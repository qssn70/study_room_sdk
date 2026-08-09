import { Body, Controller, Get, Param, ParseUUIDPipe, Post, Query } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { CurrentIdentity } from '../auth/current-identity.decorator';
import { ExternalIdentity } from '../domain';
import { RealtimePublisher } from '../realtime/realtime.publisher';
import { MessagePageQueryDto, SendMessageDto } from './chat.dto';
import { ChatService } from './chat.service';

@ApiTags('chat')
@ApiBearerAuth()
@Controller('v1/rooms/:roomId/messages')
export class ChatController {
  constructor(private readonly chat: ChatService, private readonly realtime: RealtimePublisher) {}

  @Get()
  history(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
    @Query() query: MessagePageQueryDto,
  ) {
    return this.chat.history(roomId, identity, query.cursor, query.limit);
  }

  @Post()
  async send(
    @Param('roomId', new ParseUUIDPipe({ version: '4' })) roomId: string,
    @CurrentIdentity() identity: ExternalIdentity,
    @Body() body: SendMessageDto,
  ) {
    const message = await this.chat.send(roomId, identity, body.text);
    this.realtime.publishRoom(identity.appId, roomId, 'chat.message.created', message, null);
    return message;
  }
}
