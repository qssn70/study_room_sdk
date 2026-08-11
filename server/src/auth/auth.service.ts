import { Injectable, OnModuleInit, UnauthorizedException } from '@nestjs/common';
import jwt, { JwtHeader, JwtPayload } from 'jsonwebtoken';
import jwksClient, { JwksClient } from 'jwks-rsa';
import { ApplicationsService } from '../applications/applications.service';
import { JwksUriPolicy } from '../applications/jwks-uri.policy';
import { AdminIdentity, ExternalIdentity } from '../domain';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AuthService implements OnModuleInit {
  private readonly clients = new Map<string, JwksClient>();

  constructor(
    private readonly applications: ApplicationsService,
    private readonly prisma: PrismaService,
    private readonly jwksUriPolicy: JwksUriPolicy,
  ) {}

  onModuleInit() {
    this.jwksUriPolicy.assertAllowed(
      this.requiredEnv('STUDY_ROOM_ADMIN_JWKS_URL'),
      'Administrator JWKS URI',
    );
    this.requiredEnv('STUDY_ROOM_ADMIN_JWT_ISSUER');
    this.requiredEnv('STUDY_ROOM_ADMIN_JWT_AUDIENCE');
    this.jwksCacheMs();
  }

  async verifyBearer(authorization?: string): Promise<ExternalIdentity> {
    return this.verifyUserToken(this.bearerToken(authorization));
  }

  async verifyAdminBearer(authorization: string | undefined, requiredScope: string) {
    const token = this.bearerToken(authorization);
    const payload = await this.verify(
      token,
      this.requiredEnv('STUDY_ROOM_ADMIN_JWKS_URL'),
      this.requiredEnv('STUDY_ROOM_ADMIN_JWT_ISSUER'),
      this.requiredEnv('STUDY_ROOM_ADMIN_JWT_AUDIENCE'),
    );
    const scopes = this.scopes(payload.scope);
    if (!scopes.includes(requiredScope)) {
      throw new UnauthorizedException(`Missing required scope: ${requiredScope}`);
    }
    if (typeof payload.sub !== 'string' || typeof payload.exp !== 'number') {
      throw new UnauthorizedException('Admin JWT is missing required claims');
    }
    return {
      subject: payload.sub,
      scopes,
      expiresAt: new Date(payload.exp * 1000),
    } satisfies AdminIdentity;
  }

  async verifyUserToken(token: string): Promise<ExternalIdentity> {
    const decoded = jwt.decode(token);
    if (!decoded || typeof decoded === 'string' || typeof decoded.appId !== 'string') {
      throw new UnauthorizedException('JWT is missing appId');
    }
    const application = await this.applications.getEnabled(decoded.appId).catch(() => {
      throw new UnauthorizedException('Invalid or disabled application');
    });
    const payload = await this.verify(
      token,
      application.jwksUri,
      application.issuer,
      application.audience,
    );
    const { sub, appId, displayName, avatarUrl, exp } = payload;
    if (
      typeof sub !== 'string' || sub.trim().length === 0 || sub.trim().length > 256 ||
      appId !== application.appId ||
      typeof displayName !== 'string' || displayName.trim().length === 0 ||
      typeof exp !== 'number' ||
      (avatarUrl !== undefined && typeof avatarUrl !== 'string')
    ) {
      throw new UnauthorizedException('JWT is missing required claims');
    }
    const identity: ExternalIdentity = {
      userId: sub.trim(),
      appId: application.appId,
      displayName: displayName.trim(),
      avatarUrl: avatarUrl ?? '',
      expiresAt: new Date(exp * 1000),
    };
    await this.prisma.tenantUser.upsert({
      where: { appId_userId: { appId: identity.appId, userId: identity.userId } },
      create: {
        appId: identity.appId,
        userId: identity.userId,
        displayName: identity.displayName,
        avatarUrl: identity.avatarUrl,
      },
      update: { displayName: identity.displayName, avatarUrl: identity.avatarUrl },
    });
    return identity;
  }

  private async verify(token: string, jwksUri: string, issuer: string, audience: string): Promise<JwtPayload> {
    try {
      const decoded = jwt.decode(token, { complete: true });
      if (!decoded || typeof decoded.payload === 'string') {
        throw new UnauthorizedException('JWT payload must be an object');
      }
      const header = decoded.header as JwtHeader;
      if (!header.kid || !['RS256', 'ES256'].includes(header.alg ?? '')) {
        throw new UnauthorizedException('JWT algorithm or kid is invalid');
      }
      const key = await this.client(jwksUri).getSigningKey(header.kid);
      const verified = jwt.verify(token, key.getPublicKey(), {
        algorithms: ['RS256', 'ES256'],
        issuer,
        audience,
      });
      if (typeof verified === 'string') {
        throw new UnauthorizedException('JWT payload must be an object');
      }
      return verified;
    } catch (error) {
      if (error instanceof UnauthorizedException) throw error;
      throw new UnauthorizedException('Invalid or expired JWT');
    }
  }

  private client(uri: string) {
    this.jwksUriPolicy.assertAllowed(uri);
    let client = this.clients.get(uri);
    if (!client) {
      client = jwksClient({
        jwksUri: uri,
        cache: true,
        cacheMaxEntries: 10,
        cacheMaxAge: this.jwksCacheMs(),
        rateLimit: true,
        jwksRequestsPerMinute: 10,
        timeout: 5000,
      });
      this.clients.set(uri, client);
    }
    return client;
  }

  private bearerToken(authorization?: string) {
    if (!authorization?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Bearer token is required');
    }
    const token = authorization.slice('Bearer '.length).trim();
    if (!token) throw new UnauthorizedException('Bearer token is required');
    return token;
  }

  private scopes(value: unknown): string[] {
    if (typeof value === 'string') return value.split(/\s+/).filter(Boolean);
    if (Array.isArray(value)) return value.filter((item): item is string => typeof item === 'string');
    return [];
  }

  private requiredEnv(name: string) {
    const value = process.env[name];
    if (!value) throw new UnauthorizedException(`${name} is not configured`);
    return value;
  }

  private jwksCacheMs() {
    const value = Number(process.env.STUDY_ROOM_JWKS_CACHE_MS ?? 5 * 60 * 1000);
    if (!Number.isSafeInteger(value) || value < 1000 || value > 24 * 60 * 60 * 1000) {
      throw new UnauthorizedException('STUDY_ROOM_JWKS_CACHE_MS must be between 1000 and 86400000');
    }
    return value;
  }
}
