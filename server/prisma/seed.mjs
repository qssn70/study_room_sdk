import { PrismaClient } from '@prisma/client';

const runtimeProfile = process.env.STUDY_ROOM_RUNTIME_PROFILE ?? 'production';
if (!['dev', 'test'].includes(runtimeProfile) || process.env.STUDY_ROOM_ALLOW_INSECURE_JWKS !== 'true') {
  throw new Error(
    'The demo seed is restricted to an explicit dev/test runtime profile with STUDY_ROOM_ALLOW_INSECURE_JWKS=true',
  );
}

const fixtureBaseUrl = new URL(process.env.STUDY_ROOM_DEV_JWKS_BASE_URL ?? 'http://jwks:4000');
const fixtureHostname = fixtureBaseUrl.hostname.toLowerCase();
const fixtureOctets = fixtureHostname.split('.').map(Number);
const isLoopback = ['localhost', '[::1]'].includes(fixtureHostname) || (
  fixtureOctets.length === 4 && fixtureOctets[0] === 127 && fixtureOctets.every(
    (value) => Number.isInteger(value) && value >= 0 && value <= 255,
  )
);
if (fixtureBaseUrl.protocol !== 'http:' || !(isLoopback || fixtureHostname === 'jwks')) {
  throw new Error('STUDY_ROOM_DEV_JWKS_BASE_URL must use HTTP on localhost, loopback, or the jwks fixture host');
}

const fixtureUrl = (path) => new URL(path, fixtureBaseUrl).toString();
const prisma = new PrismaClient();

try {
  await prisma.application.upsert({
    where: { appId: 'demo' },
    create: {
      appId: 'demo',
      issuer: fixtureUrl('/apps/demo'),
      audience: 'study-room-api',
      jwksUri: fixtureUrl('/apps/demo/jwks.json'),
      enabled: true,
      chatRetentionDays: null,
      sessionRetentionDays: null,
    },
    update: {
      issuer: fixtureUrl('/apps/demo'),
      audience: 'study-room-api',
      jwksUri: fixtureUrl('/apps/demo/jwks.json'),
    },
  });
  console.log('Seeded development application: demo');
} finally {
  await prisma.$disconnect();
}
