import { BadRequestException, NotFoundException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { APPLICATION_CHANGE_CHANNEL, ApplicationsService } from '../src/applications/applications.service';

const app = {
  appId: 'app-1', issuer: 'https://issuer.example', audience: 'api',
  jwksUri: 'https://issuer.example/jwks.json', enabled: true,
  chatRetentionDays: null, sessionRetentionDays: null,
  createdAt: new Date(), updatedAt: new Date(),
};

describe('ApplicationsService registry and invalidation', () => {
  const redis = {
    subscribe: jest.fn(async (_channel, handler) => { redis.handler = handler; }),
    publish: jest.fn(async () => undefined),
    handler: undefined as undefined | ((message: string) => void),
  };

  beforeEach(() => {
    jest.clearAllMocks();
    redis.handler = undefined;
    delete process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS;
  });

  it('creates, audits, publishes, and invalidates cached applications', async () => {
    const tx = {
      application: { create: jest.fn(async () => app) },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = {
      $transaction: jest.fn(async (callback) => callback(tx)),
      application: { findUnique: jest.fn(async () => app) },
    };
    const service = new ApplicationsService(prisma as never, redis as never);
    await service.onModuleInit();
    await expect(service.create({
      appId: app.appId, issuer: app.issuer, audience: app.audience, jwksUri: app.jwksUri,
    }, 'admin-1')).resolves.toEqual(app);
    expect(redis.publish).toHaveBeenCalledWith(APPLICATION_CHANGE_CHANNEL, expect.stringContaining('app-1'));
    await service.get('app-1');
    await service.get('app-1');
    expect(prisma.application.findUnique).toHaveBeenCalledTimes(1);
    redis.handler?.('{"appId":"app-1"}');
    await service.get('app-1');
    expect(prisma.application.findUnique).toHaveBeenCalledTimes(2);
  });

  it('updates and lists applications while mapping missing records', async () => {
    const tx = {
      application: { update: jest.fn(async () => ({ ...app, enabled: false })) },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = {
      $transaction: jest.fn(async (callback) => callback(tx)),
      application: {
        findMany: jest.fn(async () => [app, { ...app, appId: 'app-2' }, { ...app, appId: 'app-3' }]),
      },
    };
    const service = new ApplicationsService(prisma as never, redis as never);
    await expect(service.update('app-1', { enabled: false }, 'admin')).resolves.toMatchObject({ enabled: false });
    await expect(service.list('cursor', 2)).resolves.toMatchObject({
      items: [{ appId: 'app-1' }, { appId: 'app-2' }], nextCursor: 'app-2',
    });

    const missing = new Prisma.PrismaClientKnownRequestError('missing', {
      code: 'P2025', clientVersion: 'test', meta: {},
    });
    prisma.$transaction.mockRejectedValueOnce(missing);
    await expect(service.update('missing', {}, 'admin')).rejects.toBeInstanceOf(NotFoundException);
  });

  it('hides disabled/missing applications and rejects unsafe JWKS URLs', async () => {
    const prisma = { application: { findUnique: jest
      .fn()
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce({ ...app, enabled: false }) } };
    const service = new ApplicationsService(prisma as never, redis as never);
    await expect(service.get('missing')).rejects.toBeInstanceOf(NotFoundException);
    await expect(service.getEnabled('app-1')).rejects.toBeInstanceOf(NotFoundException);
    await expect(service.create({
      appId: 'app-2', issuer: 'issuer', audience: 'api', jwksUri: 'http://remote.example/jwks',
    }, 'admin')).rejects.toBeInstanceOf(BadRequestException);
  });

  it('allows explicitly opted-in local JWKS and returns a final page', async () => {
    process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS = 'true';
    const tx = {
      application: { create: jest.fn(async () => ({ ...app, jwksUri: 'http://localhost/jwks' })) },
      auditLog: { create: jest.fn(async () => undefined) },
    };
    const prisma = {
      $transaction: jest.fn(async (callback) => callback(tx)),
      application: { findMany: jest.fn(async () => [app]) },
    };
    const service = new ApplicationsService(prisma as never, redis as never);
    await expect(service.create({
      appId: 'app-1', issuer: 'issuer', audience: 'audience',
      jwksUri: 'http://localhost/jwks', enabled: false,
    }, 'admin')).resolves.toBeDefined();
    await expect(service.list(undefined, 0)).resolves.toEqual({ items: [app], nextCursor: null });
  });
});
