import { Body, Controller, Get, Param, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import {
  ListActiveSessionsParamsDto,
  ListActiveSessionsQueryDto,
  StartSessionParamsDto,
  UpdateSessionBodyDto,
  UpdateSessionParamsDto,
} from '../generated/request-dtos';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { RoomsService } from '../rooms/rooms.service';
import { SessionsService } from './sessions.service';

@ApiTags('sessions')
@ApiBearerAuth()
@Controller('v1')
export class SessionsController {
  constructor(
    private readonly sessions: SessionsService,
    private readonly realtime: RealtimePublisher,
    private readonly rooms: RoomsService,
  ) {}

  @Post('rooms/:roomId/sessions')
  async start(@Param() params: StartSessionParamsDto, @CurrentIdentity() identity: ExternalIdentity) {
    const session = await this.sessions.start(params.roomId, identity);
    this.realtime.publishRoom(identity.appId, params.roomId, 'session.updated', session, null);
    await this.publishPresence(identity, params.roomId);
    return session;
  }

  @Get('rooms/:roomId/active-sessions')
  listActive(
    @Param() params: ListActiveSessionsParamsDto,
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: ListActiveSessionsQueryDto,
  ) {
    return this.sessions.listActive(params.roomId, identity, query.cursor, query.limit);
  }

  @Patch('sessions/:sessionId')
  async update(
    @Param() params: UpdateSessionParamsDto,
    @Body() body: UpdateSessionBodyDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const session = await this.sessions.update(params.sessionId, body.status, identity);
    this.realtime.publishRoom(identity.appId, session.roomId, 'session.updated', session, null);
    await this.publishPresence(identity, session.roomId);
    return session;
  }

  private async publishPresence(identity: ExternalIdentity, roomId: string) {
    const room = await this.rooms.snapshot(identity.appId, roomId);
    const member = room?.members.find((candidate) => candidate.id === identity.userId);
    if (room && member) {
      this.realtime.publishRoom(
        identity.appId,
        roomId,
        'member.presence.updated',
        member,
        room.version,
      );
    }
  }
}
