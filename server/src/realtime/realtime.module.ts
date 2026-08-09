import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RoomsStateModule } from '../rooms/rooms-state.module';
import { RealtimeGateway } from './realtime.gateway';

@Module({
  imports: [AuthModule, RoomsStateModule],
  providers: [RealtimeGateway],
  exports: [RealtimeGateway],
})
export class RealtimeModule {}

