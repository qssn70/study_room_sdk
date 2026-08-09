import { MiddlewareConsumer, Module, NestModule } from '@nestjs/common';
import { APP_FILTER, APP_GUARD, APP_INTERCEPTOR } from '@nestjs/core';
import { ScheduleModule } from '@nestjs/schedule';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { ApplicationsModule } from './applications/applications.module';
import { AuthGuard } from './auth/auth.guard';
import { AuthModule } from './auth/auth.module';
import { ChatModule } from './chat/chat.module';
import { ApiExceptionFilter } from './common/api-exception.filter';
import { RequestContextMiddleware } from './common/request-context.middleware';
import { TenantRateLimitGuard } from './common/tenant-rate-limit.guard';
import { OperationsModule } from './operations/operations.module';
import { MetricsInterceptor } from './operations/metrics.interceptor';
import { PrismaModule } from './prisma/prisma.module';
import { RealtimeCoreModule } from './realtime/realtime-core.module';
import { RealtimeModule } from './realtime/realtime.module';
import { RedisModule } from './redis/redis.module';
import { RoomsModule } from './rooms/rooms.module';
import { SessionsModule } from './sessions/sessions.module';

@Module({
  imports: [
    PrismaModule,
    RedisModule,
    RealtimeCoreModule,
    ScheduleModule.forRoot(),
    ThrottlerModule.forRoot([{ ttl: 60_000, limit: 120 }]),
    ApplicationsModule,
    AuthModule,
    RoomsModule,
    SessionsModule,
    ChatModule,
    RealtimeModule,
    OperationsModule,
  ],
  providers: [
    { provide: APP_GUARD, useClass: ThrottlerGuard },
    { provide: APP_GUARD, useClass: AuthGuard },
    { provide: APP_GUARD, useClass: TenantRateLimitGuard },
    { provide: APP_FILTER, useClass: ApiExceptionFilter },
    { provide: APP_INTERCEPTOR, useExisting: MetricsInterceptor },
  ],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestContextMiddleware).forRoutes('*');
  }
}
