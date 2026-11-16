import { defineConfig } from 'prisma/config';

export default defineConfig({
  schema: 'prisma/schema.prisma',
  migrations: {
    path: 'prisma/migrations',
  },
  // Generate can run without a DB; migrate deploy requires DATABASE_URL.
  datasource: {
    url: process.env.DATABASE_URL!,
  },
});
