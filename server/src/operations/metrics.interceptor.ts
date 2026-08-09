import { CallHandler, ExecutionContext, Injectable, NestInterceptor } from '@nestjs/common';
import { Request, Response } from 'express';
import { Observable, tap } from 'rxjs';
import { MetricsService } from './metrics.service';

@Injectable()
export class MetricsInterceptor implements NestInterceptor {
  constructor(private readonly metrics: MetricsService) {}

  intercept(context: ExecutionContext, next: CallHandler): Observable<unknown> {
    if (context.getType() !== 'http') return next.handle();
    const http = context.switchToHttp();
    const request = http.getRequest<Request>();
    const response = http.getResponse<Response>();
    const started = process.hrtime.bigint();
    return next.handle().pipe(tap({ finalize: () => {
      const duration = Number(process.hrtime.bigint() - started) / 1_000_000_000;
      const route = `${request.baseUrl}${request.route?.path ?? ''}` || 'unmatched';
      const labels = { method: request.method, route, status: String(response.statusCode) };
      this.metrics.httpDuration.observe(labels, duration);
      if (response.statusCode >= 400) this.metrics.httpErrors.inc(labels);
    } }));
  }
}
