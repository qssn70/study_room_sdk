import { ArgumentsHost, Catch, ExceptionFilter, HttpException, HttpStatus, Logger } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import { Response } from 'express';
import { AuthenticatedRequest } from '../auth/authenticated-request';

@Catch()
export class ApiExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(ApiExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost) {
    const context = host.switchToHttp();
    const request = context.getRequest<AuthenticatedRequest>();
    const response = context.getResponse<Response>();
    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message: string | string[] = 'Internal server error';
    let code = 'internal_error';
    let details: unknown;

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const body = exception.getResponse();
      if (typeof body === 'string') {
        message = body;
      } else if (body && typeof body === 'object') {
        const value = body as { message?: string | string[]; code?: string; details?: unknown };
        message = value.message ?? exception.message;
        code = value.code ?? this.codeFor(status);
        details = value.details;
      }
    } else if (exception instanceof Prisma.PrismaClientKnownRequestError) {
      if (exception.code === 'P2002') {
        status = HttpStatus.CONFLICT;
        code = 'conflict';
        message = 'Resource already exists';
      } else if (exception.code === 'P2025') {
        status = HttpStatus.NOT_FOUND;
        code = 'not_found';
        message = 'Resource not found';
      }
    }

    if (status >= 500) {
      this.logger.error(
        `${request.method} ${request.originalUrl} failed requestId=${request.requestId ?? 'unknown'}: ${exception instanceof Error ? exception.message : String(exception)}`,
      );
    }
    response.status(status).json({
      code,
      message: Array.isArray(message) ? message.join('; ') : message,
      ...(details === undefined ? {} : { details }),
      requestId: request.requestId ?? 'unknown',
    });
  }

  private codeFor(status: number) {
    return status === 400 ? 'invalid_request'
      : status === 401 ? 'unauthorized'
        : status === 403 ? 'forbidden'
          : status === 404 ? 'not_found'
            : status === 409 ? 'conflict'
              : status === 429 ? 'rate_limited'
                : 'request_failed';
  }
}
