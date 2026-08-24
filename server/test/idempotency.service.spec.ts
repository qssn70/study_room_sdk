import { BadRequestException } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash } from 'node:crypto';
import { IdempotencyService } from '../src/common/idempotency.service';

const duplicate = () => new Prisma.PrismaClientKnownRequestError('duplicate', {
  code: 'P2002',
  clientVersion: 'test',
  meta: {},
});

const hash = (value: string) => createHash('sha256').update(value).digest('hex');

describe('IdempotencyService', () => {
  const metrics = () => ({
    idempotencyRequests: { inc: jest.fn() },
  });

  it('creates the record and resource in one transaction', async () => {
    const tx = { idempotencyRecord: { create: jest.fn(async () => undefined) } };
    const prisma = {
      $transaction: jest.fn(async (callback) => callback(tx)),
      idempotencyRecord: { findUnique: jest.fn() },
    };
    const observedMetrics = metrics();
    const service = new IdempotencyService(prisma as never, observedMetrics as never);
    const create = jest.fn(async (_transaction, resourceId: string) => ({ id: resourceId }));

    const result = await service.execute({
      appId: 'app-1',
      userId: 'user-1',
      operation: 'rooms.create',
      key: 'room:create-1',
      request: { title: 'Focus' },
      create,
      replay: jest.fn(),
    });

    expect(result).toEqual({ value: { id: expect.any(String) }, created: true });
    expect(tx.idempotencyRecord.create).toHaveBeenCalledWith({
      data: expect.objectContaining({
        appId: 'app-1',
        userId: 'user-1',
        operation: 'rooms.create',
        key: 'room:create-1',
        requestHash: hash('{"title":"Focus"}'),
        resourceId: result.value.id,
      }),
    });
    expect(create).toHaveBeenCalledWith(tx, result.value.id);
    expect(observedMetrics.idempotencyRequests.inc).toHaveBeenCalledWith({
      operation: 'rooms.create',
      outcome: 'created',
    });
  });

  it('replays the current resource for the same normalized request', async () => {
    const prisma = {
      $transaction: jest.fn(async () => { throw duplicate(); }),
      idempotencyRecord: { findUnique: jest.fn(async () => ({
        requestHash: hash('{"roomId":"room-1","text":"Hello"}'),
        resourceId: '00000000-0000-4000-8000-000000000001',
      })) },
    };
    const observedMetrics = metrics();
    const replay = jest.fn(async (resourceId: string) => ({ id: resourceId, text: 'Hello' }));
    const service = new IdempotencyService(prisma as never, observedMetrics as never);

    await expect(service.execute({
      appId: 'app-1',
      userId: 'user-1',
      operation: 'chat.send',
      key: 'message-1',
      request: { text: 'Hello', roomId: 'room-1' },
      create: jest.fn(),
      replay,
    })).resolves.toEqual({
      value: { id: '00000000-0000-4000-8000-000000000001', text: 'Hello' },
      created: false,
    });
    expect(prisma.idempotencyRecord.findUnique).toHaveBeenCalledWith({
      where: {
        appId_userId_operation_key: {
          appId: 'app-1',
          userId: 'user-1',
          operation: 'chat.send',
          key: 'message-1',
        },
      },
    });
    expect(observedMetrics.idempotencyRequests.inc).toHaveBeenCalledWith({
      operation: 'chat.send',
      outcome: 'replayed',
    });
  });

  it('rejects request conflicts and unavailable replay resources', async () => {
    const prisma = {
      $transaction: jest.fn(async () => { throw duplicate(); }),
      idempotencyRecord: { findUnique: jest.fn()
        .mockResolvedValueOnce({ requestHash: 'different', resourceId: 'resource-1' })
        .mockResolvedValueOnce({
          requestHash: hash('{"roomId":"room-1"}'),
          resourceId: 'resource-2',
        }) },
    };
    const observedMetrics = metrics();
    const service = new IdempotencyService(prisma as never, observedMetrics as never);
    const options = {
      appId: 'app-1',
      userId: 'user-1',
      operation: 'sessions.start' as const,
      key: 'session-1',
      request: { roomId: 'room-1' },
      create: jest.fn(),
      replay: jest.fn(async () => undefined),
    };

    await expect(service.execute(options)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'idempotency_conflict' }),
    });
    await expect(service.execute(options)).rejects.toMatchObject({
      response: expect.objectContaining({ code: 'idempotency_result_unavailable' }),
    });
    expect(observedMetrics.idempotencyRequests.inc).toHaveBeenCalledTimes(2);
    expect(observedMetrics.idempotencyRequests.inc).toHaveBeenLastCalledWith({
      operation: 'sessions.start',
      outcome: 'conflict',
    });
  });

  it('rejects malformed keys before opening a transaction', async () => {
    const prisma = { $transaction: jest.fn() };
    const service = new IdempotencyService(prisma as never, metrics() as never);
    await expect(service.execute({
      appId: 'app-1',
      userId: 'user-1',
      operation: 'rooms.create',
      key: 'contains spaces',
      request: {},
      create: jest.fn(),
      replay: jest.fn(),
    })).rejects.toBeInstanceOf(BadRequestException);
    expect(prisma.$transaction).not.toHaveBeenCalled();
  });

  it('does not turn unrelated unique violations into idempotent replay', async () => {
    const prisma = {
      $transaction: jest.fn(async () => { throw duplicate(); }),
      idempotencyRecord: { findUnique: jest.fn(async () => null) },
    };
    const service = new IdempotencyService(prisma as never, metrics() as never);
    await expect(service.execute({
      appId: 'app-1',
      userId: 'user-1',
      operation: 'sessions.start',
      key: 'session-1',
      request: { roomId: 'room-1' },
      create: jest.fn(),
      replay: jest.fn(),
    })).rejects.toBeInstanceOf(Prisma.PrismaClientKnownRequestError);
  });
});
