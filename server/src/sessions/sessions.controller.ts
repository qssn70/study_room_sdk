import { Controller, Headers, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../auth/auth.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { SessionsService } from './sessions.service';

@ApiTags('sessions')
@ApiBearerAuth()
@Controller()
export class SessionsController {
  constructor(
    private readonly auth: AuthService,
    private readonly sessions: SessionsService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Post('rooms/:roomId/sessions/start')
  async start(
    @Param('roomId') roomId: string,
    @Headers('authorization') authorization?: string,
  ) {
    const identity = await this.auth.verifyBearer(authorization);
    const session = await this.sessions.start(roomId, identity);
    this.realtime.publish(identity.appId, roomId, 'session.updated', session);
    return session;
  }

  @Post('sessions/:sessionId/pause')
  async pause(@Param('sessionId') sessionId: string) {
    const session = await this.sessions.pause(sessionId);
    this.realtime.publish(session.appId, session.roomId, 'session.updated', session);
    return session;
  }

  @Post('sessions/:sessionId/resume')
  async resume(@Param('sessionId') sessionId: string) {
    const session = await this.sessions.resume(sessionId);
    this.realtime.publish(session.appId, session.roomId, 'session.updated', session);
    return session;
  }

  @Post('sessions/:sessionId/finish')
  async finish(@Param('sessionId') sessionId: string) {
    const session = await this.sessions.finish(sessionId);
    this.realtime.publish(session.appId, session.roomId, 'session.updated', session);
    return session;
  }
}
