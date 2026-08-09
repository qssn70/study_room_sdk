import { Body, Controller, Get, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { ChatService } from './chat.service';

@ApiTags('chat')
@ApiBearerAuth()
@Controller('rooms/:roomId/chat')
export class ChatController {
  constructor(
    private readonly chat: ChatService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Get()
  async history(
    @Param('roomId') roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
  ) {
    return { messages: this.chat.history(roomId, identity) };
  }

  @Post()
  async send(
    @Param('roomId') roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
    @Body('text') text = '',
  ) {
    const message = this.chat.send(roomId, identity, text);
    this.realtime.publish(identity.appId, roomId, 'chat.message', message);
    return message;
  }
}
