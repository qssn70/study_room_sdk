import { Injectable } from '@nestjs/common';
import { Counter, collectDefaultMetrics, Histogram, Registry } from 'prom-client';

@Injectable()
export class MetricsService {
  readonly registry = new Registry();
  readonly httpDuration = new Histogram({
    name: 'study_room_http_request_duration_seconds',
    help: 'HTTP request latency without user or room labels.',
    labelNames: ['method', 'route', 'status'] as const,
    buckets: [0.01, 0.05, 0.1, 0.25, 0.5, 1, 2, 5],
    registers: [this.registry],
  });
  readonly httpErrors = new Counter({
    name: 'study_room_http_errors_total',
    help: 'HTTP errors without high-cardinality labels.',
    labelNames: ['method', 'route', 'status'] as const,
    registers: [this.registry],
  });

  constructor() {
    collectDefaultMetrics({ register: this.registry, prefix: 'study_room_' });
  }
}
