import { BadRequestException, ConflictException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { Prisma, SessionStatus } from '@prisma/client';
import { ExternalIdentity, StudySessionDto, StudySessionStatus } from '../domain';
import { PrismaService } from '../prisma/prisma.service';
import { RoomsService } from '../rooms/rooms.service';

@Injectable()
export class SessionsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rooms: RoomsService,
  ) {}

  async start(roomId: string, identity: ExternalIdentity): Promise<StudySessionDto> {
    await this.rooms.requireMember(roomId, identity);
    try {
      const session = await this.prisma.$transaction((tx) => tx.studySession.create({
          data: { roomId, appId: identity.appId, userId: identity.userId },
        }));
      return this.toDto(session);
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        throw new ConflictException('An active study session already exists');
      }
      throw error;
    }
  }

  async update(
    sessionId: string,
    status: StudySessionStatus,
    identity: ExternalIdentity,
  ): Promise<StudySessionDto> {
    const next = status.toUpperCase() as SessionStatus;
    const updated = await this.prisma.$transaction(async (tx) => {
      const session = await tx.studySession.findFirst({
        where: { id: sessionId, appId: identity.appId },
      });
      if (!session) throw new NotFoundException('Study session not found');
      if (session.userId !== identity.userId) {
        throw new ForbiddenException('Only the session creator can control this session');
      }
      const allowed = session.status === 'RUNNING'
        ? ['PAUSED', 'FINISHED']
        : session.status === 'PAUSED'
          ? ['RUNNING', 'FINISHED']
          : [];
      if (!allowed.includes(next)) {
        throw new BadRequestException(`Cannot move session from ${session.status.toLowerCase()} to ${status}`);
      }
      const changed = await tx.studySession.updateMany({
        where: { id: session.id, status: session.status },
        data: { status: next, finishedAt: next === 'FINISHED' ? new Date() : null },
      });
      if (changed.count !== 1) {
        throw new ConflictException('Study session changed concurrently');
      }
      return tx.studySession.findUniqueOrThrow({ where: { id: session.id } });
    });
    return this.toDto(updated);
  }

  async listActive(roomId: string, identity: ExternalIdentity, cursor?: string, limit = 50) {
    await this.rooms.requireMember(roomId, identity);
    const take = Math.min(Math.max(limit, 1), 100);
    const sessions = await this.prisma.studySession.findMany({
      where: {
        appId: identity.appId,
        roomId,
        status: { in: [SessionStatus.RUNNING, SessionStatus.PAUSED] },
      },
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      take: take + 1,
    });
    const hasMore = sessions.length > take;
    if (hasMore) sessions.pop();
    return {
      items: sessions.map((session) => this.toDto(session)),
      nextCursor: hasMore ? sessions.at(-1)?.id ?? null : null,
    };
  }

  private toDto(session: {
    id: string;
    roomId: string;
    userId: string;
    status: SessionStatus;
    startedAt: Date;
    finishedAt: Date | null;
    updatedAt: Date;
  }): StudySessionDto {
    return {
      id: session.id,
      roomId: session.roomId,
      userId: session.userId,
      status: session.status.toLowerCase() as StudySessionStatus,
      startedAt: session.startedAt.toISOString(),
      finishedAt: session.finishedAt?.toISOString() ?? null,
      updatedAt: session.updatedAt.toISOString(),
    };
  }
}
