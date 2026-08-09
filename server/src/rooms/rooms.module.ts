import { Module } from '@nestjs/common';
import { RealtimeModule } from '../realtime/realtime.module';
import { RoomsController } from './rooms.controller';
import { RoomsStateModule } from './rooms-state.module';

@Module({
  imports: [RoomsStateModule, RealtimeModule],
  controllers: [RoomsController],
})
export class RoomsModule {}
