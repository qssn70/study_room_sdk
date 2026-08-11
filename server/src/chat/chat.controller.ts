import { Body, Controller, Get, Param, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import {
  ListMessagesParamsDto,
  ListMessagesQueryDto,
  SendMessageBodyDto,
  SendMessageParamsDto,
} from '../generated/request-dtos';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { ChatService } from './chat.service';

@ApiTags('chat')
@ApiBearerAuth()
@Controller('v1/rooms/:roomId/messages')
export class ChatController {
  constructor(private readonly chat: ChatService, private readonly realtime: RealtimePublisher) {}

  @Get()
  history(
    @Param() params: ListMessagesParamsDto,
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: ListMessagesQueryDto,
  ) {
    return this.chat.history(params.roomId, identity, query.cursor, query.limit);
  }

  @Post()
  async send(
    @Param() params: SendMessageParamsDto,
    @CurrentIdentity() identity: ExternalIdentity,
    @Body() body: SendMessageBodyDto,
  ) {
    const message = await this.chat.send(params.roomId, identity, body.text);
    this.realtime.publishRoom(identity.appId, params.roomId, 'chat.message.created', message, null);
    return message;
  }
}
