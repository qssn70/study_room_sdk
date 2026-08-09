import { PrismaClient } from '@prisma/client';

const prisma = new PrismaClient();

try {
  await prisma.application.upsert({
    where: { appId: 'demo' },
    create: {
      appId: 'demo',
      issuer: 'http://jwks:4000/apps/demo',
      audience: 'study-room-api',
      jwksUri: 'http://jwks:4000/apps/demo/jwks.json',
      enabled: true,
      chatRetentionDays: null,
      sessionRetentionDays: null,
    },
    update: {
      issuer: 'http://jwks:4000/apps/demo',
      audience: 'study-room-api',
      jwksUri: 'http://jwks:4000/apps/demo/jwks.json',
    },
  });
  console.log('Seeded development application: demo');
} finally {
  await prisma.$disconnect();
}
