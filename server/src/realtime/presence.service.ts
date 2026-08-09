import { Injectable } from '@nestjs/common';
import { SessionStatus } from '@prisma/client';
import { PresenceStatus } from '../domain';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

interface ConnectionPresence {
  userId: string;
  away: boolean;
}

@Injectable()
export class PresenceService {
  readonly ttlSeconds = this.integerEnvironment('STUDY_ROOM_PRESENCE_TTL_SECONDS', 60, 3, 3600);
  readonly refreshSeconds = this.integerEnvironment('STUDY_ROOM_PRESENCE_REFRESH_SECONDS', 20, 1, 3599);

  constructor(private readonly redis: RedisService, private readonly prisma: PrismaService) {
    if (this.refreshSeconds >= this.ttlSeconds) {
      throw new Error('STUDY_ROOM_PRESENCE_REFRESH_SECONDS must be less than the presence TTL');
    }
  }

  async register(appId: string, roomId: string, userId: string, socketId: string) {
    await this.write(appId, roomId, userId, socketId, false);
  }

  async setAway(appId: string, roomId: string, userId: string, socketId: string, away: boolean) {
    await this.write(appId, roomId, userId, socketId, away);
  }

  async refresh(appId: string, roomId: string, _userId: string, socketId: string) {
    const connectionKey = this.connectionKey(appId, roomId, socketId);
    const indexKey = this.roomIndexKey(appId, roomId);
    const refreshed = await this.redis.client.expire(connectionKey, this.ttlSeconds);
    if (refreshed) {
      await this.redis.client.expire(indexKey, this.ttlSeconds * 2);
    } else {
      await this.redis.client.sRem(indexKey, connectionKey);
    }
  }

  async unregister(appId: string, roomId: string, _userId: string, socketId: string) {
    const connectionKey = this.connectionKey(appId, roomId, socketId);
    await Promise.all([
      this.redis.client.del(connectionKey),
      this.redis.client.sRem(this.roomIndexKey(appId, roomId), connectionKey),
    ]);
  }

  async removeUser(appId: string, roomId: string, userId: string) {
    const indexKey = this.roomIndexKey(appId, roomId);
    const keys = await this.redis.client.sMembers(indexKey);
    if (!keys.length) return;
    const values = await this.redis.client.mGet(keys);
    const targets = keys.filter((_, index) => this.parse(values[index])?.userId === userId);
    if (!targets.length) return;
    await Promise.all([
      this.redis.client.del(targets),
      this.redis.client.sRem(indexKey, targets),
    ]);
  }

  async statusFor(appId: string, roomId: string, userId: string): Promise<PresenceStatus> {
    return (await this.statusesFor(appId, roomId, [userId])).get(userId) ?? 'offline';
  }

  async statusesFor(appId: string, roomId: string, userIds: readonly string[]) {
    const statuses = new Map<string, PresenceStatus>(userIds.map((userId) => [userId, 'offline']));
    if (!userIds.length) return statuses;

    const requested = new Set(userIds);
    const indexKey = this.roomIndexKey(appId, roomId);
    const keys = await this.redis.client.sMembers(indexKey);
    const values = keys.length ? await this.redis.client.mGet(keys) : [];
    const connections = new Map<string, ConnectionPresence[]>();
    const stale: string[] = [];
    values.forEach((value, index) => {
      const parsed = this.parse(value);
      if (!parsed) {
        stale.push(keys[index]);
        return;
      }
      if (!requested.has(parsed.userId)) return;
      const current = connections.get(parsed.userId) ?? [];
      current.push(parsed);
      connections.set(parsed.userId, current);
    });
    if (stale.length) await this.redis.client.sRem(indexKey, stale);

    const sessions = await this.prisma.studySession.findMany({
      where: {
        appId,
        roomId,
        userId: { in: [...requested] },
        status: { in: [SessionStatus.RUNNING, SessionStatus.PAUSED] },
      },
      select: { userId: true, status: true },
    });
    const sessionsByUser = new Map<string, SessionStatus>();
    for (const session of sessions) {
      const current = sessionsByUser.get(session.userId);
      if (current !== SessionStatus.RUNNING) sessionsByUser.set(session.userId, session.status);
    }

    for (const userId of requested) {
      const activeConnections = connections.get(userId) ?? [];
      if (!activeConnections.length) continue;
      const session = sessionsByUser.get(userId);
      if (session === SessionStatus.RUNNING) statuses.set(userId, 'focusing');
      else if (session === SessionStatus.PAUSED) statuses.set(userId, 'idle');
      else if (activeConnections.every((connection) => connection.away)) statuses.set(userId, 'away');
      else statuses.set(userId, 'online');
    }
    return statuses;
  }

  private async write(appId: string, roomId: string, userId: string, socketId: string, away: boolean) {
    const connectionKey = this.connectionKey(appId, roomId, socketId);
    const indexKey = this.roomIndexKey(appId, roomId);
    await Promise.all([
      this.redis.client.set(connectionKey, JSON.stringify({ userId, away }), { EX: this.ttlSeconds }),
      this.redis.client.sAdd(indexKey, connectionKey),
    ]);
    await this.redis.client.expire(indexKey, this.ttlSeconds * 2);
  }

  private parse(value: string | null): ConnectionPresence | undefined {
    if (!value) return undefined;
    try {
      const parsed = JSON.parse(value) as Partial<ConnectionPresence>;
      if (typeof parsed.userId !== 'string' || typeof parsed.away !== 'boolean') return undefined;
      return { userId: parsed.userId, away: parsed.away };
    } catch {
      return undefined;
    }
  }

  private roomIndexKey(appId: string, roomId: string) {
    return `study-room:presence-room:${this.segment(appId)}:${this.segment(roomId)}`;
  }

  private connectionKey(appId: string, roomId: string, socketId: string) {
    return `study-room:presence-connection:${this.segment(appId)}:${this.segment(roomId)}:${this.segment(socketId)}`;
  }

  private segment(value: string) {
    return encodeURIComponent(value);
  }

  private integerEnvironment(name: string, fallback: number, minimum: number, maximum: number) {
    const value = Number(process.env[name] ?? fallback);
    if (!Number.isSafeInteger(value) || value < minimum || value > maximum) {
      throw new Error(`${name} must be an integer between ${minimum} and ${maximum}`);
    }
    return value;
  }
}
