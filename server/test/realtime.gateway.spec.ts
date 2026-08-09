import jwt from 'jsonwebtoken';
import { Server, Socket } from 'socket.io';
import { AuthService } from '../src/auth/auth.service';
import { RealtimeGateway } from '../src/realtime/realtime.gateway';
import { RoomsService } from '../src/rooms/rooms.service';

describe('RealtimeGateway', () => {
  const auth = new AuthService('secret');
  const rooms = new RoomsService();
  const gateway = new RealtimeGateway(auth, rooms);
  const emit = jest.fn();
  const identity = {
    userId: 'user-1',
    appId: 'app:one',
    displayName: 'Lin',
    avatarUrl: '',
  };
  let socketSequence = 0;

  beforeAll(() => {
    gateway.server = {
      to: jest.fn().mockReturnValue({ emit }),
    } as unknown as Server;
  });

  it('accepts only a valid auth.token and stores verified identity', async () => {
    let middleware:
      | ((socket: Socket, next: (error?: Error) => void) => void)
      | undefined;
    gateway.afterInit({
      use: (candidate: typeof middleware) => {
        middleware = candidate;
      },
    } as unknown as Server);

    const queryOnly = socketWith({ auth: {}, query: { token: sign(identity) } });
    await expect(runMiddleware(middleware!, queryOnly)).rejects.toThrow('Unauthorized');

    const authenticated = socketWith({ auth: { token: sign(identity) }, query: {} });
    await expect(runMiddleware(middleware!, authenticated)).resolves.toBeUndefined();
    expect(authenticated.data.identity).toEqual(identity);
  });

  it('requires membership and derives a collision-safe tenant topic', async () => {
    const outsider = socketWithIdentity({ ...identity, userId: 'outsider' });
    await expect(gateway.joinRoom(outsider, { roomId: 'room' })).resolves.toEqual({
      ok: false,
      error: 'Room membership is required',
    });

    await rooms.joinRoom('room', identity);
    const member = socketWithIdentity(identity);
    await expect(gateway.joinRoom(member, { roomId: 'room' })).resolves.toEqual({ ok: true });
    expect(member.join).toHaveBeenCalledWith(JSON.stringify(['app:one', 'room']));
    await expect(gateway.leaveRoom(member, { roomId: 'room' })).resolves.toEqual({ ok: true });
    expect(member.leave).toHaveBeenCalledWith(JSON.stringify(['app:one', 'room']));

    const otherIdentity = { ...identity, appId: 'app', userId: 'user-2' };
    await rooms.joinRoom('one:room', otherIdentity);
    const other = socketWithIdentity(otherIdentity);
    await gateway.joinRoom(other, { roomId: 'one:room' });
    expect(other.join).toHaveBeenCalledWith(JSON.stringify(['app', 'one:room']));
    expect((member.join as jest.Mock).mock.calls[0][0]).not.toBe(
      (other.join as jest.Mock).mock.calls[0][0],
    );
  });

  it('aggregates multi-socket presence and marks the last disconnect offline', async () => {
    await rooms.joinRoom('presence-room', identity);
    const first = socketWithIdentity(identity);
    const second = socketWithIdentity(identity);
    await gateway.joinRoom(first, { roomId: 'presence-room' });
    await gateway.joinRoom(second, { roomId: 'presence-room' });

    await gateway.updatePresence(first, {
      roomId: 'presence-room',
      status: 'away',
    });
    expect((await rooms.getRoom('presence-room', identity)).members[0].status).toBe('online');
    await gateway.updatePresence(second, {
      roomId: 'presence-room',
      status: 'away',
    });
    expect((await rooms.getRoom('presence-room', identity)).members[0].status).toBe('away');
    await gateway.updatePresence(first, {
      roomId: 'presence-room',
      status: 'focusing',
    });
    expect((await rooms.getRoom('presence-room', identity)).members[0].status).toBe('focusing');

    await gateway.handleDisconnect(first);
    expect((await rooms.getRoom('presence-room', identity)).members[0].status).toBe('away');
    await gateway.handleDisconnect(second);
    expect((await rooms.getRoom('presence-room', identity)).members[0].status).toBe('offline');
  });

  it('rejects invalid, unsubscribed, and removed-member presence updates', async () => {
    const guardedIdentity = { ...identity, userId: 'presence-guard' };
    await rooms.joinRoom('guarded-room', guardedIdentity);
    const client = socketWithIdentity(guardedIdentity);

    await expect(
      gateway.updatePresence(client, { roomId: 'guarded-room', status: 'idle' }),
    ).resolves.toEqual({
      ok: false,
      error: 'Realtime room subscription is required',
    });

    await gateway.joinRoom(client, { roomId: 'guarded-room' });
    await expect(
      gateway.updatePresence(client, { roomId: 'guarded-room', status: 'offline' }),
    ).resolves.toEqual({ ok: false, error: 'Invalid presence status' });

    await rooms.leaveRoom('guarded-room', guardedIdentity);
    await expect(
      gateway.updatePresence(client, { roomId: 'guarded-room', status: 'idle' }),
    ).resolves.toEqual({ ok: false, error: 'Room membership is required' });
  });

  it('leaves realtime channels without deleting access membership', async () => {
    const leavingIdentity = { ...identity, userId: 'realtime-leaver' };
    await rooms.joinRoom('realtime-leave-room', leavingIdentity);
    const client = socketWithIdentity(leavingIdentity);
    await gateway.joinRoom(client, { roomId: 'realtime-leave-room' });

    await gateway.leaveRoom(client, { roomId: 'realtime-leave-room' });

    await expect(
      rooms.getRoom('realtime-leave-room', leavingIdentity),
    ).resolves.toMatchObject({ id: 'realtime-leave-room' });
    expect(
      (await rooms.getRoom('realtime-leave-room', leavingIdentity)).members[0].status,
    ).toBe('offline');
  });

  it('includes roomId in every published event envelope', () => {
    emit.mockClear();

    gateway.publish('app:one', 'event-room', 'chat.message', { id: 'message-1' });

    expect(gateway.server.to).toHaveBeenLastCalledWith(
      JSON.stringify(['app:one', 'event-room']),
    );
    expect(emit).toHaveBeenCalledWith('study-room.event', {
      type: 'chat.message',
      roomId: 'event-room',
      payload: { id: 'message-1' },
    });
  });

  function sign(payload: typeof identity) {
    return jwt.sign(
      {
        sub: payload.userId,
        appId: payload.appId,
        displayName: payload.displayName,
        avatarUrl: payload.avatarUrl,
      },
      'secret',
      { expiresIn: '5m' },
    );
  }

  function socketWith(handshake: Record<string, unknown>): Socket {
    return {
      id: `socket-${++socketSequence}`,
      handshake,
      data: {},
      join: jest.fn().mockResolvedValue(undefined),
      leave: jest.fn().mockResolvedValue(undefined),
    } as unknown as Socket;
  }

  function socketWithIdentity(value: typeof identity): Socket {
    const socket = socketWith({ auth: {}, query: {} });
    socket.data.identity = value;
    return socket;
  }

  function runMiddleware(
    middleware: (socket: Socket, next: (error?: Error) => void) => void,
    socket: Socket,
  ): Promise<void> {
    return new Promise((resolve, reject) => {
      middleware(socket, (error) => (error ? reject(error) : resolve()));
    });
  }
});
