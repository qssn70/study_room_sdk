import { Logger } from '@nestjs/common';
import {
  ConnectedSocket,
  MessageBody,
  OnGatewayConnection,
  SubscribeMessage,
  WebSocketGateway,
  WebSocketServer,
} from '@nestjs/websockets';
import { Server, Socket } from 'socket.io';

@WebSocketGateway({
  namespace: 'realtime',
  cors: { origin: '*' },
})
export class RealtimeGateway implements OnGatewayConnection {
  @WebSocketServer()
  server!: Server;

  private readonly logger = new Logger(RealtimeGateway.name);

  handleConnection(client: Socket) {
    const token = client.handshake.auth.token ?? client.handshake.query.token;
    if (!token) {
      client.disconnect(true);
      return;
    }
    this.logger.debug(`Realtime client connected: ${client.id}`);
  }

  @SubscribeMessage('room.join')
  joinRoom(
    @ConnectedSocket() client: Socket,
    @MessageBody() body: { roomId?: string; appId?: string },
  ) {
    if (!body.roomId || !body.appId) {
      return { ok: false, error: 'roomId and appId are required' };
    }
    client.join(this.roomTopic(body.appId, body.roomId));
    return { ok: true };
  }

  publish(appId: string, roomId: string, type: string, payload: unknown) {
    this.server.to(this.roomTopic(appId, roomId)).emit('study-room.event', {
      type,
      payload,
    });
  }

  private roomTopic(appId: string, roomId: string): string {
    return `${appId}:${roomId}`;
  }
}

