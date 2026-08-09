import { Module } from '@nestjs/common';
import { AuthModule } from '../auth/auth.module';
import { RoomsModule } from '../rooms/rooms.module';
import { RealtimeGateway } from './realtime.gateway';

@Module({ imports: [AuthModule, RoomsModule], providers: [RealtimeGateway] })
export class RealtimeModule {}
