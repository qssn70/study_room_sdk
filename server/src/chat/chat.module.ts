import { Module } from '@nestjs/common';
import { RealtimeModule } from '../realtime/realtime.module';
import { RoomsStateModule } from '../rooms/rooms-state.module';
import { ChatController } from './chat.controller';
import { ChatService } from './chat.service';

@Module({
  imports: [RoomsStateModule, RealtimeModule],
  controllers: [ChatController],
  providers: [ChatService],
  exports: [ChatService],
})
export class ChatModule {}
