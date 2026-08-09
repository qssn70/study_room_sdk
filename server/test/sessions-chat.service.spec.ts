import { BadRequestException, ConflictException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { ChatService } from '../src/chat/chat.service';
import { SessionsService } from '../src/sessions/sessions.service';

const identity = {
  userId: 'user-1',
  appId: 'app-1',
  displayName: 'Lin',
  avatarUrl: '',
  expiresAt: new Date(Date.now() + 60_000),
};

describe('SessionsService durable transitions', () => {
  const rooms = { requireMember: jest.fn(async () => ({ role: 'MEMBER' })) };

  it('rejects a concurrent active session using the database unique constraint', async () => {
    const duplicate = new Prisma.PrismaClientKnownRequestError('duplicate', {
      code: 'P2002', clientVersion: 'test', meta: {},
    });
    const studySession = { create: jest.fn(async () => { throw duplicate; }) };
    const prisma = {
      studySession,
      $transaction: jest.fn(async (action: (tx: { studySession: typeof studySession }) => unknown) =>
        action({ studySession })),
    };
    const service = new SessionsService(prisma as never, rooms as never);
    await expect(service.start('room-1', identity)).rejects.toBeInstanceOf(ConflictException);
  });

  it('allows only running/paused/finished state transitions', async () => {
    const current = {
      id: 'session-1', roomId: 'room-1', appId: 'app-1', userId: 'user-1',
      status: 'RUNNING', startedAt: new Date(), finishedAt: null, updatedAt: new Date(),
    };
    const studySession = {
      findFirst: jest.fn(async () => current),
      updateMany: jest.fn(async () => ({ count: 1 })),
      findUniqueOrThrow: jest.fn(async () => ({
        ...current,
        status: 'PAUSED',
        updatedAt: new Date(),
      })),
    };
    const prisma = {
      studySession,
      $transaction: jest.fn(async (action: (tx: { studySession: typeof studySession }) => unknown) =>
        action({ studySession })),
    };
    const service = new SessionsService(prisma as never, rooms as never);
    await expect(service.update('session-1', 'paused', identity)).resolves.toMatchObject({ status: 'paused' });
    await expect(service.update('session-1', 'running', identity)).rejects.toBeInstanceOf(BadRequestException);
  });

  it('starts successfully in a transaction', async () => {
    const created = {
      id: 'session-1', roomId: 'room-1', appId: 'app-1', userId: 'user-1',
      status: 'RUNNING', startedAt: new Date(), finishedAt: null, updatedAt: new Date(),
    };
    const studySession = { create: jest.fn(async () => created) };
    const prisma = {
      studySession,
      $transaction: jest.fn(async (action) => action({ studySession })),
    };
    const service = new SessionsService(prisma as never, rooms as never);
    await expect(service.start('room-1', identity)).resolves.toMatchObject({ status: 'running' });
  });

  it('rejects missing, foreign, finished, and concurrently changed sessions', async () => {
    const base = {
      id: 'session-1', roomId: 'room-1', appId: 'app-1', userId: 'user-1',
      status: 'PAUSED', startedAt: new Date(), finishedAt: null, updatedAt: new Date(),
    };
    const studySession = {
      findFirst: jest.fn()
        .mockResolvedValueOnce(null)
        .mockResolvedValueOnce({ ...base, userId: 'other' })
        .mockResolvedValueOnce({ ...base, status: 'FINISHED' })
        .mockResolvedValueOnce(base),
      updateMany: jest.fn(async () => ({ count: 0 })),
      findUniqueOrThrow: jest.fn(),
    };
    const prisma = { $transaction: jest.fn(async (action) => action({ studySession })) };
    const service = new SessionsService(prisma as never, rooms as never);
    await expect(service.update('missing', 'paused', identity)).rejects.toBeInstanceOf(Error);
    await expect(service.update('session-1', 'running', identity)).rejects.toBeInstanceOf(Error);
    await expect(service.update('session-1', 'running', identity)).rejects.toBeInstanceOf(BadRequestException);
    await expect(service.update('session-1', 'finished', identity)).rejects.toBeInstanceOf(ConflictException);
  });

  it('lists active sessions using stable cursor pagination', async () => {
    const rows = [1, 2, 3].map((index) => ({
      id: `00000000-0000-4000-8000-00000000000${index}`,
      roomId: 'room-1', appId: 'app-1', userId: `user-${index}`,
      status: index === 1 ? 'RUNNING' : 'PAUSED', startedAt: new Date(),
      finishedAt: null, updatedAt: new Date(),
    }));
    const prisma = { studySession: { findMany: jest.fn(async () => rows) } };
    const service = new SessionsService(prisma as never, rooms as never);
    const page = await service.listActive('room-1', identity, undefined, 2);
    expect(page.items).toHaveLength(2);
    expect(page.nextCursor).toBe(rows[1].id);
    expect(prisma.studySession.findMany).toHaveBeenCalledWith(expect.objectContaining({
      orderBy: [{ updatedAt: 'desc' }, { id: 'desc' }],
      take: 3,
    }));
  });
});

describe('ChatService pagination', () => {
  it('returns chronological items and a cursor while enforcing membership', async () => {
    const chatRooms = { requireMember: jest.fn(async () => ({ role: 'MEMBER' })) };
    const rows = [1, 2, 3].map((index) => ({
      id: `message-${index}`,
      roomId: 'room-1',
      senderId: 'user-1',
      text: `${index}`,
      sentAt: new Date(`2026-08-09T00:00:0${index}Z`),
      sender: { displayName: 'Lin' },
    }));
    const prisma = { chatMessage: { findMany: jest.fn(async () => rows) } };
    const service = new ChatService(prisma as never, chatRooms as never);
    const page = await service.history('room-1', identity, undefined, 2);
    expect(page.items.map((item) => item.id)).toEqual(['message-2', 'message-1']);
    expect(page.nextCursor).toBe('message-2');
    expect(chatRooms.requireMember).toHaveBeenCalled();
  });

  it('sends messages and handles the final cursor page', async () => {
    const chatRooms = { requireMember: jest.fn(async () => ({ role: 'MEMBER' })) };
    const row = {
      id: 'message-1', roomId: 'room-1', senderId: 'user-1', text: 'hello',
      sentAt: new Date('2026-08-09T00:00:00Z'), sender: { displayName: 'Lin' },
    };
    const prisma = { chatMessage: {
      create: jest.fn(async () => row),
      findMany: jest.fn(async () => [row]),
    } };
    const service = new ChatService(prisma as never, chatRooms as never);
    await expect(service.send('room-1', identity, ' hello ')).resolves.toMatchObject({ text: 'hello' });
    await expect(service.history('room-1', identity, 'cursor', 50)).resolves.toMatchObject({ nextCursor: null });
    expect(prisma.chatMessage.findMany).toHaveBeenCalledWith(expect.objectContaining({
      cursor: { id: 'cursor' }, skip: 1,
    }));
  });
});
