import { Body, Controller, Get, Param, ParseUUIDPipe, Patch, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { RoomsService } from '../rooms/rooms.service';
import { SessionPageQueryDto, UpdateSessionDto } from './sessions.dto';
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
  async start(@Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string, @CurrentIdentity() identity: ExternalIdentity) {
    const session = await this.sessions.start(roomId, identity);
    this.realtime.publishRoom(identity.appId, roomId, 'session.updated', session, null);
    await this.publishPresence(identity, roomId);
    return session;
  }

  @Get('rooms/:roomId/active-sessions')
  listActive(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: SessionPageQueryDto,
  ) {
    return this.sessions.listActive(roomId, identity, query.cursor, query.limit);
  }

  @Patch('sessions/:sessionId')
  async update(
    @Param('sessionId', new ParseUUIDPipe({ version: '4' })) sessionId: string,
    @Body() body: UpdateSessionDto,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const session = await this.sessions.update(sessionId, body.status, identity);
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
