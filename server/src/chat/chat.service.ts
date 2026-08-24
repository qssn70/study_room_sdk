import { Injectable } from '@nestjs/common';
import { Prisma } from '@prisma/client';
import {
  IdempotencyService,
  IdempotentResult,
} from '../common/idempotency.service';
import { ChatMessageDto, ExternalIdentity } from '../domain';
import { PrismaService } from '../prisma/prisma.service';
import { RoomsService } from '../rooms/rooms.service';

@Injectable()
export class ChatService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly rooms: RoomsService,
    private readonly idempotency?: IdempotencyService,
  ) {}

  async send(roomId: string, identity: ExternalIdentity, text: string): Promise<ChatMessageDto> {
    await this.rooms.requireMember(roomId, identity);
    const normalized = text.trim();
    const message = await this.prisma.$transaction((tx) =>
      this.createMessage(tx, roomId, identity, normalized),
    );
    return this.toDto(message);
  }

  async sendIdempotent(
    roomId: string,
    identity: ExternalIdentity,
    text: string,
    idempotencyKey?: string,
  ): Promise<IdempotentResult<ChatMessageDto>> {
    if (idempotencyKey === undefined) {
      return { value: await this.send(roomId, identity, text), created: true };
    }
    await this.rooms.requireMember(roomId, identity);
    if (!this.idempotency) throw new Error('IdempotencyService is unavailable');
    const normalized = text.trim();
    return this.idempotency.execute({
      appId: identity.appId,
      userId: identity.userId,
      operation: 'chat.send',
      key: idempotencyKey,
      request: { roomId, text: normalized },
      create: async (tx, resourceId) => this.toDto(
        await this.createMessage(tx, roomId, identity, normalized, resourceId),
      ),
      replay: async (resourceId) => {
        const message = await this.prisma.chatMessage.findFirst({
          where: { id: resourceId, appId: identity.appId },
          include: { sender: true },
        });
        return message ? this.toDto(message) : undefined;
      },
    });
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

  private async createMessage(
    tx: Prisma.TransactionClient,
    roomId: string,
    identity: ExternalIdentity,
    text: string,
    id?: string,
  ) {
    const message = await tx.chatMessage.create({
      data: {
        ...(id === undefined ? {} : { id }),
        roomId,
        appId: identity.appId,
        senderId: identity.userId,
        text,
      },
      include: { sender: true },
    });
    await tx.auditLog.create({
      data: {
        appId: identity.appId,
        actorId: identity.userId,
        action: 'chat.message.created',
        resourceId: message.id,
        metadata: { roomId },
      },
    });
    return message;
  }

  private toDto(message: {
    id: string;
    roomId: string;
    senderId: string;
    text: string;
    sentAt: Date;
    sender: { displayName: string };
  }): ChatMessageDto {
    return {
      id: message.id,
      roomId: message.roomId,
      senderId: message.senderId,
      senderName: message.sender.displayName,
      text: message.text,
      sentAt: message.sentAt.toISOString(),
    };
  }
}
