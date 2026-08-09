import { CanActivate, ExecutionContext, HttpException, Injectable } from '@nestjs/common';
import { Reflector } from '@nestjs/core';
import { AuthenticatedRequest } from '../auth/authenticated-request';
import { PUBLIC_ROUTE } from '../auth/auth.decorators';
import { RedisService } from '../redis/redis.service';

@Injectable()
export class TenantRateLimitGuard implements CanActivate {
  constructor(private readonly redis: RedisService, private readonly reflector: Reflector) {}

  async canActivate(context: ExecutionContext) {
    if (context.getType() !== 'http') return true;
    const targets = [context.getHandler(), context.getClass()];
    if (this.reflector.getAllAndOverride<boolean>(PUBLIC_ROUTE, targets)) return true;
    const request = context.switchToHttp().getRequest<AuthenticatedRequest>();
    const identity = request.identity;
    if (identity) {
      await this.consume('app', identity.appId, this.limit('STUDY_ROOM_APP_RATE_LIMIT', 600));
      await this.consume(
        'user',
        `${identity.appId}:${identity.userId}`,
        this.limit('STUDY_ROOM_USER_RATE_LIMIT', 180),
      );
    } else if (request.adminIdentity) {
      await this.consume(
        'admin',
        request.adminIdentity.subject,
        this.limit('STUDY_ROOM_ADMIN_RATE_LIMIT', 120),
      );
    }
    return true;
  }

  private async consume(kind: string, identity: string, limit: number) {
    const window = Math.floor(Date.now() / 60_000);
    const encoded = Buffer.from(identity).toString('base64url');
    const key = `study-room:rate:${kind}:${encoded}:${window}`;
    const count = await this.redis.client.incr(key);
    if (count === 1) await this.redis.client.expire(key, 65);
    if (count > limit) {
      throw new HttpException(
        { code: 'rate_limited', message: `${kind} request limit exceeded` },
        429,
      );
    }
  }

  private limit(name: string, fallback: number) {
    const configured = Number(process.env[name] ?? fallback);
    return Number.isSafeInteger(configured) && configured > 0 ? configured : fallback;
  }
}
