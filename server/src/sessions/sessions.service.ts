import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { ExternalIdentity, StudySessionDto, StudySessionStatus } from '../domain';

@Injectable()
export class SessionsService {
  private readonly sessions = new Map<string, StudySessionDto>();

  async start(roomId: string, identity: ExternalIdentity): Promise<StudySessionDto> {
    const session: StudySessionDto = {
      id: randomUUID(),
      appId: identity.appId,
      roomId,
      userId: identity.userId,
      status: 'running',
      startedAt: new Date().toISOString(),
    };
    this.sessions.set(session.id, session);
    return { ...session };
  }

  async pause(sessionId: string): Promise<StudySessionDto> {
    return this.transition(sessionId, 'paused', ['running']);
  }

  async resume(sessionId: string): Promise<StudySessionDto> {
    return this.transition(sessionId, 'running', ['paused']);
  }

  async finish(sessionId: string): Promise<StudySessionDto> {
    const session = await this.transition(sessionId, 'finished', ['running', 'paused']);
    session.finishedAt = new Date().toISOString();
    this.sessions.set(session.id, session);
    return { ...session };
  }

  private async transition(
    sessionId: string,
    status: StudySessionStatus,
    allowedFrom: StudySessionStatus[],
  ): Promise<StudySessionDto> {
    const session = this.sessions.get(sessionId);
    if (!session) {
      throw new NotFoundException('Study session not found');
    }
    if (!allowedFrom.includes(session.status)) {
      throw new BadRequestException(`Cannot move session from ${session.status} to ${status}`);
    }
    const next = { ...session, status };
    this.sessions.set(sessionId, next);
    return { ...next };
  }
}

