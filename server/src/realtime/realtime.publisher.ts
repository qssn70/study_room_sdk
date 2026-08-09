import { Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { Namespace } from 'socket.io';
import {
  RealtimeEnvelopeWire,
  realtimeSchemaVersion,
  toRealtimeEnvelopeWire,
} from '../generated/contract-types';
import { RedisService } from '../redis/redis.service';

export const REALTIME_CONTROL_CHANNEL = 'study-room:realtime-control';
export type RealtimeEnvelope = RealtimeEnvelopeWire;
type RealtimeEventType = RealtimeEnvelopeWire['type'];
type EventOf<T extends RealtimeEventType> = Extract<RealtimeEnvelopeWire, { type: T }>;

@Injectable()
export class RealtimePublisher {
  private server?: Namespace;

  constructor(private readonly redis: RedisService) {}

  bind(server: Namespace) {
    this.server = server;
  }

  publishRoom<T extends RealtimeEventType>(
    appId: string,
    roomId: EventOf<T>['roomId'],
    type: T,
    payload: EventOf<T>['payload'],
    roomVersion: EventOf<T>['roomVersion'],
  ) {
    this.server?.to(this.roomTopic(appId, roomId)).emit(
      'study-room.event',
      this.envelope(type, payload, roomId, roomVersion),
    );
  }

  publishUser<T extends RealtimeEventType>(
    appId: string,
    userId: string,
    type: T,
    payload: EventOf<T>['payload'],
    roomId: EventOf<T>['roomId'],
    roomVersion: EventOf<T>['roomVersion'],
  ) {
    this.server?.to(this.userTopic(appId, userId)).emit(
      'study-room.event',
      this.envelope(type, payload, roomId, roomVersion),
    );
  }

  async evictUser(appId: string, roomId: string, userId: string) {
    await this.server?.in(this.userTopic(appId, userId)).socketsLeave(this.roomTopic(appId, roomId));
    await this.redis.publish(
      REALTIME_CONTROL_CHANNEL,
      JSON.stringify({ type: 'room.evict', appId, roomId, userId }),
    );
  }

  async disconnectApp(appId: string) {
    this.server?.in(this.appTopic(appId)).disconnectSockets(true);
  }

  roomTopic(appId: string, roomId: string) {
    return `room:${JSON.stringify([appId, roomId])}`;
  }

  userTopic(appId: string, userId: string) {
    return `user:${JSON.stringify([appId, userId])}`;
  }

  appTopic(appId: string) {
    return `app:${JSON.stringify([appId])}`;
  }

  private envelope<T extends RealtimeEventType>(
    type: T,
    payload: EventOf<T>['payload'],
    roomId: EventOf<T>['roomId'],
    roomVersion: EventOf<T>['roomVersion'],
  ): EventOf<T> {
    return toRealtimeEnvelopeWire({
      schemaVersion: realtimeSchemaVersion,
      eventId: randomUUID(),
      type,
      roomId,
      roomVersion,
      occurredAt: new Date().toISOString(),
      payload,
    } as EventOf<T>) as EventOf<T>;
  }
}
