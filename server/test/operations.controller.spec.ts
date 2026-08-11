import { ServiceUnavailableException } from '@nestjs/common';
import { OperationsController } from '../src/operations/operations.controller';

describe('OperationsController health probes', () => {
  const createController = (options: {
    postgres?: () => Promise<unknown>;
    redis?: () => Promise<boolean>;
  } = {}) => {
    const prisma = {
      $queryRaw: jest.fn(options.postgres ?? (async () => [{ '?column?': 1 }])),
    };
    const redis = {
      ping: jest.fn(options.redis ?? (async () => true)),
    };
    const metrics = { registry: { metrics: jest.fn() } };

    return {
      controller: new OperationsController(prisma as never, redis as never, metrics as never),
      prisma,
      redis,
    };
  };

  afterEach(() => {
    jest.useRealTimers();
  });

  it('reports live and ready when both dependencies are healthy', async () => {
    const { controller, prisma, redis } = createController();

    expect(controller.live()).toEqual({ status: 'ok' });
    await expect(controller.ready()).resolves.toEqual({ status: 'ready' });
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    expect(redis.ping).toHaveBeenCalledTimes(1);
  });

  it('returns service unavailable when PostgreSQL rejects', async () => {
    const { controller } = createController({
      postgres: async () => { throw new Error('connection refused'); },
    });

    await expect(controller.ready()).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('returns service unavailable when Redis reports unavailable', async () => {
    const { controller } = createController({ redis: async () => false });

    await expect(controller.ready()).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('starts both probes in parallel and times out a permanently pending probe', async () => {
    jest.useFakeTimers();
    const { controller, prisma, redis } = createController({
      postgres: () => new Promise(() => undefined),
    });

    const readiness = controller.ready();
    expect(prisma.$queryRaw).toHaveBeenCalledTimes(1);
    expect(redis.ping).toHaveBeenCalledTimes(1);

    await jest.advanceTimersByTimeAsync(2_999);
    let settled = false;
    void readiness.then(
      () => { settled = true; },
      () => { settled = true; },
    );
    await Promise.resolve();
    expect(settled).toBe(false);

    await jest.advanceTimersByTimeAsync(1);
    await expect(readiness).rejects.toBeInstanceOf(ServiceUnavailableException);
  });
});
