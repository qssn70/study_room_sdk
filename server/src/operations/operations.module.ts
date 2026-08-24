import { Module } from '@nestjs/common';
import { IdempotencyService } from '../common/idempotency.service';
import { MetricsInterceptor } from './metrics.interceptor';
import { MetricsService } from './metrics.service';
import { OperationsController } from './operations.controller';
import { RetentionService } from './retention.service';

@Module({
  controllers: [OperationsController],
  providers: [MetricsService, MetricsInterceptor, RetentionService, IdempotencyService],
  exports: [MetricsInterceptor, MetricsService, IdempotencyService],
})
export class OperationsModule {}
