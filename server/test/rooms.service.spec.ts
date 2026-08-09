import { RoomsService } from '../src/rooms/rooms.service';

describe('RoomsService', () => {
  it('joins rooms within an app boundary and records member presence', async () => {
    const service = new RoomsService();

    const room = await service.joinRoom('room-1', {
      userId: 'user-1',
      appId: 'app-1',
      displayName: 'Lin',
      avatarUrl: '',
    });

    expect(room).toMatchObject({
      id: 'room-1',
      title: 'Room room-1',
      appId: 'app-1',
    });
    expect(room.members).toHaveLength(1);
    expect(room.members[0]).toMatchObject({
      id: 'user-1',
      status: 'offline',
    });
  });

  it('keeps rooms with the same id isolated by appId', async () => {
    const service = new RoomsService();

    await service.joinRoom('room-1', {
      userId: 'user-1',
      appId: 'app-1',
      displayName: 'Lin',
      avatarUrl: '',
    });
    const other = await service.joinRoom('room-1', {
      userId: 'user-2',
      appId: 'app-2',
      displayName: 'Mei',
      avatarUrl: '',
    });

    expect(other.members.map((member) => member.id)).toEqual(['user-2']);
  });

  it('requires membership for reads and keeps delimiter-containing ids isolated', async () => {
    const service = new RoomsService();
    const first = {
      userId: 'user-1',
      appId: 'app:one',
      displayName: 'Lin',
      avatarUrl: '',
    };
    const second = {
      userId: 'user-2',
      appId: 'app',
      displayName: 'Mei',
      avatarUrl: '',
    };

    await service.joinRoom('room', first);
    await service.joinRoom('one:room', second);

    await expect(service.getRoom('room', { ...first, userId: 'other' })).rejects.toThrow(
      'Room membership is required',
    );
    await expect(service.getRoom('room', first)).resolves.toMatchObject({ appId: 'app:one' });
    await expect(service.getRoom('one:room', second)).resolves.toMatchObject({ appId: 'app' });
  });

  it('removes membership only on explicit REST leave', async () => {
    const service = new RoomsService();
    const member = {
      userId: 'user-1',
      appId: 'app-1',
      displayName: 'Lin',
      avatarUrl: '',
    };
    await service.joinRoom('room-1', member);
    service.registerConnection('room-1', member, 'socket-1');
    service.unregisterConnection('room-1', member, 'socket-1');

    await expect(service.getRoom('room-1', member)).resolves.toMatchObject({
      members: [expect.objectContaining({ id: 'user-1', status: 'offline' })],
    });

    await service.leaveRoom('room-1', member);
    await expect(service.getRoom('room-1', member)).rejects.toThrow(
      'Room membership is required',
    );
  });
});

