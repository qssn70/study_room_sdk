import 'reflect-metadata';
import { existsSync, readFileSync } from 'fs';
import { resolve } from 'path';
import { trustProxyHops } from './common/runtime-config';
import { startTelemetry, stopTelemetry } from './telemetry';

async function bootstrap() {
  const configuredTrustProxyHops = trustProxyHops();
  await startTelemetry();
  const [common, core, swagger, express, helmetModule, yaml, application] = await Promise.all([
    import('@nestjs/common'),
    import('@nestjs/core'),
    import('@nestjs/swagger'),
    import('express'),
    import('helmet'),
    import('js-yaml'),
    import('./app.module'),
  ]);
  const { ConsoleLogger, ValidationPipe } = common;
  const { NestFactory } = core;
  const { SwaggerModule } = swagger;
  const { json } = express;
  const helmet = helmetModule.default;
  const { load } = yaml;
  const { AppModule } = application;
  const app = await NestFactory.create(AppModule, {
    bodyParser: false,
    logger: new ConsoleLogger({ json: process.env.NODE_ENV === 'production' }),
  });
  if (configuredTrustProxyHops > 0) {
    app.getHttpAdapter().getInstance().set('trust proxy', configuredTrustProxyHops);
  }
  app.use(helmet());
  app.use(json({ limit: '64kb' }));

  const configuredAllowedOrigins = process.env.STUDY_ROOM_ALLOWED_ORIGINS;
  if (process.env.NODE_ENV === 'production' && !configuredAllowedOrigins) {
    throw new Error('STUDY_ROOM_ALLOWED_ORIGINS is required in production');
  }
  const allowedOrigins = new Set(
    (configuredAllowedOrigins ?? 'http://localhost:3000,http://localhost:8080')
      .split(',')
      .map((value) => value.trim())
      .filter(Boolean),
  );
  app.enableCors({
    origin(origin: string | undefined, callback: (error: Error | null, allow?: boolean) => void) {
      if (!origin || allowedOrigins.has(origin)) callback(null, true);
      else callback(new Error('Origin is not allowed by CORS'));
    },
    credentials: false,
  });
  app.useGlobalPipes(new ValidationPipe({
    transform: true,
    whitelist: true,
    forbidNonWhitelisted: true,
    stopAtFirstError: false,
  }));
  app.enableShutdownHooks();

  const candidates = [
    resolve(process.cwd(), 'contracts', 'openapi.yaml'),
    resolve(process.cwd(), '..', 'contracts', 'openapi.yaml'),
  ];
  const contractPath = candidates.find(existsSync);
  if (contractPath) {
    const document = load(readFileSync(contractPath, 'utf8')) as Parameters<typeof SwaggerModule.setup>[2];
    SwaggerModule.setup('/docs/openapi', app, document);
  }

  const port = Number(process.env.PORT ?? 3000);
  await app.listen(port);
  const shutdown = async () => {
    await app.close();
    await stopTelemetry();
  };
  process.once('SIGTERM', () => void shutdown());
  process.once('SIGINT', () => void shutdown());
}

void bootstrap();
