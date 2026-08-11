import { Injectable } from '@nestjs/common';

export type StudyRoomRuntimeProfile = 'production' | 'dev' | 'test';

export class JwksUriPolicyError extends Error {
  constructor(message: string) {
    super(message);
    this.name = 'JwksUriPolicyError';
  }
}

@Injectable()
export class JwksUriPolicy {
  assertAllowed(value: string, label = 'JWKS URI'): URL {
    const profile = this.runtimeProfile();
    let uri: URL;
    try {
      uri = new URL(value);
    } catch {
      throw new JwksUriPolicyError(`${label} must be an absolute URL`);
    }

    if (uri.protocol === 'https:') return uri;
    if (uri.protocol !== 'http:') {
      throw new JwksUriPolicyError(`${label} must use HTTPS`);
    }
    if (profile === 'production') {
      throw new JwksUriPolicyError(`${label} must use HTTPS in production`);
    }
    if (process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS !== 'true') {
      throw new JwksUriPolicyError(
        `${label} may use HTTP in dev/test only when STUDY_ROOM_ALLOW_INSECURE_JWKS=true`,
      );
    }
    if (!this.isLocalFixtureHost(uri.hostname)) {
      throw new JwksUriPolicyError(
        `${label} may use HTTP in dev/test only for localhost, loopback addresses, or the jwks fixture host`,
      );
    }
    return uri;
  }

  runtimeProfile(): StudyRoomRuntimeProfile {
    const profile = process.env.STUDY_ROOM_RUNTIME_PROFILE ?? 'production';
    if (profile === 'production' || profile === 'dev' || profile === 'test') return profile;
    throw new JwksUriPolicyError(
      'STUDY_ROOM_RUNTIME_PROFILE must be one of production, dev, or test',
    );
  }

  private isLocalFixtureHost(hostname: string): boolean {
    const normalized = hostname.toLowerCase();
    if (normalized === 'localhost' || normalized === 'jwks' || normalized === '[::1]') return true;
    const octets = normalized.split('.').map(Number);
    return octets.length === 4 && octets[0] === 127 && octets.every(
      (value) => Number.isInteger(value) && value >= 0 && value <= 255,
    );
  }
}
