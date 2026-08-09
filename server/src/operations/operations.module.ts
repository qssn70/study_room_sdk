import { Module } from '@nestjs/common';
import { MetricsInterceptor } from './metrics.interceptor';
import { MetricsService } from './metrics.service';
import { OperationsController } from './operations.controller';
import { RetentionService } from './retention.service';

@Module({
  controllers: [OperationsController],
  providers: [MetricsService, MetricsInterceptor, RetentionService],
  exports: [MetricsInterceptor],
})
export class OperationsModule {}
