import { Module } from '@nestjs/common';
import { ApplicationsModule } from '../applications/applications.module';
import { AuthService } from './auth.service';

@Module({
  imports: [ApplicationsModule],
  providers: [AuthService],
  exports: [AuthService],
})
export class AuthModule {}
