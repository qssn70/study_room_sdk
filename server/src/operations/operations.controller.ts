import { Controller, Get, Header, ServiceUnavailableException } from '@nestjs/common';
import { AdminScope, Public } from '../auth/auth.decorators';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';
import { MetricsService } from './metrics.service';
import { SkipRateLimit } from '../common/rate-limit.decorators';

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
      await this.prisma.$queryRaw`SELECT 1`;
      if (!(await this.redis.ping())) throw new Error('Redis is unavailable');
      return { status: 'ready' };
    } catch {
      throw new ServiceUnavailableException('Dependencies are unavailable');
    }
  }

  @AdminScope('metrics:read')
  @Header('Content-Type', 'text/plain; version=0.0.4; charset=utf-8')
  @Get('metrics')
  metricsText() {
    return this.metrics.registry.metrics();
  }
}
