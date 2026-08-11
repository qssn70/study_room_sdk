import { Controller, Get, Header, ServiceUnavailableException } from '@nestjs/common';
import { AdminScope, Public } from '../auth/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { MetricsService } from './metrics.service';
import { SkipRateLimit } from '../common/rate-limit.decorators';

const READINESS_DEADLINE_MS = 3_000;

@Controller()
export class OperationsController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
    private readonly metrics: MetricsService,
  ) {}

  @Public()
  @SkipRateLimit()
  @Get('health/live')
  live() {
    return { status: 'ok' };
  }

  @Public()
  @SkipRateLimit()
  @Get('health/ready')
  async ready() {
    try {
      await this.withDeadline(Promise.all([
        this.prisma.$queryRaw`SELECT 1`,
        this.redis.ping().then((available) => {
          if (!available) throw new Error('Redis is unavailable');
        }),
      ]));
      return { status: 'ready' };
    } catch {
      throw new ServiceUnavailableException('Dependencies are unavailable');
    }
  }

  private async withDeadline<T>(operation: Promise<T>): Promise<T> {
    let timeout: NodeJS.Timeout | undefined;
    try {
      return await Promise.race([
        operation,
        new Promise<never>((_, reject) => {
          timeout = setTimeout(
            () => reject(new Error('Readiness probe timed out')),
            READINESS_DEADLINE_MS,
          );
        }),
      ]);
    } finally {
      if (timeout) clearTimeout(timeout);
    }
  }

  @AdminScope('metrics:read')
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  @Get('metrics')
  metricsText() {
    return this.metrics.registry.metrics();
  }
}
