import { Body, Controller, Get, Headers, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../auth/auth.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { RoomsService } from './rooms.service';

@ApiTags('rooms')
@ApiBearerAuth()
@Controller('rooms')
export class RoomsController {
  constructor(
    private readonly auth: AuthService,
    private readonly rooms: RoomsService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Get(':roomId')
  async getRoom(
    @Param('roomId') roomId: string,
    @Headers('authorization') authorization?: string,
  ) {
    const identity = await this.auth.verifyBearer(authorization);
    return this.rooms.getRoom(roomId, identity.appId);
  }

  @Post(':roomId/join')
  async joinRoom(
    @Param('roomId') roomId: string,
    @Headers('authorization') authorization?: string,
  ) {
    const identity = await this.auth.verifyBearer(authorization);
    const room = await this.rooms.joinRoom(roomId, identity);
    this.realtime.publish(identity.appId, roomId, 'room.state', room);
    this.realtime.publish(identity.appId, roomId, 'member.updated', {
      id: identity.userId,
      displayName: identity.displayName,
      avatarUrl: identity.avatarUrl,
      status: 'online',
    });
    return room;
  }

  @Post(':roomId/leave')
  async leaveRoom(
    @Param('roomId') roomId: string,
    @Headers('authorization') authorization?: string,
    @Body() _body: Record<string, unknown> = {},
  ) {
    const identity = await this.auth.verifyBearer(authorization);
    const room = await this.rooms.leaveRoom(roomId, identity);
    this.realtime.publish(identity.appId, roomId, 'room.state', room);
    this.realtime.publish(identity.appId, roomId, 'member.updated', {
      id: identity.userId,
      displayName: identity.displayName,
      avatarUrl: identity.avatarUrl,
      status: 'offline',
    });
    return room;
  }
}
