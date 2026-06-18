import { Injectable, UnauthorizedException } from '@nestjs/common';
import jwt, { JwtPayload } from 'jsonwebtoken';
import { ExternalIdentity } from '../domain';

@Injectable()
export class AuthService {
  constructor(private readonly jwtSecret = process.env.STUDY_ROOM_JWT_SECRET ?? 'dev-secret') {}

  async verifyBearer(authorization?: string): Promise<ExternalIdentity> {
    if (!authorization?.startsWith('Bearer ')) {
      throw new UnauthorizedException('Bearer token is required');
    }

    const token = authorization.slice('Bearer '.length);
    const decoded = jwt.verify(token, this.jwtSecret);
    if (typeof decoded === 'string') {
      throw new UnauthorizedException('JWT payload must be an object');
    }

    return this.toIdentity(decoded);
  }

  private toIdentity(payload: JwtPayload): ExternalIdentity {
    const { sub, appId, displayName, avatarUrl } = payload;
    if (
      typeof sub !== 'string' ||
      typeof appId !== 'string' ||
      typeof displayName !== 'string' ||
      typeof avatarUrl !== 'string'
    ) {
      throw new UnauthorizedException('JWT is missing required claims');
    }

    return {
      userId: sub,
      appId,
      displayName,
      avatarUrl,
    };
  }
}

