import {
  BadRequestException,
  ConflictException,
  Injectable,
} from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { createHash, randomUUID } from 'node:crypto';
import { MetricsService } from '../operations/metrics.service';
import { PrismaService } from '../prisma/prisma.service';

export const IDEMPOTENCY_OPERATIONS = [
  'rooms.create',
  'chat.send',
  'sessions.start',
] as const;

export type IdempotencyOperation = (typeof IDEMPOTENCY_OPERATIONS)[number];

export interface IdempotentResult<T> {
  value: T;
  created: boolean;
}

interface ExecuteOptions<T> {
  appId: string;
  userId: string;
  operation: IdempotencyOperation;
  key: string;
  request: unknown;
  create: (
    tx: Prisma.TransactionClient,
    resourceId: string,
  ) => Promise<T>;
  replay: (resourceId: string) => Promise<T | undefined>;
}

const idempotencyKeyPattern = /^[A-Za-z0-9._:-]{1,128}$/;

@Injectable()
export class IdempotencyService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly metrics: MetricsService,
  ) {}

  async execute<T>(options: ExecuteOptions<T>): Promise<IdempotentResult<T>> {
    this.validateKey(options.key);
    const requestHash = this.hash(options.request);
    const resourceId = randomUUID();
    try {
      const value = await this.prisma.$transaction(async (tx) => {
        await tx.idempotencyRecord.create({
          data: {
            appId: options.appId,
            userId: options.userId,
            operation: options.operation,
            key: options.key,
            requestHash,
            resourceId,
          },
        });
        return options.create(tx, resourceId);
      });
      this.metrics.idempotencyRequests.inc({
        operation: options.operation,
        outcome: 'created',
      });
      return { value, created: true };
    } catch (error) {
      if (!this.isUniqueViolation(error)) throw error;
      const record = await this.prisma.idempotencyRecord.findUnique({
        where: {
          appId_userId_operation_key: {
            appId: options.appId,
            userId: options.userId,
            operation: options.operation,
            key: options.key,
          },
        },
      });
      if (!record) throw error;
      if (record.requestHash !== requestHash) {
        this.conflict(options.operation, 'idempotency_conflict',
          'Idempotency key was already used with a different request');
      }
      const value = await options.replay(record.resourceId);
      if (!value) {
        this.conflict(options.operation, 'idempotency_result_unavailable',
          'The resource created for this idempotency key is no longer available');
      }
      this.metrics.idempotencyRequests.inc({
        operation: options.operation,
        outcome: 'replayed',
      });
      return { value, created: false };
    }
  }

  private validateKey(key: string) {
    if (!idempotencyKeyPattern.test(key)) {
      throw new BadRequestException({
        code: 'invalid_idempotency_key',
        message:
          'Idempotency-Key must contain 1 to 128 A-Z, a-z, 0-9, dot, underscore, colon, or hyphen characters',
      });
    }
  }

  private hash(request: unknown) {
    return createHash('sha256')
      .update(JSON.stringify(this.canonicalize(request)))
      .digest('hex');
  }

  private canonicalize(value: unknown): unknown {
    if (Array.isArray(value)) return value.map((item) => this.canonicalize(item));
    if (value && typeof value === 'object') {
      return Object.fromEntries(
        Object.entries(value as Record<string, unknown>)
          .sort(([left], [right]) => left.localeCompare(right))
          .map(([key, item]) => [key, this.canonicalize(item)]),
      );
    }
    return value;
  }

  private isUniqueViolation(error: unknown) {
    return error instanceof Prisma.PrismaClientKnownRequestError
      && error.code === 'P2002';
  }

  private conflict(
    operation: IdempotencyOperation,
    code: 'idempotency_conflict' | 'idempotency_result_unavailable',
    message: string,
  ): never {
    this.metrics.idempotencyRequests.inc({ operation, outcome: 'conflict' });
    throw new ConflictException({ code, message });
  }
}
