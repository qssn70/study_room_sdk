import { Injectable, ServiceUnavailableException } from '@nestjs/common';
import { createHash } from 'crypto';
import { RedisService } from '../redis/redis.service';
import { RateLimitExceededException } from './rate-limit.exception';

const WINDOW_MS = 60_000;
const CONSUME_SCRIPT = `
local count = redis.call('INCR', KEYS[1])
local ttl = redis.call('PTTL', KEYS[1])
if count == 1 or ttl < 0 then
  redis.call('PEXPIRE', KEYS[1], ARGV[1])
  ttl = tonumber(ARGV[1])
end
return {count, ttl}
`;

@Injectable()
export class RateLimitService {
  constructor(private readonly redis: RedisService) {}

  configuredLimit(name: string, fallback: number) {
    const configured = Number(process.env[name] ?? fallback);
    return Number.isSafeInteger(configured) && configured > 0 ? configured : fallback;
  }

  async consume(kind: string, identity: string, limit: number) {
    const now = Date.now();
    const window = Math.floor(now / WINDOW_MS);
    const expiryMs = WINDOW_MS - (now % WINDOW_MS);
    const digest = createHash('sha256').update(identity).digest('hex');
    const key = `study-room:rate:v2:${kind}:${digest}:${window}`;
    let result: unknown;
    try {
      result = await this.redis.client.eval(CONSUME_SCRIPT, {
        keys: [key],
        arguments: [String(expiryMs)],
      });
    } catch {
      throw new ServiceUnavailableException({
        code: 'rate_limit_unavailable',
        message: 'Rate limiting is temporarily unavailable',
      });
    }
    if (!Array.isArray(result) || result.length < 2) {
      throw new ServiceUnavailableException({
        code: 'rate_limit_unavailable',
        message: 'Rate limiting returned an invalid response',
      });
    }
    const count = Number(result[0]);
    const ttlMs = Math.max(1, Number(result[1]));
    if (!Number.isFinite(count) || !Number.isFinite(ttlMs)) {
      throw new ServiceUnavailableException({
        code: 'rate_limit_unavailable',
        message: 'Rate limiting returned an invalid response',
      });
    }
    if (count > limit) {
      throw new RateLimitExceededException(
        `${kind} request limit exceeded`,
        Math.max(1, Math.ceil(ttlMs / 1000)),
      );
    }
  }
}
