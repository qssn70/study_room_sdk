import { Injectable, NestMiddleware } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { NextFunction, Response } from 'express';
import { AuthenticatedRequest } from '../auth/authenticated-request';

@Injectable()
export class RequestContextMiddleware implements NestMiddleware {
  use(request: AuthenticatedRequest, response: Response, next: NextFunction) {
    const incoming = request.header('x-request-id');
    request.requestId = incoming && incoming.length <= 128 ? incoming : randomUUID();
    response.setHeader('x-request-id', request.requestId);
    next();
  }
}
