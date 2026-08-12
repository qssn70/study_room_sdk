import { Injectable, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { NextFunction, Response } from 'express';
import { AuthenticatedRequest } from '../auth/authenticated-request';
import { trace } from '@opentelemetry/api';
import {
  applyE2eTraceMarker,
  e2eTraceMarkerHeader,
} from '../telemetry-marker';

@Injectable()
export class RequestContextMiddleware implements NestMiddleware {
  use(request: AuthenticatedRequest, response: Response, next: NextFunction) {
    const incoming = request.header('x-request-id');
    request.requestId = incoming && incoming.length <= 128 ? incoming : randomUUID();
    response.setHeader('x-request-id', request.requestId);
    const span = trace.getActiveSpan();
    if (span) {
      applyE2eTraceMarker(
        span,
        { [e2eTraceMarkerHeader]: request.headers[e2eTraceMarkerHeader] },
        process.env.STUDY_ROOM_RUNTIME_PROFILE,
      );
    }
    next();
  }
}
