import { ConflictException } from '@nestjs/common';
import { RoomsService } from '../src/rooms/rooms.service';

const identity = {
  userId: 'owner-1',
  appId: 'app-1',
  displayName: 'Owner',
  avatarUrl: '',
  expiresAt: new Date(Date.now() + 60_000),
};

const pendingRequest = {
  id: 'request-1',
  roomId: 'room-1',
  appId: 'app-1',
  userId: 'user-2',
  status: 'PENDING',
  decidedBy: null,
  createdAt: new Date('2026-08-09T00:00:00Z'),
  updatedAt: new Date('2026-08-09T00:00:00Z'),
  user: { displayName: 'Ada' },
};

describe('RoomsService approval invariants', () => {
  it('returns the existing pending request idempotently', async () => {
    const prisma = {
      room: { findFirst: jest.fn(async () => ({ id: 'room-1' })) },
      roomMembership: { count: jest.fn(async () => 0) },
      joinRequest: {
        findFirst: jest.fn(async () => pendingRequest),
        create: jest.fn(),
      },
    };
    const service = new RoomsService(prisma as never, {} as never);
    await expect(service.requestJoin('room-1', { ...identity, userId: 'user-2' })).resolves.toMatchObject({
      request: { id: 'request-1', status: 'pending' },
      created: false,
    });
    expect(prisma.joinRequest.create).not.toHaveBeenCalled();
  });

  it('approves transactionally, creates membership, and increments room version', async () => {
    const tx = {
      joinRequest: {
        findFirst: jest.fn(async () => pendingRequest),
        update: jest.fn(async () => ({ ...pendingRequest, status: 'APPROVED' })),
      },
      roomMembership: { upsert: jest.fn(async () => undefined) },
      room: { update: jest.fn(async () => ({ version: 7 })) },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = { $transaction: jest.fn(async (callback) => callback(tx)) };
    const service = new RoomsService(prisma as never, {} as never);
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);

    const result = await service.decideJoinRequest('room-1', 'request-1', 'approved', identity);
    expect(result.roomVersion).toBe(7);
    expect(tx.roomMembership.upsert).toHaveBeenCalledWith(expect.objectContaining({
      create: expect.objectContaining({ role: 'MEMBER', userId: 'user-2' }),
    }));
    expect(tx.auditLog.create).toHaveBeenCalled();
  });

  it('prevents an owner from leaving before transfer or deletion', async () => {
    const service = new RoomsService({} as never, {} as never);
    jest.spyOn(service, 'requireMember').mockResolvedValue({ role: 'OWNER' } as never);
    await expect(service.leave('room-1', identity)).rejects.toBeInstanceOf(ConflictException);
  });
});
