import { RetentionService } from '../src/operations/retention.service';

describe('RetentionService advisory-lock cleanup', () => {
  it('deletes only configured expired data while holding the lock', async () => {
    const now = Date.parse('2026-08-11T03:00:00.000Z');
    jest.spyOn(Date, 'now').mockReturnValue(now);
    const tx = {
      $queryRaw: jest.fn(async () => [{ locked: true }]),
      application: { findMany: jest.fn(async () => [{
        appId: 'app-1', enabled: false, chatRetentionDays: 7, sessionRetentionDays: null,
      }, {
        appId: 'app-2', enabled: true, chatRetentionDays: null, sessionRetentionDays: 30,
      }, {
        appId: 'permanent', enabled: false, chatRetentionDays: null, sessionRetentionDays: null,
      }]) },
      chatMessage: { deleteMany: jest.fn(async () => ({ count: 2 })) },
      studySession: { deleteMany: jest.fn(async () => ({ count: 1 })) },
    };
    const prisma = { $transaction: jest.fn(async (callback) => callback(tx)) };
    const service = new RetentionService(prisma as never);
    await service.clean();
    expect(tx.chatMessage.deleteMany).toHaveBeenCalledTimes(1);
    expect(tx.studySession.deleteMany).toHaveBeenCalledTimes(1);
    expect(tx.chatMessage.deleteMany).toHaveBeenCalledWith({
      where: {
        appId: 'app-1',
        sentAt: { lt: new Date(now - 7 * 86_400_000) },
      },
    });
    expect(tx.studySession.deleteMany).toHaveBeenCalledWith({
      where: {
        appId: 'app-2',
        finishedAt: { lt: new Date(now - 30 * 86_400_000) },
      },
    });
    expect(tx.application.findMany).toHaveBeenCalledWith({
      where: {
        OR: [{ chatRetentionDays: { not: null } }, { sessionRetentionDays: { not: null } }],
      },
    });
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), { timeout: 60_000 });
    jest.restoreAllMocks();
  });

  it('does nothing when another instance owns the advisory lock', async () => {
    const tx = {
      $queryRaw: jest.fn(async () => [{ locked: false }]),
      application: { findMany: jest.fn() },
    };
    const prisma = { $transaction: jest.fn(async (callback) => callback(tx)) };
    await new RetentionService(prisma as never).clean();
    expect(tx.application.findMany).not.toHaveBeenCalled();
  });
});
