import { ServiceUnavailableException } from '@nestjs/common';
import { IpRateLimitGuard } from '../src/common/ip-rate-limit.guard';
import { SKIP_RATE_LIMIT } from '../src/common/rate-limit.decorators';
import { RateLimitExceededException } from '../src/common/rate-limit.exception';
import { RateLimitService } from '../src/common/rate-limit.service';
import { TenantRateLimitGuard } from '../src/common/tenant-rate-limit.guard';
import { ApiExceptionFilter } from '../src/common/api-exception.filter';

function context(request: Record<string, unknown>) {
  return {
    getType: () => 'http',
    getHandler: () => undefined,
    getClass: () => undefined,
    switchToHttp: () => ({ getRequest: () => request }),
  };
}

describe('RateLimitService distributed Redis quota', () => {
  it('uses an opaque fixed-window key and rejects counts over the limit', async () => {
    const client = { eval: jest.fn(async () => [3, 12_500]) };
    const service = new RateLimitService({ client } as never);
    await expect(service.consume('ip', '203.0.113.7', 2)).rejects.toMatchObject({
      retryAfterSeconds: 13,
    });
    const [script, options] = client.eval.mock.calls[0] as unknown as [
      string,
      { keys: string[] },
    ];
    expect(script).toContain("redis.call('INCR'");
    expect(options.keys[0]).toMatch(/^study-room:rate:v2:ip:[a-f0-9]{64}:\d+$/);
    expect(options.keys[0]).not.toContain('203.0.113.7');
  });

  it('maps Redis failures and malformed replies to service unavailable', async () => {
    const failed = new RateLimitService({ client: { eval: jest.fn(async () => { throw new Error('down'); }) } } as never);
    await expect(failed.consume('ip', '127.0.0.1', 1)).rejects.toBeInstanceOf(ServiceUnavailableException);
    const malformed = new RateLimitService({ client: { eval: jest.fn(async () => ['bad']) } } as never);
    await expect(malformed.consume('ip', '127.0.0.1', 1)).rejects.toBeInstanceOf(ServiceUnavailableException);
  });

  it('falls back when configured limits are invalid', () => {
    process.env.STUDY_ROOM_IP_RATE_LIMIT = '0';
    const service = new RateLimitService({ client: {} } as never);
    expect(service.configuredLimit('STUDY_ROOM_IP_RATE_LIMIT', 120)).toBe(120);
    delete process.env.STUDY_ROOM_IP_RATE_LIMIT;
  });
});

describe('distributed rate limit guards', () => {
  it('consumes the IP quota before authentication', async () => {
    const rateLimits = {
      configuredLimit: jest.fn(() => 120),
      consume: jest.fn(async () => undefined),
    };
    const reflector = { getAllAndOverride: jest.fn(() => false) };
    const guard = new IpRateLimitGuard(rateLimits as never, reflector as never);
    await expect(guard.canActivate(context({ ip: '198.51.100.4', socket: {} }) as never)).resolves.toBe(true);
    expect(rateLimits.consume).toHaveBeenCalledWith('ip', '198.51.100.4', 120);
  });

  it('skips only explicitly exempt operations', async () => {
    const rateLimits = { configuredLimit: jest.fn(), consume: jest.fn() };
    const reflector = { getAllAndOverride: jest.fn((key: string) => key === SKIP_RATE_LIMIT) };
    const guard = new IpRateLimitGuard(rateLimits as never, reflector as never);
    await expect(guard.canActivate(context({ socket: {} }) as never)).resolves.toBe(true);
    expect(rateLimits.consume).not.toHaveBeenCalled();
  });

  it('adds application and user quotas after authentication', async () => {
    const rateLimits = {
      configuredLimit: jest.fn((_name: string, fallback: number) => fallback),
      consume: jest.fn(async () => undefined),
    };
    const guard = new TenantRateLimitGuard(rateLimits as never);
    await expect(guard.canActivate(context({ identity: { appId: 'app-1', userId: 'user-1' } }) as never))
      .resolves.toBe(true);
    expect(rateLimits.consume).toHaveBeenNthCalledWith(1, 'app', 'app-1', 600);
    expect(rateLimits.consume).toHaveBeenNthCalledWith(2, 'user', 'app-1:user-1', 180);
  });

  it('adds an administrator quota and preserves quota exceptions', async () => {
    const exceeded = new RateLimitExceededException('admin request limit exceeded', 7);
    const rateLimits = {
      configuredLimit: jest.fn(() => 1),
      consume: jest.fn(async () => { throw exceeded; }),
    };
    const guard = new TenantRateLimitGuard(rateLimits as never);
    await expect(guard.canActivate(context({ adminIdentity: { subject: 'admin' } }) as never)).rejects.toBe(exceeded);
  });
});

describe('rate limit HTTP response', () => {
  it('sets Retry-After before writing the structured error body', () => {
    const response = {
      setHeader: jest.fn(),
      status: jest.fn(),
      json: jest.fn(),
    };
    response.status.mockReturnValue(response);
    const request = { method: 'GET', originalUrl: '/v1/rooms', requestId: 'request-1' };
    const host = {
      switchToHttp: () => ({
        getRequest: () => request,
        getResponse: () => response,
      }),
    };
    new ApiExceptionFilter().catch(
      new RateLimitExceededException('ip request limit exceeded', 9),
      host as never,
    );
    expect(response.setHeader).toHaveBeenCalledWith('Retry-After', '9');
    expect(response.status).toHaveBeenCalledWith(429);
    expect(response.json).toHaveBeenCalledWith({
      code: 'rate_limited',
      message: 'ip request limit exceeded',
      requestId: 'request-1',
    });
  });
});
