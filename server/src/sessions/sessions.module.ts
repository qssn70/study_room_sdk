import { Module } from '@nestjs/common';
import { RoomsModule } from '../rooms/rooms.module';
import { SessionsController } from './sessions.controller';
import { SessionsService } from './sessions.service';

@Module({ imports: [RoomsModule], controllers: [SessionsController], providers: [SessionsService] })
export class SessionsModule {}
