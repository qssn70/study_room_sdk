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
      status: 'online',
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
});

