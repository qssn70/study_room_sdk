import { ChatController } from '../src/chat/chat.controller';
import { RoomsController } from '../src/rooms/rooms.controller';
import { SessionsController } from '../src/sessions/sessions.controller';

const identity = {
  userId: 'user-1',
  appId: 'app-1',
  displayName: 'Lin',
  avatarUrl: '',
  expiresAt: new Date(Date.now() + 60_000),
};

describe('idempotent controller replay', () => {
  it('does not republish room creation events', async () => {
    const room = { id: 'room-1', version: 1 };
    const rooms = {
      createIdempotent: jest.fn(async () => ({ value: room, created: false })),
    };
    const realtime = { publishRoom: jest.fn() };
    const controller = new RoomsController(rooms as never, realtime as never);

    await expect(controller.create(
      { title: 'Focus' },
      identity,
      'room-key',
    )).resolves.toBe(room);
    expect(realtime.publishRoom).not.toHaveBeenCalled();
  });

  it('does not republish chat events', async () => {
    const message = { id: 'message-1', roomId: 'room-1' };
    const chat = {
      sendIdempotent: jest.fn(async () => ({ value: message, created: false })),
    };
    const realtime = { publishRoom: jest.fn() };
    const controller = new ChatController(chat as never, realtime as never);

    await expect(controller.send(
      { roomId: 'room-1' },
      identity,
      { text: 'Hello' },
      'message-key',
    )).resolves.toBe(message);
    expect(realtime.publishRoom).not.toHaveBeenCalled();
  });

  it('does not republish session or presence events', async () => {
    const session = { id: 'session-1', roomId: 'room-1' };
    const sessions = {
      startIdempotent: jest.fn(async () => ({ value: session, created: false })),
    };
    const realtime = { publishRoom: jest.fn() };
    const rooms = { snapshot: jest.fn() };
    const controller = new SessionsController(
      sessions as never,
      realtime as never,
      rooms as never,
    );

    await expect(controller.start(
      { roomId: 'room-1' },
      identity,
      'session-key',
    )).resolves.toBe(session);
    expect(realtime.publishRoom).not.toHaveBeenCalled();
    expect(rooms.snapshot).not.toHaveBeenCalled();
  });
});
