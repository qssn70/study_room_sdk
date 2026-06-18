import { Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module';
import { ChatModule } from './chat/chat.module';
import { RealtimeModule } from './realtime/realtime.module';
import { RoomsModule } from './rooms/rooms.module';
import { SessionsModule } from './sessions/sessions.module';

@Module({
  imports: [AuthModule, RoomsModule, SessionsModule, ChatModule, RealtimeModule],
})
export class AppModule {}

