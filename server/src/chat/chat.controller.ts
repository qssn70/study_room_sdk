import { Body, Controller, Get, Headers, Param, Post } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { AuthService } from '../auth/auth.service';
import { RealtimeGateway } from '../realtime/realtime.gateway';
import { ChatService } from './chat.service';

@ApiTags('chat')
@ApiBearerAuth()
@Controller('rooms/:roomId/chat')
export class ChatController {
  constructor(
    private readonly auth: AuthService,
    private readonly chat: ChatService,
    private readonly realtime: RealtimeGateway,
  ) {}

  @Get()
  async history(
    @Param('roomId') roomId: string,
    @Headers('authorization') authorization?: string,
  ) {
    const identity = await this.auth.verifyBearer(authorization);
    return { messages: this.chat.history(identity.appId, roomId) };
  }

  @Post()
  async send(
    @Param('roomId') roomId: string,
    @Headers('authorization') authorization: string | undefined,
    @Body('text') text = '',
  ) {
    const identity = await this.auth.verifyBearer(authorization);
    const message = this.chat.send(roomId, identity, text);
    this.realtime.publish(identity.appId, roomId, 'chat.message', message);
    return message;
  }
}
