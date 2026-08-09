import { Global, Module } from '@nestjs/common';
import { RoomsModule } from './rooms.module';

@Global()
@Module({ imports: [RoomsModule], exports: [RoomsModule] })
export class RoomsStateModule {}
