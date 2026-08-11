import { HttpException } from '@nestjs/common';

export class RateLimitExceededException extends HttpException {
  constructor(
    message: string,
    readonly retryAfterSeconds: number,
  ) {
    super({ code: 'rate_limited', message }, 429);
  }
}
