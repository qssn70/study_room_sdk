import { SessionStatus } from '@prisma/client';
import { PresenceService } from '../src/realtime/presence.service';
import { REALTIME_CONTROL_CHANNEL, RealtimePublisher } from '../src/realtime/realtime.publisher';

describe('PresenceService authoritative aggregation', () => {
  function setup() {
    const client = {
      set: jest.fn(async () => 'OK'),
      expire: jest.fn(async () => true),
      del: jest.fn(async () => 1),
      mGet: jest.fn(async () => [] as Array<string | null>),
      sAdd: jest.fn(async () => 1),
      sRem: jest.fn(async () => 1),
      sMembers: jest.fn(async () => [] as string[]),
    };
    const prisma = { studySession: { findMany: jest.fn(async () => [] as Array<{ userId: string; status: SessionStatus }>) } };
    return {
      client,
      prisma,
      service: new PresenceService({ client } as never, prisma as never),
    };
  }

  it('registers, refreshes, marks away, unregisters, and removes a user', async () => {
    const { client, service } = setup();
    await service.register('app', 'room', 'user', 'socket');
    await service.setAway('app', 'room', 'user', 'socket', true);
    await service.refresh('app', 'room', 'user', 'socket');
    await service.unregister('app', 'room', 'user', 'socket');
    client.sMembers.mockResolvedValue(['one', 'two']);
    client.mGet.mockResolvedValue([
      JSON.stringify({ userId: 'user', away: false }),
      JSON.stringify({ userId: 'other', away: false }),
    ]);
    await service.removeUser('app', 'room', 'user');

    expect(client.set).toHaveBeenCalledWith(
      expect.stringContaining('socket'),
      JSON.stringify({ userId: 'user', away: false }),
      { EX: 60 },
    );
    expect(client.set).toHaveBeenCalledWith(
      expect.stringContaining('socket'),
      JSON.stringify({ userId: 'user', away: true }),
      { EX: 60 },
    );
    expect(client.sAdd).toHaveBeenCalled();
    expect(client.del).toHaveBeenCalledWith(['one']);
  });

  it.each([
    [[], [], [], 'offline'],
    [['key'], [JSON.stringify({ userId: 'user', away: true })], [], 'away'],
    [['key'], [JSON.stringify({ userId: 'user', away: false })], [], 'online'],
    [['key'], [JSON.stringify({ userId: 'user', away: true })], [SessionStatus.PAUSED], 'idle'],
    [['key'], [JSON.stringify({ userId: 'user', away: true })], [SessionStatus.RUNNING], 'focusing'],
  ])('combines connections and sessions as %s', async (keys, values, sessions, expected) => {
    const { client, prisma, service } = setup();
    client.sMembers.mockResolvedValue(keys as string[]);
    client.mGet.mockResolvedValue(values as Array<string | null>);
    prisma.studySession.findMany.mockResolvedValue(
      (sessions as SessionStatus[]).map((status) => ({ userId: 'user', status })),
    );
    await expect(service.statusFor('app', 'room', 'user')).resolves.toBe(expected);
  });

  it('cleans stale room-index entries and rejects invalid timing configuration', async () => {
    const { client, service } = setup();
    client.sMembers.mockResolvedValue(['missing', 'invalid']);
    client.mGet.mockResolvedValue([null, '{']);
    await service.statusesFor('app', 'room', ['user']);
    expect(client.sRem).toHaveBeenCalledWith(expect.stringContaining('presence-room'), ['missing', 'invalid']);

    const previousTtl = process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS;
    const previousRefresh = process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS;
    process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS = '4';
    process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS = '4';
    expect(() => new PresenceService({ client } as never, { studySession: {} } as never)).toThrow();
    if (previousTtl === undefined) delete process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS;
    else process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS = previousTtl;
    if (previousRefresh === undefined) delete process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS;
    else process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS = previousRefresh;
  });

  it('removes expired refresh indexes and handles empty or unmatched user removal', async () => {
    const { client, service } = setup();
    client.expire.mockResolvedValueOnce(false);
    await service.refresh('app', 'room', 'user', 'expired-socket');
    expect(client.sRem).toHaveBeenCalledWith(
      expect.stringContaining('presence-room'),
      expect.stringContaining('expired-socket'),
    );

    client.sMembers.mockResolvedValueOnce([]);
    await service.removeUser('app', 'room', 'user');
    client.sMembers.mockResolvedValueOnce(['other-key']);
    client.mGet.mockResolvedValueOnce([JSON.stringify({ userId: 'other', away: false })]);
    await service.removeUser('app', 'room', 'user');
    expect(client.del).not.toHaveBeenCalledWith(['other-key']);
  });

  it('handles empty batches, unrelated connections, multiple sockets, and running priority', async () => {
    const { client, prisma, service } = setup();
    await expect(service.statusesFor('app', 'room', [])).resolves.toEqual(new Map());
    expect(prisma.studySession.findMany).not.toHaveBeenCalled();

    client.sMembers.mockResolvedValue(['one', 'two', 'three']);
    client.mGet.mockResolvedValue([
      JSON.stringify({ userId: 'user', away: true }),
      JSON.stringify({ userId: 'user', away: false }),
      JSON.stringify({ userId: 'unrequested', away: false }),
    ]);
    prisma.studySession.findMany.mockResolvedValue([
      { userId: 'user', status: SessionStatus.RUNNING },
      { userId: 'user', status: SessionStatus.PAUSED },
    ]);
    await expect(service.statusesFor('app', 'room', ['user'])).resolves.toEqual(
      new Map([['user', 'focusing']]),
    );

    client.sMembers.mockResolvedValue([]);
    prisma.studySession.findMany.mockResolvedValue([]);
    await expect(service.statusesFor('app', 'room', ['offline-user'])).resolves.toEqual(
      new Map([['offline-user', 'offline']]),
    );
    jest.spyOn(service, 'statusesFor').mockResolvedValue(new Map());
    await expect(service.statusFor('app', 'room', 'missing')).resolves.toBe('offline');
  });

  it('rejects malformed parsed values and every invalid environment bound', async () => {
    const { client, service } = setup();
    client.sMembers.mockResolvedValue(['missing-user', 'missing-away', 'wrong-user', 'wrong-away']);
    client.mGet.mockResolvedValue([
      '{}',
      JSON.stringify({ userId: 'user' }),
      JSON.stringify({ userId: 7, away: false }),
      JSON.stringify({ userId: 'user', away: 'false' }),
    ]);
    await service.statusesFor('app', 'room', ['user']);
    expect(client.sRem).toHaveBeenCalledWith(expect.stringContaining('presence-room'), [
      'missing-user', 'missing-away', 'wrong-user', 'wrong-away',
    ]);

    const previousTtl = process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS;
    const previousRefresh = process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS;
    delete process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS;
    for (const value of ['not-a-number', '2', '3601']) {
      process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS = value;
      expect(() => new PresenceService({ client } as never, { studySession: {} } as never)).toThrow();
    }
    if (previousTtl === undefined) delete process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS;
    else process.env.STUDY_ROOM_PRESENCE_TTL_SECONDS = previousTtl;
    if (previousRefresh === undefined) delete process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS;
    else process.env.STUDY_ROOM_PRESENCE_REFRESH_SECONDS = previousRefresh;
  });
});

