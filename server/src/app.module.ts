import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { AuthModule } from './auth/auth.module';
import { AuthGuard } from './auth/auth.guard';
import { ChatModule } from './chat/chat.module';
import { RealtimeModule } from './realtime/realtime.module';
import { RoomsModule } from './rooms/rooms.module';
import { RoomsStateModule } from './rooms/rooms-state.module';
import { SessionsModule } from './sessions/sessions.module';

@Module({
  imports: [
    AuthModule,
    RoomsStateModule,
    RoomsModule,
    SessionsModule,
    ChatModule,
    RealtimeModule,
  ],
  providers: [{ provide: APP_GUARD, useClass: AuthGuard }],
})
export class AppModule {}

