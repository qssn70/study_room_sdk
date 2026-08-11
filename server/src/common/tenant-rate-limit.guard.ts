import { CanActivate, ExecutionContext, Injectable } from '@nestjs/common';
import { AuthenticatedRequest } from '../auth/authenticated-request';
import { RateLimitService } from './rate-limit.service';

@Injectable()
export class TenantRateLimitGuard implements CanActivate {
  constructor(private readonly rateLimits: RateLimitService) {}

  async canActivate(context: ExecutionContext) {
    if (context.getType() !== 'http') return true;
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const identity = request.identity;
    if (identity) {
      await this.rateLimits.consume(
        'app',
        identity.appId,
        this.rateLimits.configuredLimit('STUDY_ROOM_APP_RATE_LIMIT', 600),
      );
      await this.rateLimits.consume(
        'user',
        `${identity.appId}:${identity.userId}`,
        this.rateLimits.configuredLimit('STUDY_ROOM_USER_RATE_LIMIT', 180),
      );
    } else if (request.adminIdentity) {
      await this.rateLimits.consume(
        'admin',
        request.adminIdentity.subject,
        this.rateLimits.configuredLimit('STUDY_ROOM_ADMIN_RATE_LIMIT', 120),
      );
    }
    return true;
  }
}
