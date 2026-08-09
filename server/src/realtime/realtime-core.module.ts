import { Global, Module } from '@nestjs/common';
import { PresenceService } from './presence.service';
import { RealtimePublisher } from './realtime.publisher';

@Global()
@Module({
  providers: [PresenceService, RealtimePublisher],
  exports: [PresenceService, RealtimePublisher],
})
export class RealtimeCoreModule {}
