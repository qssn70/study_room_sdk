import { Injectable } from '@nestjs/common';
import { ChatMessageDto, ExternalIdentity } from '../domain';
import { PrismaService } from '../prisma/prisma.service';
import { RoomsService } from '../rooms/rooms.service';

@Injectable()
export class ChatService {
  constructor(private readonly prisma: PrismaService, private readonly rooms: RoomsService) {}

  async send(roomId: string, identity: ExternalIdentity, text: string): Promise<ChatMessageDto> {
    await this.rooms.requireMember(roomId, identity);
    const message = await this.prisma.chatMessage.create({
      data: { roomId, appId: identity.appId, senderId: identity.userId, text: text.trim() },
      include: { sender: true },
    });
    return {
      id: message.id,
      roomId: message.roomId,
      senderId: message.senderId,
      senderName: message.sender.displayName,
      text: message.text,
      sentAt: message.sentAt.toISOString(),
    };
  }

  async history(roomId: string, identity: ExternalIdentity, cursor?: string, limit = 50) {
    await this.rooms.requireMember(roomId, identity);
    const take = Math.min(Math.max(limit, 1), 100);
    const messages = await this.prisma.chatMessage.findMany({
      where: { roomId, appId: identity.appId },
      include: { sender: true },
      orderBy: [{ sentAt: 'desc' }, { id: 'desc' }],
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      take: take + 1,
    });
    const hasMore = messages.length > take;
    if (hasMore) messages.pop();
    const nextCursor = hasMore ? messages.at(-1)?.id ?? null : null;
    return {
      items: messages.reverse().map((message) => ({
        id: message.id,
        roomId: message.roomId,
        senderId: message.senderId,
        senderName: message.sender.displayName,
        text: message.text,
        sentAt: message.sentAt.toISOString(),
      })),
      nextCursor,
    };
  }
}
