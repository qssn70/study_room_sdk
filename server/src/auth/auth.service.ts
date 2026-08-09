import { Injectable, UnauthorizedException } from '@nestjs/common';
import jwt, { JwtPayload } from 'jsonwebtoken';
import { ExternalIdentity } from '../domain';

@Injectable()
export class AuthService {
  private readonly jwtSecret: string;

  constructor(jwtSecret?: string) {
    const configured = jwtSecret ?? process.env.STUDY_ROOM_JWT_SECRET;
    if (!configured?.trim()) {
      throw new Error('STUDY_ROOM_JWT_SECRET is required');
    }
    this.jwtSecret = configured;
  }

  async verifyBearer(authorization?: string): Promise<ExternalIdentity> {
    if (!authorization?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Bearer token is required');
    }

    return this.verifyToken(authorization.slice('Bearer '.length));
  }

  async verifyToken(token: string): Promise<ExternalIdentity> {
    try {
      const decoded = jwt.verify(token, this.jwtSecret, {
        algorithms: ['HS256'],
      });
      if (typeof decoded === 'string') {
        throw new UnauthorizedException('JWT payload must be an object');
      }
      return this.toIdentity(decoded);
    } catch (error) {
      if (error instanceof UnauthorizedException) {
        throw error;
      }
      throw new UnauthorizedException('Invalid or expired JWT');
    }
  }

  private toIdentity(payload: JwtPayload): ExternalIdentity {
    const { sub, appId, displayName, avatarUrl, exp } = payload;
    if (
      typeof sub !== 'string' || sub.trim().length === 0 ||
      typeof appId !== 'string' || appId.trim().length === 0 ||
      typeof displayName !== 'string' || displayName.trim().length === 0 ||
      typeof exp !== 'number' ||
      (avatarUrl !== undefined && typeof avatarUrl !== 'string')
    ) {
      throw new UnauthorizedException('JWT is missing required claims');
    }

    return {
      userId: sub.trim(),
      appId: appId.trim(),
      displayName: displayName.trim(),
      avatarUrl: avatarUrl ?? '',
    };
  }
}

