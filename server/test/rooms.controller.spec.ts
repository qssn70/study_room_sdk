import { RoomsController } from '../src/rooms/rooms.controller';

describe('RoomsController realtime privacy', () => {
  it('delivers a created join request only to the current owner personal channel', async () => {
    const request = {
      id: '00000000-0000-4000-8000-000000000003',
      roomId: '00000000-0000-4000-8000-000000000001',
      userId: 'applicant-1',
      displayName: 'Applicant',
      status: 'pending',
      createdAt: '2026-08-09T00:00:00.000Z',
      updatedAt: '2026-08-09T00:00:00.000Z',
    };
    const rooms = {
      requestJoin: jest.fn(async () => ({ request, created: true })),
      ownerUserId: jest.fn(async () => 'owner-1'),
    };
    const realtime = {
      publishUser: jest.fn(),
      publishRoom: jest.fn(),
    };
    const controller = new RoomsController(rooms as never, realtime as never);
    const identity = {
      userId: 'applicant-1',
      appId: 'app-1',
      displayName: 'Applicant',
      avatarUrl: '',
      expiresAt: new Date(Date.now() + 60_000),
    };

    await expect(controller.requestJoin({ roomId: request.roomId }, identity)).resolves.toBe(request);
    expect(rooms.ownerUserId).toHaveBeenCalledWith(request.roomId, 'app-1');
    expect(realtime.publishUser).toHaveBeenCalledWith(
      'app-1',
      'owner-1',
      'join-request.created',
      request,
      request.roomId,
      null,
    );
    expect(realtime.publishRoom).not.toHaveBeenCalled();

    rooms.requestJoin.mockResolvedValueOnce({ request, created: false });
    await expect(controller.requestJoin({ roomId: request.roomId }, identity)).resolves.toBe(request);
    expect(rooms.ownerUserId).toHaveBeenCalledTimes(1);
    expect(realtime.publishUser).toHaveBeenCalledTimes(1);
  });
});
