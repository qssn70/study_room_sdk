import {
  BadRequestException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { randomUUID } from 'crypto';
import { ExternalIdentity, StudySessionDto, StudySessionStatus } from '../domain';
import { RoomsService } from '../rooms/rooms.service';

@Injectable()
export class SessionsService {
  private readonly sessions = new Map<string, StudySessionDto>();

  constructor(private readonly rooms: RoomsService) {}

  async start(roomId: string, identity: ExternalIdentity): Promise<StudySessionDto> {
    this.rooms.requireMember(roomId, identity);
    const session: StudySessionDto = {
      id: randomUUID(),
      appId: identity.appId,
      roomId,
      userId: identity.userId,
      status: 'running',
      startedAt: new Date().toISOString(),
    };
    this.sessions.set(session.id, session);
    this.rooms.setMemberPresenceIfPresent(
      session.appId,
      session.roomId,
      session.userId,
      'focusing',
    );
    return { ...session };
  }

  async pause(sessionId: string, identity: ExternalIdentity): Promise<StudySessionDto> {
    return this.transition(sessionId, identity, 'paused', ['running']);
  }

  async resume(sessionId: string, identity: ExternalIdentity): Promise<StudySessionDto> {
    return this.transition(sessionId, identity, 'running', ['paused']);
  }

  async finish(sessionId: string, identity: ExternalIdentity): Promise<StudySessionDto> {
    const session = await this.transition(
      sessionId,
      identity,
      'finished',
      ['running', 'paused'],
    );
    session.finishedAt = new Date().toISOString();
    this.sessions.set(session.id, session);
    return { ...session };
  }

  private async transition(
    sessionId: string,
    identity: ExternalIdentity,
    status: StudySessionStatus,
    allowedFrom: StudySessionStatus[],
  ): Promise<StudySessionDto> {
    const session = this.sessions.get(sessionId);
    if (!session || session.appId !== identity.appId) {
      throw new NotFoundException('Study session not found');
    }
    if (session.userId !== identity.userId) {
      throw new ForbiddenException('Only the session creator can control this session');
    }
    if (!allowedFrom.includes(session.status)) {
      throw new BadRequestException(`Cannot move session from ${session.status} to ${status}`);
    }
    const next = { ...session, status };
    this.sessions.set(sessionId, next);
    this.rooms.setMemberPresenceIfPresent(
      next.appId,
      next.roomId,
      next.userId,
      status === 'running' ? 'focusing' : 'idle',
    );
    return { ...next };
  }
}

