import { ChatService } from '../src/chat/chat.service';
import { RoomsService } from '../src/rooms/rooms.service';
import { SessionsService } from '../src/sessions/sessions.service';

const identity = {
  userId: 'user-1',
  appId: 'app-1',
  displayName: 'Lin',
  avatarUrl: '',
};

describe('SessionsService', () => {
  it('moves a study session through start pause resume finish', async () => {
    const rooms = new RoomsService();
    const service = new SessionsService(rooms);
    await rooms.joinRoom('room-1', identity);
    rooms.registerConnection('room-1', identity, 'socket-1');

    const started = await service.start('room-1', identity);
    expect((await rooms.getRoom('room-1', identity)).members[0].status).toBe('focusing');
    const paused = await service.pause(started.id, identity);
    expect((await rooms.getRoom('room-1', identity)).members[0].status).toBe('idle');
    const resumed = await service.resume(started.id, identity);
    expect((await rooms.getRoom('room-1', identity)).members[0].status).toBe('focusing');
    const finished = await service.finish(started.id, identity);
    expect((await rooms.getRoom('room-1', identity)).members[0].status).toBe('idle');

    expect(started.status).toBe('running');
    expect(paused.status).toBe('paused');
    expect(resumed.status).toBe('running');
    expect(finished.status).toBe('finished');
    expect(finished.finishedAt).toBeDefined();
  });

  it('isolates sessions by tenant and creator', async () => {
    const rooms = new RoomsService();
    const service = new SessionsService(rooms);
    await rooms.joinRoom('room-1', identity);
    const started = await service.start('room-1', identity);

    await expect(
      service.pause(started.id, { ...identity, appId: 'app-2' }),
    ).rejects.toThrow('Study session not found');
    await expect(
      service.pause(started.id, { ...identity, userId: 'user-2' }),
    ).rejects.toThrow('Only the session creator can control this session');
  });

  it('lets a creator finish after explicitly leaving the room', async () => {
    const rooms = new RoomsService();
    const service = new SessionsService(rooms);
    await rooms.joinRoom('left-room', identity);
    rooms.registerConnection('left-room', identity, 'socket-1');
    const started = await service.start('left-room', identity);
    await rooms.leaveRoom('left-room', identity);

    await expect(service.finish(started.id, identity)).resolves.toMatchObject({
      id: started.id,
      status: 'finished',
    });
  });
});

describe('ChatService', () => {
  it('rejects blank messages and stores trimmed text', async () => {
    const rooms = new RoomsService();
    const service = new ChatService(rooms);
    await rooms.joinRoom('room-1', identity);

    expect(() =>
      service.send('room-1', identity, '   '),
    ).toThrow('Message text is required');

    const message = service.send('room-1', identity, ' hello ');

    expect(message.text).toBe('hello');
    expect(service.history('room-1', identity)).toEqual([message]);
  });
});

