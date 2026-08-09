import { HttpException } from '@nestjs/common';
import { TenantRateLimitGuard } from '../src/common/tenant-rate-limit.guard';
import { RetentionService } from '../src/operations/retention.service';

describe('RetentionService advisory-lock cleanup', () => {
  it('deletes only configured expired data while holding the lock', async () => {
    const tx = {
      $queryRaw: jest.fn(async () => [{ locked: true }]),
      application: { findMany: jest.fn(async () => [{
        appId: 'app-1', chatRetentionDays: 7, sessionRetentionDays: null,
      }, {
        appId: 'app-2', chatRetentionDays: null, sessionRetentionDays: 30,
      }]) },
      chatMessage: { deleteMany: jest.fn(async () => ({ count: 2 })) },
      studySession: { deleteMany: jest.fn(async () => ({ count: 1 })) },
    };
    const prisma = { $transaction: jest.fn(async (callback) => callback(tx)) };
    const service = new RetentionService(prisma as never);
    await service.clean();
    expect(tx.chatMessage.deleteMany).toHaveBeenCalledTimes(1);
    expect(tx.studySession.deleteMany).toHaveBeenCalledTimes(1);
    expect(prisma.$transaction).toHaveBeenCalledWith(expect.any(Function), { timeout: 60_000 });
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

describe('TenantRateLimitGuard Redis quotas', () => {
  const reflector = { getAllAndOverride: jest.fn(() => false) };
  function context(request: Record<string, unknown>) {
    return {
      getType: () => 'http', getHandler: () => undefined, getClass: () => undefined,
      switchToHttp: () => ({ getRequest: () => request }),
    };
  }

  it('consumes application and user quotas after authentication', async () => {
    const client = { incr: jest.fn().mockResolvedValueOnce(1).mockResolvedValueOnce(2), expire: jest.fn() };
    const guard = new TenantRateLimitGuard({ client } as never, reflector as never);
    await expect(guard.canActivate(context({ identity: { appId: 'app-1', userId: 'user-1' } }) as never))
      .resolves.toBe(true);
    expect(client.incr).toHaveBeenCalledTimes(2);
    expect(client.expire).toHaveBeenCalledTimes(1);
  });

  it('rejects exceeded admin quotas and skips public routes', async () => {
    process.env.STUDY_ROOM_ADMIN_RATE_LIMIT = '1';
    const client = { incr: jest.fn(async () => 2), expire: jest.fn() };
    const guard = new TenantRateLimitGuard({ client } as never, reflector as never);
    await expect(guard.canActivate(context({ adminIdentity: { subject: 'admin' } }) as never))
      .rejects.toBeInstanceOf(HttpException);
    reflector.getAllAndOverride.mockReturnValueOnce(true);
    await expect(guard.canActivate(context({}) as never)).resolves.toBe(true);
    delete process.env.STUDY_ROOM_ADMIN_RATE_LIMIT;
  });
});
