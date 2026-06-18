import { ChatService } from '../src/chat/chat.service';
import { SessionsService } from '../src/sessions/sessions.service';

describe('SessionsService', () => {
  it('moves a study session through start pause resume finish', async () => {
    const service = new SessionsService();

    const started = await service.start('room-1', {
      userId: 'user-1',
      appId: 'app-1',
      displayName: 'Lin',
      avatarUrl: '',
    });
    const paused = await service.pause(started.id);
    const resumed = await service.resume(started.id);
    const finished = await service.finish(started.id);

    expect(started.status).toBe('running');
    expect(paused.status).toBe('paused');
    expect(resumed.status).toBe('running');
    expect(finished.status).toBe('finished');
    expect(finished.finishedAt).toBeDefined();
  });
});

describe('ChatService', () => {
  it('rejects blank messages and stores trimmed text', async () => {
    const service = new ChatService();

    expect(() =>
      service.send('room-1', {
        userId: 'user-1',
        appId: 'app-1',
        displayName: 'Lin',
        avatarUrl: '',
      }, '   '),
    ).toThrow('Message text is required');

    const message = service.send('room-1', {
      userId: 'user-1',
      appId: 'app-1',
      displayName: 'Lin',
      avatarUrl: '',
    }, ' hello ');

    expect(message.text).toBe('hello');
    expect(service.history('app-1', 'room-1')).toEqual([message]);
  });
});

