import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { RoomsService } from './rooms.service';

@ApiTags('rooms')
@ApiBearerAuth()
@Controller('rooms')
export class RoomsController {
  constructor(
    private readonly rooms: RoomsService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Get(':roomId')
  async getRoom(
    @Param('roomId') roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    return this.rooms.getRoom(roomId, identity);
  }

  @Post(':roomId/join')
  async joinRoom(
    @Param('roomId') roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const room = await this.rooms.joinRoom(roomId, identity);
    this.realtime.publish(identity.appId, roomId, 'room.state', room);
    const member = room.members.find((candidate) => candidate.id === identity.userId);
    if (member) {
      this.realtime.publish(identity.appId, roomId, 'member.updated', member);
    }
    return room;
  }

  @Post(':roomId/leave')
  async leaveRoom(
    @Param('roomId') roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
    @Body() _body: Record<string, unknown> = {},
  ) {
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