describe('RealtimePublisher topics and envelopes', () => {
  function createPublisher() {
    const redis = { publish: jest.fn(async () => undefined) };
    return { redis, publisher: new RealtimePublisher(redis as never) };
  }

  it('safely drops best-effort operations before a namespace is bound', async () => {
    const { publisher, redis } = createPublisher();
    const room = { id: 'room', appId: 'app', title: 'Focus', version: 1, members: [] };
    expect(() => publisher.publishRoom('app', 'room', 'room.state', room, 1)).not.toThrow();
    expect(() => publisher.publishUser(
      'app', 'user', 'membership.updated', { roomId: 'room', active: false }, 'room', 1,
    )).not.toThrow();
    await expect(publisher.evictUser('app', 'room', 'user')).resolves.toBeUndefined();
    await expect(publisher.disconnectApp('app')).resolves.toBeUndefined();
    expect(redis.publish).toHaveBeenCalledWith(REALTIME_CONTROL_CHANNEL, expect.stringContaining('room.evict'));
  });

  it('publishes and performs cross-instance eviction/disconnect', async () => {
    const emit = jest.fn();
    const socketsLeave = jest.fn(async () => undefined);
    const disconnectSockets = jest.fn();
    const namespace = {
      to: jest.fn(() => ({ emit })),
      in: jest.fn(() => ({ socketsLeave, disconnectSockets })),
    };
    const { publisher, redis } = createPublisher();
    publisher.bind(namespace as never);
    publisher.publishRoom('app', 'room', 'room.state', {
      id: 'room', appId: 'app', title: 'Focus', version: 2, members: [],
    }, 2);
    publisher.publishUser('app', 'user', 'membership.updated', { roomId: 'room', active: false }, 'room', 3);
    await publisher.evictUser('app', 'room', 'user');
    await publisher.disconnectApp('app');
    expect(emit).toHaveBeenCalledWith('study-room.event', expect.objectContaining({
      schemaVersion: 1, eventId: expect.any(String), occurredAt: expect.any(String),
    }));
    expect(socketsLeave).toHaveBeenCalledWith(publisher.roomTopic('app', 'room'));
    expect(redis.publish).toHaveBeenCalledWith(REALTIME_CONTROL_CHANNEL, expect.any(String));
    expect(disconnectSockets).toHaveBeenCalledWith(true);
    expect(publisher.userTopic('app', 'user')).toContain('["app","user"]');
    expect(publisher.appTopic('app')).toContain('["app"]');
  });
});
