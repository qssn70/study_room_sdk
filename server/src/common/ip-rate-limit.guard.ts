import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthenticatedRequest } from '../auth/authenticated-request';
import { SKIP_RATE_LIMIT } from './rate-limit.decorators';
import { RateLimitService } from './rate-limit.service';

@Injectable()
export class IpRateLimitGuard implements CanActivate {
  constructor(
    private readonly rateLimits: RateLimitService,
    private readonly reflector: Reflector,
  ) {}

  async canActivate(context: ExecutionContext) {
    if (context.getType() !== 'http') return true;
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(SKIP_RATE_LIMIT, targets)) return true;
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const address = request.ip || request.socket.remoteAddress || 'unknown';
    await this.rateLimits.consume(
      'ip',
      address,
      this.rateLimits.configuredLimit('STUDY_ROOM_IP_RATE_LIMIT', 120),
    );
    return true;
  }
}
