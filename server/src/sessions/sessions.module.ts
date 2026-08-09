import { Module } from '@nestjs/common';
import { RealtimeModule } from '../realtime/realtime.module';
import { RoomsStateModule } from '../rooms/rooms-state.module';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';

@Module({
  imports: [RoomsStateModule, RealtimeModule],
  controllers: [SessionsController],
  providers: [SessionsService],
  exports: [SessionsService],
})
export class SessionsModule {}
