import { Module } from '@nestjs/common';
import { ApplicationsController } from './applications.controller';
import { ApplicationsService } from './applications.service';
import { JwksUriPolicy } from './jwks-uri.policy';

@Module({
  controllers: [ApplicationsController],
  providers: [ApplicationsService, JwksUriPolicy],
  exports: [ApplicationsService, JwksUriPolicy],
})
export class ApplicationsModule {}
