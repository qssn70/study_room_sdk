import { BadRequestException, Injectable } from '@nestjs/common';
import { randomUUID } from 'crypto';
import { ChatMessageDto, ExternalIdentity } from '../domain';

@Injectable()
export class ChatService {
  private readonly messages = new Map<string, ChatMessageDto[]>();

  send(roomId: string, identity: ExternalIdentity, text: string): ChatMessageDto {
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
    const key = this.key(identity.appId, roomId);
    this.messages.set(key, [...(this.messages.get(key) ?? []), message]);
    return { ...message };
  }

  history(appId: string, roomId: string): ChatMessageDto[] {
    return [...(this.messages.get(this.key(appId, roomId)) ?? [])];
  }

  private key(appId: string, roomId: string): string {
    return `${appId}:${roomId}`;
  }
}

