import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  OnGatewayDisconnect,
  OnGatewayInit,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { createAdapter } from '@socket.io/redis-adapter';
import { Namespace, Socket } from 'socket.io';
import { APPLICATION_CHANGE_CHANNEL } from '../applications/applications.service';
import { AuthService } from '../auth/auth.service';
import { ExternalIdentity } from '../domain';
import { RedisService } from '../redis/redis.service';
import { RoomsService } from '../rooms/rooms.service';
import { PresenceService } from './presence.service';
import { REALTIME_CONTROL_CHANNEL, RealtimePublisher } from './realtime.publisher';

const configuredOrigins = (process.env.STUDY_ROOM_ALLOWED_ORIGINS ?? 'http://localhost:3000,http://localhost:8080')
  .split(',')
  .map((value) => value.trim())
  .filter(Boolean);

@WebSocketGateway({
  namespace: '/v1/realtime',
  cors: { origin: configuredOrigins },
  transports: ['websocket'],
})
export class RealtimeGateway implements OnGatewayConnection, OnGatewayDisconnect, OnGatewayInit {
  @WebSocketServer()
  server!: Namespace;

  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    private readonly auth: AuthService,
    private readonly rooms: RoomsService,
    private readonly presence: PresenceService,
    private readonly redis: RedisService,
    private readonly publisher: RealtimePublisher,
  ) {}

  async afterInit(server: Namespace) {
    this.server = server;
    server.server.adapter(createAdapter(this.redis.publisher, this.redis.adapterSubscriber));
    this.publisher.bind(server);
    server.use((socket, next) => {
      const token = socket.handshake.auth?.token;
      if (typeof token !== 'string' || token.trim().length === 0) {
        next(new Error('Unauthorized'));
        return;
      }
      this.auth.verifyUserToken(token).then(
        async (identity) => {
          socket.data.identity = identity;
          await Promise.all([
            socket.join(this.publisher.userTopic(identity.appId, identity.userId)),
            socket.join(this.publisher.appTopic(identity.appId)),
          ]);
        },
      ).then(
        () => next(),
        () => next(new Error('Unauthorized')),
      );
    });
    await this.redis.subscribe(APPLICATION_CHANGE_CHANNEL, async (message) => {
      const event = JSON.parse(message) as { appId: string; enabled: boolean };
      if (!event.enabled) await this.publisher.disconnectApp(event.appId);
    });
    await this.redis.subscribe(REALTIME_CONTROL_CHANNEL, async (message) => {
      const event = JSON.parse(message) as {
        type: string;
        appId: string;
        roomId: string;
        userId: string;
      };
      if (event.type === 'room.evict') await this.handleRoomEviction(event);
    });
  }

  async handleConnection(client: Socket) {
    const identity = this.identityFor(client);
    await client.join(this.publisher.userTopic(identity.appId, identity.userId));
    await client.join(this.publisher.appTopic(identity.appId));
    this.joinedRoomsFor(client);
    this.scheduleExpiry(client, identity.expiresAt);
    client.data.presenceTimer = setInterval(
      () => void this.refreshPresence(client),
      this.presence.refreshSeconds * 1000,
    );
    this.logger.debug(`Realtime client connected: ${client.id}`);
  }

  async handleDisconnect(client: Socket) {
    clearTimeout(client.data.expiryTimer as NodeJS.Timeout | undefined);
    clearInterval(client.data.presenceTimer as NodeJS.Timeout | undefined);
    const identity = client.data.identity as ExternalIdentity | undefined;
    if (!identity) return;
    for (const roomId of this.joinedRoomsFor(client)) {
      await this.presence.unregister(identity.appId, roomId, identity.userId, client.id);
      await this.publishPresence(identity.appId, roomId, identity.userId);
    }
    this.joinedRoomsFor(client).clear();
  }

  @SubscribeMessage('room.subscribe')
  async subscribeRoom(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string },
  ) {
    if (!body?.roomId) return { ok: false, error: { code: 'invalid_request', message: 'roomId is required' } };
    const identity = this.identityFor(client);
    if (!(await this.rooms.isMember(body.roomId, identity))) {
      return { ok: false, error: { code: 'membership_required', message: 'Room membership is required' } };
    }
    await client.join(this.publisher.roomTopic(identity.appId, body.roomId));
    this.joinedRoomsFor(client).add(body.roomId);
    await this.presence.register(identity.appId, body.roomId, identity.userId, client.id);
    await this.publishPresence(identity.appId, body.roomId, identity.userId);
    return { ok: true };
  }

  @SubscribeMessage('room.unsubscribe')
  async unsubscribeRoom(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string },
  ) {
    if (!body?.roomId) return { ok: false, error: { code: 'invalid_request', message: 'roomId is required' } };
    const identity = this.identityFor(client);
    this.joinedRoomsFor(client).delete(body.roomId);
    await client.leave(this.publisher.roomTopic(identity.appId, body.roomId));
    await this.presence.unregister(identity.appId, body.roomId, identity.userId, client.id);
    await this.publishPresence(identity.appId, body.roomId, identity.userId);
    return { ok: true };
  }

  @SubscribeMessage('presence.set-away')
  async setAway(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string; away?: boolean },
  ) {
    if (!body?.roomId || typeof body.away !== 'boolean') {
      return { ok: false, error: { code: 'invalid_request', message: 'roomId and away are required' } };
    }
    if (!this.joinedRoomsFor(client).has(body.roomId)) {
      return { ok: false, error: { code: 'subscription_required', message: 'Realtime room subscription is required' } };
    }
    const identity = this.identityFor(client);
    if (!(await this.rooms.isMember(body.roomId, identity))) {
      await this.publisher.evictUser(identity.appId, body.roomId, identity.userId);
      return { ok: false, error: { code: 'membership_required', message: 'Room membership is required' } };
    }
    await this.presence.setAway(
      identity.appId,
      body.roomId,
      identity.userId,
      client.id,
      body.away,
    );
    await this.publishPresence(identity.appId, body.roomId, identity.userId);
    return { ok: true };
  }

  private async refreshPresence(client: Socket) {
    const identity = client.data.identity as ExternalIdentity | undefined;
    if (!identity) return;
    for (const roomId of this.joinedRoomsFor(client)) {
      await this.presence.refresh(identity.appId, roomId, identity.userId, client.id);
    }
  }

  private async publishPresence(appId: string, roomId: string, userId: string) {
    const room = await this.rooms.snapshot(appId, roomId);
    const member = room?.members.find((candidate) => candidate.id === userId);
    if (room && member) {
      this.publisher.publishRoom(
        appId,
        roomId,
        'member.presence.updated',
        member,
        room.version,
      );
    }
  }

  private async handleRoomEviction(event: { appId: string; roomId: string; userId: string }) {
    let evictedConnection = false;
    for (const client of this.server.sockets.values()) {
      const identity = client.data.identity as ExternalIdentity | undefined;
      if (identity?.appId !== event.appId || identity.userId !== event.userId) continue;
      const rooms = this.joinedRoomsFor(client);
      if (!rooms.delete(event.roomId)) continue;
      await client.leave(this.publisher.roomTopic(event.appId, event.roomId));
      await this.presence.unregister(event.appId, event.roomId, event.userId, client.id);
      evictedConnection = true;
    }
    if (evictedConnection) {
      await this.publishPresence(event.appId, event.roomId, event.userId);
    }
  }

  private scheduleExpiry(client: Socket, expiresAt: Date) {
    const maximumDelay = 2_147_483_647;
    const remaining = Math.max(0, expiresAt.getTime() - Date.now());
    client.data.expiryTimer = setTimeout(() => {
      if (expiresAt.getTime() - Date.now() > 0) {
        this.scheduleExpiry(client, expiresAt);
        return;
      }
      client.emit('study-room.auth-expired', { code: 'token_expired' });
      client.disconnect(true);
    }, Math.min(remaining, maximumDelay));
  }

  private identityFor(client: Socket): ExternalIdentity {
    return client.data.identity as ExternalIdentity;
  }

  private joinedRoomsFor(client: Socket): Set<string> {
    const existing = client.data.joinedRoomIds;
    if (existing instanceof Set) return existing as Set<string>;
    const rooms = new Set<string>();
    client.data.joinedRoomIds = rooms;
    return rooms;
  }
}
