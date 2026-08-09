import { RealtimeGateway } from '../src/realtime/realtime.gateway';

const identity = {
  userId: 'user-1',
  appId: 'app-1',
  displayName: 'Lin',
  avatarUrl: '',
  expiresAt: new Date(Date.now() + 60_000),
};

function socket() {
  return {
    id: 'socket-1',
    data: { identity },
    join: jest.fn(async () => undefined),
    leave: jest.fn(async () => undefined),
    emit: jest.fn(),
    disconnect: jest.fn(),
  };
}

describe('RealtimeGateway authorization and presence', () => {
  const rooms = {
    isMember: jest.fn(async () => true),
    snapshot: jest.fn(async () => ({
      id: 'room-1', appId: 'app-1', version: 2,
      members: [{ id: 'user-1', displayName: 'Lin', avatarUrl: '', role: 'member', status: 'online' }],
    })),
  };
  const presence = {
    refreshSeconds: 20,
    register: jest.fn(async () => undefined),
    setAway: jest.fn(async () => undefined),
    refresh: jest.fn(async () => undefined),
    unregister: jest.fn(async () => undefined),
  };
  const publisher = {
    roomTopic: jest.fn(() => 'room-topic'),
    userTopic: jest.fn(() => 'user-topic'),
    appTopic: jest.fn(() => 'app-topic'),
    publishRoom: jest.fn(),
    evictUser: jest.fn(async () => undefined),
    bind: jest.fn(),
    disconnectApp: jest.fn(async () => undefined),
  };
  const gateway = new RealtimeGateway(
    {} as never,
    rooms as never,
    presence as never,
    {} as never,
    publisher as never,
  );

  beforeEach(() => jest.clearAllMocks());

  it('waits for membership before subscribing and registering presence', async () => {
    const client = socket();
    await expect(gateway.subscribeRoom(client as never, { roomId: 'room-1' })).resolves.toEqual({ ok: true });
    expect(client.join).toHaveBeenCalledWith('room-topic');
    expect(presence.register).toHaveBeenCalledWith('app-1', 'room-1', 'user-1', 'socket-1');
  });

  it('accepts only away state and evicts users whose membership was removed', async () => {
    const client = socket();
    await gateway.subscribeRoom(client as never, { roomId: 'room-1' });
    await expect(gateway.setAway(client as never, { roomId: 'room-1', away: 'yes' as never }))
      .resolves.toMatchObject({ ok: false, error: { code: 'invalid_request' } });
    rooms.isMember.mockResolvedValueOnce(false);
    await expect(gateway.setAway(client as never, { roomId: 'room-1', away: true }))
      .resolves.toMatchObject({ ok: false, error: { code: 'membership_required' } });
    expect(publisher.evictUser).toHaveBeenCalledWith('app-1', 'room-1', 'user-1');
  });

  it('validates subscription and presence acknowledgement payloads', async () => {
    const client = socket();
    await expect(gateway.subscribeRoom(client as never, {})).resolves.toMatchObject({ ok: false });
    rooms.isMember.mockResolvedValueOnce(false);
    await expect(gateway.subscribeRoom(client as never, { roomId: 'room-1' }))
      .resolves.toMatchObject({ error: { code: 'membership_required' } });
    await expect(gateway.setAway(client as never, {})).resolves.toMatchObject({ ok: false });
    await expect(gateway.setAway(client as never, { roomId: 'room-1', away: false }))
      .resolves.toMatchObject({ error: { code: 'subscription_required' } });
    await expect(gateway.unsubscribeRoom(client as never, {})).resolves.toMatchObject({ ok: false });
  });

  it('joins private topics, refreshes/unregisters presence, and unsubscribes', async () => {
    jest.useFakeTimers();
    const client = socket();
    await gateway.handleConnection(client as never);
    await gateway.subscribeRoom(client as never, { roomId: 'room-1' });
    await expect(gateway.setAway(client as never, { roomId: 'room-1', away: true }))
      .resolves.toEqual({ ok: true });
    expect(presence.setAway).toHaveBeenCalledWith('app-1', 'room-1', 'user-1', 'socket-1', true);
    jest.advanceTimersByTime(20_000);
    await Promise.resolve();
    expect(presence.refresh).toHaveBeenCalled();
    await gateway.unsubscribeRoom(client as never, { roomId: 'room-1' });
    await gateway.subscribeRoom(client as never, { roomId: 'room-1' });
    await gateway.handleDisconnect(client as never);
    expect(client.join).toHaveBeenCalledWith('user-topic');
    expect(client.join).toHaveBeenCalledWith('app-topic');
    expect(client.leave).toHaveBeenCalledWith('room-topic');
    expect(presence.unregister).toHaveBeenCalled();
    jest.useRealTimers();
  });

  it('initializes the Redis adapter and authenticates namespace middleware', async () => {
    let middleware: ((socket: unknown, next: (error?: Error) => void) => void) | undefined;
    const handlers = new Map<string, (message: string) => Promise<void>>();
    const auth = { verifyUserToken: jest.fn(async () => identity) };
    const redis = {
      publisher: {}, adapterSubscriber: {},
      subscribe: jest.fn(async (channel, handler) => { handlers.set(channel, handler); }),
    };
    const server = {
      server: { adapter: jest.fn() },
      use: jest.fn((value) => { middleware = value; }),
      sockets: new Map(),
    };
    const initialized = new RealtimeGateway(
      auth as never, rooms as never, presence as never, redis as never, publisher as never,
    );
    await initialized.afterInit(server as never);
    expect(server.server.adapter).toHaveBeenCalled();
    expect(publisher.bind).toHaveBeenCalledWith(server);
    const authenticated = {
      handshake: { auth: { token: 'jwt' } }, data: {},
      join: jest.fn(async () => undefined),
    };
    await new Promise<void>((resolve, reject) => middleware!(authenticated, (error) => error ? reject(error) : resolve()));
    expect(authenticated.data).toEqual({ identity });
    expect(authenticated.join).toHaveBeenCalledWith('user-topic');
    expect(authenticated.join).toHaveBeenCalledWith('app-topic');
    await new Promise<void>((resolve) => middleware!({ handshake: { auth: {} }, data: {} }, (error) => {
      expect(error).toBeInstanceOf(Error);
      resolve();
    }));
    await handlers.get('study-room:applications')?.('{"appId":"app-1","enabled":false}');
    expect(publisher.disconnectApp).toHaveBeenCalledWith('app-1');

    const local = socket();
    const joinedRooms = new Set(['room-1']);
    (local.data as Record<string, unknown>).joinedRoomIds = joinedRooms;
    server.sockets.set(local.id, local);
    const secondLocal = socket();
    secondLocal.id = 'socket-2';
    const secondJoinedRooms = new Set(['room-1']);
    (secondLocal.data as Record<string, unknown>).joinedRoomIds = secondJoinedRooms;
    server.sockets.set(secondLocal.id, secondLocal);
    rooms.snapshot.mockResolvedValueOnce({
      id: 'room-1', appId: 'app-1', version: 2,
      members: [{ id: 'user-1', displayName: 'Lin', avatarUrl: '', role: 'member', status: 'offline' }],
    });
    await handlers.get('study-room:realtime-control')?.(
      '{"type":"room.evict","appId":"app-1","roomId":"room-1","userId":"user-1"}',
    );
    expect(local.leave).toHaveBeenCalledWith('room-topic');
    expect(secondLocal.leave).toHaveBeenCalledWith('room-topic');
    expect(joinedRooms).not.toContain('room-1');
    expect(secondJoinedRooms).not.toContain('room-1');
    expect(presence.unregister).toHaveBeenCalledWith('app-1', 'room-1', 'user-1', 'socket-1');
    expect(presence.unregister).toHaveBeenCalledWith('app-1', 'room-1', 'user-1', 'socket-2');
    expect(presence.unregister.mock.invocationCallOrder.at(-1))
      .toBeLessThan(rooms.snapshot.mock.invocationCallOrder.at(-1)!);
    expect(publisher.publishRoom).toHaveBeenCalledTimes(1);
    expect(publisher.publishRoom).toHaveBeenCalledWith(
      'app-1',
      'room-1',
      'member.presence.updated',
      expect.objectContaining({ id: 'user-1', status: 'offline' }),
      2,
    );
    await handlers.get('study-room:realtime-control')?.(
      '{"type":"room.evict","appId":"app-1","roomId":"room-1","userId":"user-1"}',
    );
    await handlers.get('study-room:realtime-control')?.(
      '{"type":"room.evict","appId":"app-1","roomId":"room-1","userId":"another-user"}',
    );
    expect(publisher.publishRoom).toHaveBeenCalledTimes(1);
  });
});
