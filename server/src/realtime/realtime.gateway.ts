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
import { Server, Socket } from 'socket.io';
import { AuthService } from '../auth/auth.service';
import { ExternalIdentity, PresenceStatus, StudyRoomDto } from '../domain';
import { RoomsService } from '../rooms/rooms.service';

@WebSocketGateway({
  namespace: 'realtime',
  cors: { origin: '*' },
})
export class RealtimeGateway
  implements OnGatewayConnection, OnGatewayDisconnect, OnGatewayInit
{
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);

  constructor(
    private readonly auth: AuthService,
    private readonly rooms: RoomsService,
  ) {}

  afterInit(server: Server) {
    server.use((socket, next) => {
      const token = socket.handshake.auth?.token;
      if (typeof token !== 'string' || token.trim().length === 0) {
        next(new Error('Unauthorized'));
        return;
      }
      this.auth.verifyToken(token).then(
        (identity) => {
          socket.data.identity = identity;
          next();
        },
        () => next(new Error('Unauthorized')),
      );
    });
  }

  handleConnection(client: Socket) {
    this.joinedRoomsFor(client);
    this.logger.debug(`Realtime client connected: ${client.id}`);
  }

  async handleDisconnect(client: Socket) {
    const identity = client.data.identity as ExternalIdentity | undefined;
    if (!identity) {
      return;
    }
    for (const roomId of this.joinedRoomsFor(client)) {
      const room = this.rooms.unregisterConnection(roomId, identity, client.id);
      if (room) {
        this.publishPresenceSnapshot(room, identity.userId);
      }
    }
    this.joinedRoomsFor(client).clear();
  }

  @SubscribeMessage('room.join')
  async joinRoom(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string },
  ) {
    if (!body.roomId) {
      return { ok: false, error: 'roomId is required' };
    }
    const identity = this.identityFor(client);
    try {
      this.rooms.requireMember(body.roomId, identity);
    } catch {
      return { ok: false, error: 'Room membership is required' };
    }
    await client.join(this.roomTopic(identity.appId, body.roomId));
    this.joinedRoomsFor(client).add(body.roomId);
    const room = this.rooms.registerConnection(body.roomId, identity, client.id);
    this.publishPresenceSnapshot(room, identity.userId);
    return { ok: true };
  }

  @SubscribeMessage('room.leave')
  async leaveRoom(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string },
  ) {
    if (!body.roomId) {
      return { ok: false, error: 'roomId is required' };
    }
    const identity = this.identityFor(client);
    this.joinedRoomsFor(client).delete(body.roomId);
    await client.leave(this.roomTopic(identity.appId, body.roomId));
    const room = this.rooms.unregisterConnection(body.roomId, identity, client.id);
    if (room) {
      this.publishPresenceSnapshot(room, identity.userId);
    }
    return { ok: true };
  }

  @SubscribeMessage('presence.update')
  async updatePresence(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string; status?: string },
  ) {
    if (!body.roomId || !body.status) {
      return { ok: false, error: 'roomId and status are required' };
    }
    if (!this.joinedRoomsFor(client).has(body.roomId)) {
      return { ok: false, error: 'Realtime room subscription is required' };
    }
    const allowed: PresenceStatus[] = ['online', 'focusing', 'idle', 'away'];
    if (!allowed.includes(body.status as PresenceStatus)) {
      return { ok: false, error: 'Invalid presence status' };
    }
    const identity = this.identityFor(client);
    try {
      const room = this.rooms.updateConnectionPresence(
        body.roomId,
        identity,
        client.id,
        body.status as Exclude<PresenceStatus, 'offline'>,
      );
      this.publishPresenceSnapshot(room, identity.userId);
      return { ok: true };
    } catch {
      return { ok: false, error: 'Room membership is required' };
    }
  }

  publish(appId: string, roomId: string, type: string, payload: unknown) {
    this.server.to(this.roomTopic(appId, roomId)).emit('study-room.event', {
      type,
      roomId,
      payload,
    });
  }

  publishMemberPresence(appId: string, roomId: string, userId: string) {
    const room = this.rooms.roomSnapshot(appId, roomId);
    if (room) {
      this.publishPresenceSnapshot(room, userId);
    }
  }

  private roomTopic(appId: string, roomId: string): string {
    return JSON.stringify([appId, roomId]);
  }

  private identityFor(client: Socket): ExternalIdentity {
    return client.data.identity as ExternalIdentity;
  }

  private joinedRoomsFor(client: Socket): Set<string> {
    const existing = client.data.joinedRoomIds;
    if (existing instanceof Set) {
      return existing as Set<string>;
    }
    const joinedRoomIds = new Set<string>();
    client.data.joinedRoomIds = joinedRoomIds;
    return joinedRoomIds;
  }

  private publishPresenceSnapshot(room: StudyRoomDto, userId: string) {
    const member = room.members.find((candidate) => candidate.id === userId);
    this.publish(room.appId, room.id, 'room.state', room);
    if (member) {
      this.publish(room.appId, room.id, 'member.updated', member);
    }
  }
}

