import { Controller, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SessionsService } from './sessions.service';

@ApiTags('sessions')
@ApiBearerAuth()
@Controller()
export class SessionsController {
  constructor(
    private readonly sessions: SessionsService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Post('rooms/:roomId/sessions/start')
  async start(
    @Param('roomId') roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const session = await this.sessions.start(roomId, identity);
    this.realtime.publish(identity.appId, roomId, 'session.updated', session);
    this.realtime.publishMemberPresence(session.appId, session.roomId, session.userId);
    return session;
  }

  @Post('sessions/:sessionId/pause')
  async pause(
    @Param('sessionId') sessionId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const session = await this.sessions.pause(sessionId, identity);
    this.realtime.publish(session.appId, session.roomId, 'session.updated', session);
    this.realtime.publishMemberPresence(session.appId, session.roomId, session.userId);
    return session;
  }

  @Post('sessions/:sessionId/resume')
  async resume(
    @Param('sessionId') sessionId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const session = await this.sessions.resume(sessionId, identity);
    this.realtime.publish(session.appId, session.roomId, 'session.updated', session);
    this.realtime.publishMemberPresence(session.appId, session.roomId, session.userId);
    return session;
  }

  @Post('sessions/:sessionId/finish')
  async finish(
    @Param('sessionId') sessionId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    const session = await this.sessions.finish(sessionId, identity);
    this.realtime.publish(session.appId, session.roomId, 'session.updated', session);
    this.realtime.publishMemberPresence(session.appId, session.roomId, session.userId);
    return session;
  }
}
