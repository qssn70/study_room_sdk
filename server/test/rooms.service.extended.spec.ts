import { ConflictException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { RoomsService } from '../src/rooms/rooms.service';

const identity = {
  userId: 'owner-1', appId: 'app-1', displayName: 'Owner', avatarUrl: '',
  expiresAt: new Date(Date.now() + 60_000),
};
const room = {
  id: 'room-1', appId: 'app-1', title: 'Focus', version: 2,
  deletedAt: null, createdAt: new Date(), updatedAt: new Date(),
  memberships: [{
    roomId: 'room-1', appId: 'app-1', userId: 'owner-1', role: 'OWNER', joinedAt: new Date(),
    user: { appId: 'app-1', userId: 'owner-1', displayName: 'Owner', avatarUrl: '' },
  }],
};
const request = {
  id: 'request-1', roomId: 'room-1', appId: 'app-1', userId: 'user-2', status: 'PENDING',
  decidedBy: null, createdAt: new Date('2026-08-09T00:00:00Z'),
  updatedAt: new Date('2026-08-09T00:00:00Z'), user: { displayName: 'Ada' },
};
const presence = {
  statusFor: jest.fn(async () => 'online'),
  statusesFor: jest.fn(async (_appId: string, _roomId: string, userIds: string[]) =>
    new Map(userIds.map((userId) => [userId, 'online']))),
  removeUser: jest.fn(async () => undefined),
};

describe('RoomsService room and membership workflows', () => {
  beforeEach(() => jest.clearAllMocks());

  it('creates a room with one owner and an audit record', async () => {
    const tx = {
      room: { create: jest.fn(async () => room) },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = { $transaction: jest.fn(async (callback) => callback(tx)) };
    const service = new RoomsService(prisma as never, presence as never);
    await expect(service.create(' Focus ', identity)).resolves.toMatchObject({ title: 'Focus' });
    expect(tx.room.create).toHaveBeenCalledWith(expect.objectContaining({
      data: expect.objectContaining({ memberships: { create: expect.objectContaining({ role: 'OWNER' }) } }),
    }));
    expect(tx.auditLog.create).toHaveBeenCalled();
  });

  it('lists cursor pages, reads member rooms, and returns snapshots', async () => {
    const prisma = { room: {
      findMany: jest.fn(async () => [room, { ...room, id: 'room-2' }]),
      findFirst: jest.fn(async () => room),
    } };
    const service = new RoomsService(prisma as never, presence as never);
    await expect(service.list(identity, 'cursor', 1)).resolves.toMatchObject({
      items: [{ id: 'room-1' }], nextCursor: 'room-1',
    });
    await expect(service.get('room-1', identity)).resolves.toMatchObject({ id: 'room-1' });
    await expect(service.snapshot('app-1', 'room-1')).resolves.toMatchObject({ id: 'room-1' });
    prisma.room.findFirst.mockResolvedValueOnce(null as never);
    await expect(service.snapshot('app-1', 'missing')).resolves.toBeUndefined();
    prisma.room.findFirst.mockResolvedValueOnce(null as never);
    await expect(service.get('missing', identity)).rejects.toBeInstanceOf(ForbiddenException);
  });

  it('checks membership and creates a new request', async () => {
    const prisma = {
      room: { findFirst: jest.fn(async () => ({ id: 'room-1' })) },
      roomMembership: { count: jest.fn(async () => 0) },
      joinRequest: {
        findFirst: jest.fn(async () => null),
        create: jest.fn(async () => request),
      },
    };
    const service = new RoomsService(prisma as never, presence as never);
    await expect(service.isMember('room-1', identity)).resolves.toBe(false);
    await expect(service.requestJoin('room-1', { ...identity, userId: 'user-2' }))
      .resolves.toMatchObject({ request: { status: 'pending' }, created: true });
    prisma.roomMembership.count.mockResolvedValueOnce(1);
    await expect(service.requestJoin('room-1', identity)).rejects.toBeInstanceOf(ConflictException);
    prisma.room.findFirst.mockResolvedValueOnce(null as never);
    await expect(service.requestJoin('missing', identity)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('recovers the concurrent pending request after a unique violation', async () => {
    const duplicate = new Prisma.PrismaClientKnownRequestError('duplicate', {
      code: 'P2002', clientVersion: 'test', meta: {},
    });
    const prisma = {
      room: { findFirst: jest.fn(async () => ({ id: 'room-1' })) },
      roomMembership: { count: jest.fn(async () => 0) },
      joinRequest: {
        findFirst: jest.fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce(request),
        create: jest.fn(async () => { throw duplicate; }),
      },
    };
    const service = new RoomsService(prisma as never, presence as never);
    await expect(service.requestJoin('room-1', { ...identity, userId: 'user-2' }))
      .resolves.toMatchObject({ request: { id: 'request-1' }, created: false });
  });

  it('lists and cancels personal and owner requests', async () => {
    const prisma = { joinRequest: {
      findMany: jest.fn(async () => [request]),
      findFirst: jest.fn(async () => request),
      update: jest.fn(async () => ({ ...request, status: 'CANCELLED' })),
    } };
    const service = new RoomsService(prisma as never, presence as never);
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);
    await expect(service.listMyJoinRequests(identity)).resolves.toMatchObject({ items: [{ id: 'request-1' }] });
    await expect(service.listRoomJoinRequests('room-1', identity)).resolves.toMatchObject({ items: [{ id: 'request-1' }] });
    await expect(service.cancelJoinRequest('room-1', identity)).resolves.toBeUndefined();
    prisma.joinRequest.findFirst.mockResolvedValueOnce(null as never);
    await expect(service.cancelJoinRequest('room-1', identity)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('rejects a request without creating membership', async () => {
    const tx = {
      joinRequest: {
        findFirst: jest.fn(async () => request),
        update: jest.fn(async () => ({ ...request, status: 'REJECTED' })),
      },
      roomMembership: { upsert: jest.fn() },
      room: { update: jest.fn() },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = { $transaction: jest.fn(async (callback) => callback(tx)) };
    const service = new RoomsService(prisma as never, presence as never);
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);
    await expect(service.decideJoinRequest('room-1', 'request-1', 'rejected', identity))
      .resolves.toMatchObject({ request: { status: 'rejected' }, roomVersion: null });
    expect(tx.roomMembership.upsert).not.toHaveBeenCalled();
    tx.joinRequest.findFirst.mockResolvedValueOnce(null as never);
    await expect(service.decideJoinRequest('room-1', 'missing', 'approved', identity))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it('removes members and prevents removing an owner', async () => {
    const prisma = {
      roomMembership: {
        findUnique: jest.fn(async () => ({ role: 'MEMBER' })),
        delete: jest.fn(async () => undefined),
      },
      room: {
        update: jest.fn(async () => ({ version: 3 })),
        findFirst: jest.fn(async () => room),
      },
      auditLog: { create: jest.fn(async () => undefined) },
      $transaction: jest.fn(async (operations) => Promise.all(operations)),
    };
    const service = new RoomsService(prisma as never, presence as never);
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);
    await expect(service.removeMember('room-1', 'user-2', identity)).resolves.toMatchObject({ id: 'room-1' });
    expect(presence.removeUser).toHaveBeenCalled();
    prisma.roomMembership.findUnique.mockResolvedValueOnce({ role: 'OWNER' });
    await expect(service.removeMember('room-1', 'owner-1', identity)).rejects.toBeInstanceOf(ConflictException);
    prisma.roomMembership.findUnique.mockResolvedValueOnce(null as never);
    await expect(service.removeMember('room-1', 'missing', identity)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('lets a member leave and transfers ownership transactionally', async () => {
    const roomMembership = {
      delete: jest.fn(async () => undefined),
      findUnique: jest.fn(async () => ({ role: 'MEMBER' })),
      update: jest.fn(async () => undefined),
    };
    const roomClient = {
      update: jest.fn(async () => ({ version: 3 })),
      findFirst: jest.fn(async () => room),
    };
    const auditLog = { create: jest.fn(async () => undefined) };
    const prisma = {
      roomMembership,
      room: roomClient,
      auditLog,
      $transaction: jest.fn(async (value) => typeof value === 'function'
        ? value({
            roomMembership,
            room: roomClient,
            auditLog,
          })
        : Promise.all(value)),
    };
    const service = new RoomsService(prisma as never, presence as never);
    jest.spyOn(service, 'requireMember').mockResolvedValue({ role: 'MEMBER' } as never);
    await expect(service.leave('room-1', { ...identity, userId: 'user-2' })).resolves.toMatchObject({ id: 'room-1' });
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);
    await expect(service.transferOwnership('room-1', 'user-2', identity)).resolves.toMatchObject({ id: 'room-1' });
    expect(prisma.roomMembership.update).toHaveBeenCalledTimes(2);
    prisma.roomMembership.findUnique.mockResolvedValueOnce(null as never);
    await expect(service.transferOwnership('room-1', 'missing', identity)).rejects.toBeInstanceOf(NotFoundException);
  });

  it('soft deletes a room, removes presence, and enforces membership helpers', async () => {
    const prisma = {
      roomMembership: {
        findMany: jest.fn(async () => [{ userId: 'owner-1' }, { userId: 'user-2' }]),
        findFirst: jest.fn()
          .mockResolvedValueOnce(null)
          .mockResolvedValueOnce({ role: 'MEMBER' }),
      },
      room: { update: jest.fn(async () => ({ version: 3 })) },
      auditLog: { create: jest.fn(async () => undefined) },
      $transaction: jest.fn(async (operations) => Promise.all(operations)),
    };
    const service = new RoomsService(prisma as never, presence as never);
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);
    await expect(service.delete('room-1', identity)).resolves.toEqual({
      userIds: ['owner-1', 'user-2'], roomVersion: 3,
    });
    expect(presence.removeUser).toHaveBeenCalledTimes(2);
    await expect(service.requireMember('room-1', identity)).rejects.toBeInstanceOf(ForbiddenException);
    await expect(service.requireMember('room-1', identity)).resolves.toMatchObject({ role: 'MEMBER' });
  });

  it('resolves the current owner for private join-request delivery', async () => {
    const prisma = { roomMembership: { findFirst: jest.fn()
      .mockResolvedValueOnce({ userId: 'owner-1' })
      .mockResolvedValueOnce(null) } };
    const service = new RoomsService(prisma as never, presence as never);
    await expect(service.ownerUserId('room-1', 'app-1')).resolves.toBe('owner-1');
    await expect(service.ownerUserId('room-1', 'app-1')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('paginates request lists with cursors and next cursors', async () => {
    const second = { ...request, id: 'request-2' };
    const prisma = { joinRequest: { findMany: jest.fn(async () => [request, second]) } };
    const service = new RoomsService(prisma as never, presence as never);
    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);

    await expect(service.listMyJoinRequests(identity, 'request-cursor', 1)).resolves.toMatchObject({
      items: [{ id: 'request-1' }], nextCursor: 'request-1',
    });
    await expect(service.listRoomJoinRequests('room-1', identity, 'request-cursor', 1)).resolves.toMatchObject({
      items: [{ id: 'request-1' }], nextCursor: 'request-1',
    });
    expect(prisma.joinRequest.findMany).toHaveBeenCalledWith(expect.objectContaining({
      cursor: { id: 'request-cursor' }, skip: 1, take: 2,
    }));
  });

  it('covers empty room pages, list bounds, and missing presence fallback', async () => {
    const prisma = { room: { findMany: jest.fn(async () => []), findFirst: jest.fn(async () => room) } };
    const missingPresence = {
      ...presence,
      statusesFor: jest.fn(async () => new Map()),
    };
    const service = new RoomsService(prisma as never, missingPresence as never);

    await expect(service.list(identity, undefined, 0)).resolves.toEqual({ items: [], nextCursor: null });
    expect(prisma.room.findMany).toHaveBeenLastCalledWith(expect.objectContaining({ take: 2 }));
    await service.list(identity, undefined, 101);
    expect(prisma.room.findMany).toHaveBeenLastCalledWith(expect.objectContaining({ take: 101 }));
    await expect(service.get('room-1', identity)).resolves.toMatchObject({
      members: [expect.objectContaining({ status: 'offline' })],
    });
  });

  it('rethrows non-unique request creation failures', async () => {
    const failure = new Error('database unavailable');
    const prisma = {
      room: { findFirst: jest.fn(async () => ({ id: 'room-1' })) },
      roomMembership: { count: jest.fn(async () => 0) },
      joinRequest: {
        findFirst: jest.fn(async () => null),
        create: jest.fn(async () => { throw failure; }),
      },
    };
    const service = new RoomsService(prisma as never, presence as never);
    await expect(service.requestJoin('room-1', { ...identity, userId: 'user-2' })).rejects.toBe(failure);
  });

  it('handles self-transfer, missing post-transfer room, and non-owner permission', async () => {
    const clients = {
      roomMembership: {
        findFirst: jest.fn(async () => ({ role: 'MEMBER' })),
        findUnique: jest.fn(async () => ({ role: 'MEMBER' })),
        update: jest.fn(async () => undefined),
      },
      room: { update: jest.fn(async () => ({ version: 3 })), findFirst: jest.fn(async () => null) },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = {
      ...clients,
      $transaction: jest.fn(async (callback) => callback(clients)),
    };
    const service = new RoomsService(prisma as never, presence as never);

    await expect((service as unknown as {
      requireOwner(roomId: string, current: typeof identity): Promise<unknown>;
    }).requireOwner('room-1', identity)).rejects.toBeInstanceOf(ForbiddenException);

    jest.spyOn(service as never, 'requireOwner' as never).mockResolvedValue({ role: 'OWNER' } as never);
    jest.spyOn(service, 'get').mockResolvedValue({ id: 'room-1' } as never);
    await expect(service.transferOwnership('room-1', identity.userId, identity)).resolves.toMatchObject({ id: 'room-1' });
    await expect(service.transferOwnership('room-1', 'user-2', identity)).rejects.toBeInstanceOf(NotFoundException);
  });
});
