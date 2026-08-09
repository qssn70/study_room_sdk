import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { ChatMessageDto, ExternalIdentity } from '../domain';
import { RoomsService } from '../rooms/rooms.service';

@Injectable()
export class ChatService {
  private readonly messagesByApp = new Map<string, Map<string, ChatMessageDto[]>>();

  constructor(private readonly rooms: RoomsService) {}

  send(roomId: string, identity: ExternalIdentity, text: string): ChatMessageDto {
    this.rooms.requireMember(roomId, identity);
    const trimmed = text.trim();
    if (trimmed.length === 0) {
      throw new BadRequestException('Message text is required');
    }

    const message: ChatMessageDto = {
      id: randomUUID(),
      appId: identity.appId,
      roomId,
      senderId: identity.userId,
      senderName: identity.displayName,
      text: trimmed,
      sentAt: new Date().toISOString(),
    };
    const messages = this.appMessages(identity.appId);
    messages.set(roomId, [...(messages.get(roomId) ?? []), message]);
    return { ...message };
  }

  history(roomId: string, identity: ExternalIdentity): ChatMessageDto[] {
    this.rooms.requireMember(roomId, identity);
    return [...(this.messagesByApp.get(identity.appId)?.get(roomId) ?? [])];
  }

  private appMessages(appId: string): Map<string, ChatMessageDto[]> {
    let messages = this.messagesByApp.get(appId);
    if (!messages) {
      messages = new Map<string, ChatMessageDto[]>();
      this.messagesByApp.set(appId, messages);
    }
    return messages;
  }
}

