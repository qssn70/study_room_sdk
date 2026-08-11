import { UnauthorizedException } from '@nestjs/common';
import { generateKeyPairSync } from 'crypto';
import jwt from 'jsonwebtoken';
import { JwksUriPolicy } from '../src/applications/jwks-uri.policy';
import { AuthService } from '../src/auth/auth.service';

describe('AuthService v1 JWKS verification', () => {
  const { privateKey, publicKey } = generateKeyPairSync('rsa', { modulusLength: 2048 });
  const application = {
    appId: 'app-1',
    issuer: 'https://issuer.example',
    audience: 'study-room',
    jwksUri: 'https://issuer.example/.well-known/jwks.json',
    enabled: true,
  };
  const applications = { getEnabled: jest.fn(async () => application) };
  const prisma = { tenantUser: { upsert: jest.fn(async () => undefined) } };
  let service: AuthService;

  beforeEach(() => {
    jest.clearAllMocks();
    delete process.env.STUDY_ROOM_RUNTIME_PROFILE;
    delete process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS;
    delete process.env.STUDY_ROOM_ADMIN_JWKS_URL;
    delete process.env.STUDY_ROOM_ADMIN_JWT_ISSUER;
    delete process.env.STUDY_ROOM_ADMIN_JWT_AUDIENCE;
    service = new AuthService(applications as never, prisma as never, new JwksUriPolicy());
    jest.spyOn(service as never, 'client' as never).mockReturnValue({
      getSigningKey: jest.fn(async () => ({ getPublicKey: () => publicKey.export({ type: 'spki', format: 'pem' }) })),
    } as never);
  });

  function token(overrides: Record<string, unknown> = {}) {
    return jwt.sign(
      { sub: 'user-1', appId: 'app-1', displayName: 'Lin', avatarUrl: '', ...overrides },
      privateKey,
      {
        algorithm: 'RS256',
        keyid: 'key-1',
        issuer: 'https://issuer.example',
        audience: 'study-room',
        expiresIn: '5m',
      },
    );
  }

  it('verifies required claims and refreshes the tenant profile', async () => {
    const identity = await service.verifyBearer(`Bearer ${token()}`);
    expect(identity).toMatchObject({ userId: 'user-1', appId: 'app-1', displayName: 'Lin' });
    expect(identity.expiresAt.getTime()).toBeGreaterThan(Date.now());
    expect(prisma.tenantUser.upsert).toHaveBeenCalledWith(expect.objectContaining({
      where: { appId_userId: { appId: 'app-1', userId: 'user-1' } },
    }));
  });

  it('rejects wrong audience, app mismatch, expired, and missing bearer tokens', async () => {
    await expect(service.verifyBearer()).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer(`Bearer ${token({ appId: 'other' })}`)).rejects.toBeInstanceOf(UnauthorizedException);
    const wrongAudience = jwt.sign(
      { sub: 'user-1', appId: 'app-1', displayName: 'Lin' },
      privateKey,
      { algorithm: 'RS256', keyid: 'key-1', issuer: application.issuer, audience: 'other', expiresIn: '5m' },
    );
    await expect(service.verifyBearer(`Bearer ${wrongAudience}`)).rejects.toBeInstanceOf(UnauthorizedException);
    const expired = jwt.sign(
      { sub: 'user-1', appId: 'app-1', displayName: 'Lin', exp: 1 },
      privateKey,
      { algorithm: 'RS256', keyid: 'key-1', issuer: application.issuer, audience: application.audience },
    );
    await expect(service.verifyBearer(`Bearer ${expired}`)).rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('verifies independent admin tokens and required scopes', async () => {
    process.env.STUDY_ROOM_ADMIN_JWKS_URL = 'https://admin.example/jwks';
    process.env.STUDY_ROOM_ADMIN_JWT_ISSUER = 'https://admin.example';
    process.env.STUDY_ROOM_ADMIN_JWT_AUDIENCE = 'study-room-admin';
    const adminToken = jwt.sign(
      { sub: 'admin-1', scope: 'apps:manage metrics:read' },
      privateKey,
      {
        algorithm: 'RS256', keyid: 'key-1', issuer: 'https://admin.example',
        audience: 'study-room-admin', expiresIn: '5m',
      },
    );
    await expect(service.verifyAdminBearer(`Bearer ${adminToken}`, 'apps:manage')).resolves.toMatchObject({
      subject: 'admin-1', scopes: ['apps:manage', 'metrics:read'],
    });
    await expect(service.verifyAdminBearer(`Bearer ${adminToken}`, 'missing')).rejects.toBeInstanceOf(UnauthorizedException);
    const arrayScope = jwt.sign(
      { sub: 'admin-2', scope: ['apps:manage', 7] },
      privateKey,
      {
        algorithm: 'RS256', keyid: 'key-1', issuer: 'https://admin.example',
        audience: 'study-room-admin', expiresIn: '5m',
      },
    );
    await expect(service.verifyAdminBearer(`Bearer ${arrayScope}`, 'apps:manage'))
      .resolves.toMatchObject({ scopes: ['apps:manage'] });
  });

  it('validates the administrator trust configuration during startup', () => {
    process.env.STUDY_ROOM_ADMIN_JWKS_URL = 'https://admin.example/jwks';
    process.env.STUDY_ROOM_ADMIN_JWT_ISSUER = 'https://admin.example';
    process.env.STUDY_ROOM_ADMIN_JWT_AUDIENCE = 'study-room-admin';
    expect(() => service.onModuleInit()).not.toThrow();

    process.env.STUDY_ROOM_ADMIN_JWKS_URL = 'http://localhost:4000/admin/jwks.json';
    process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS = 'true';
    expect(() => service.onModuleInit()).toThrow('must use HTTPS in production');

    process.env.STUDY_ROOM_RUNTIME_PROFILE = 'test';
    expect(() => service.onModuleInit()).not.toThrow();
  });

  it('rejects malformed claims, algorithms, app lookup failures, and bearer syntax', async () => {
    await expect(service.verifyBearer('Basic value')).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer('Bearer ')).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer('Bearer not-a-jwt')).rejects.toBeInstanceOf(UnauthorizedException);
    applications.getEnabled.mockRejectedValueOnce(new Error('disabled'));
    await expect(service.verifyBearer(`Bearer ${token()}`)).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer(`Bearer ${token({ sub: '' })}`)).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer(`Bearer ${token({ sub: 'u'.repeat(257) })}`))
      .rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer(`Bearer ${token({ displayName: '' })}`)).rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyBearer(`Bearer ${token({ avatarUrl: 7 })}`)).rejects.toBeInstanceOf(UnauthorizedException);
    const hs = jwt.sign(
      { sub: 'user', appId: 'app-1', displayName: 'User' },
      'secret',
      { algorithm: 'HS256', keyid: 'key-1', issuer: application.issuer, audience: application.audience, expiresIn: '5m' },
    );
    await expect(service.verifyBearer(`Bearer ${hs}`)).rejects.toBeInstanceOf(UnauthorizedException);
    delete process.env.STUDY_ROOM_ADMIN_JWKS_URL;
    await expect(service.verifyAdminBearer(`Bearer ${token()}`, 'apps:manage'))
      .rejects.toBeInstanceOf(UnauthorizedException);
  });

  it('rejects admin tokens with missing subject or expiration and handles non-string scopes', async () => {
    process.env.STUDY_ROOM_ADMIN_JWKS_URL = 'https://admin.example/jwks';
    process.env.STUDY_ROOM_ADMIN_JWT_ISSUER = 'https://admin.example';
    process.env.STUDY_ROOM_ADMIN_JWT_AUDIENCE = 'study-room-admin';
    const missingSubject = jwt.sign(
      { scope: 'apps:manage' },
      privateKey,
      {
        algorithm: 'RS256', keyid: 'key-1', issuer: 'https://admin.example',
        audience: 'study-room-admin', expiresIn: '5m',
      },
    );
    const missingExpiration = jwt.sign(
      { sub: 'admin-1', scope: 'apps:manage' },
      privateKey,
      {
        algorithm: 'RS256', keyid: 'key-1', issuer: 'https://admin.example',
        audience: 'study-room-admin',
      },
    );
    await expect(service.verifyAdminBearer(`Bearer ${missingSubject}`, 'apps:manage'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    await expect(service.verifyAdminBearer(`Bearer ${missingExpiration}`, 'apps:manage'))
      .rejects.toBeInstanceOf(UnauthorizedException);
    expect((service as unknown as { scopes(value: unknown): string[] }).scopes({ scope: 'none' })).toEqual([]);
  });

  it('defaults an omitted avatar and covers verified non-object payload protection', async () => {
    await expect(service.verifyBearer(`Bearer ${token({ avatarUrl: undefined })}`)).resolves.toMatchObject({
      avatarUrl: '',
    });

    const decode = jest.spyOn(jwt, 'decode').mockReturnValue({
      header: { alg: 'RS256', kid: 'key-1' },
      payload: {},
      signature: 'signature',
    } as never);
    const verify = jest.spyOn(jwt, 'verify').mockReturnValue('string-payload' as never);
    await expect((service as unknown as {
      verify(tokenValue: string, uri: string, issuer: string, audience: string): Promise<unknown>;
    }).verify('token', application.jwksUri, application.issuer, application.audience))
      .rejects.toBeInstanceOf(UnauthorizedException);
    decode.mockRestore();
    verify.mockRestore();
  });

  it('creates and reuses JWKS clients and validates cache duration bounds', () => {
    jest.restoreAllMocks();
    const privateService = service as unknown as { client(uri: string): unknown };
    process.env.STUDY_ROOM_JWKS_CACHE_MS = '999';
    expect(() => privateService.client('https://new.example/jwks')).toThrow(UnauthorizedException);
    process.env.STUDY_ROOM_JWKS_CACHE_MS = '86400001';
    expect(() => privateService.client('https://new.example/jwks')).toThrow(UnauthorizedException);
    process.env.STUDY_ROOM_JWKS_CACHE_MS = 'not-a-number';
    expect(() => privateService.client('https://new.example/jwks')).toThrow(UnauthorizedException);
    process.env.STUDY_ROOM_JWKS_CACHE_MS = '1000';
    const first = privateService.client('https://new.example/jwks');
    expect(privateService.client('https://new.example/jwks')).toBe(first);
    delete process.env.STUDY_ROOM_JWKS_CACHE_MS;
  });
});
