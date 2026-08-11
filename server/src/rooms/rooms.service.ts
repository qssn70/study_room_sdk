import {
  ConflictException,
  ForbiddenException,
  Injectable,
  NotFoundException,
} from '@nestjs/common';
import { JoinRequestStatus, Prisma, RoomRole } from '@prisma/client';
import { ExternalIdentity, JoinRequestDto, StudyRoomDto } from '../domain';
import { toRoomWire } from '../generated/contract-types';
import { PrismaService } from '../prisma/prisma.service';
import { PresenceService } from '../realtime/presence.service';

const roomInclude = {
  memberships: { include: { user: true }, orderBy: { joinedAt: 'asc' as const } },
} satisfies Prisma.RoomInclude;

type RoomWithMembers = Prisma.RoomGetPayload<{ include: typeof roomInclude }>;
type RequestWithUser = Prisma.JoinRequestGetPayload<{ include: { user: true } }>;

@Injectable()
export class RoomsService {
  constructor(private readonly prisma: PrismaService, private readonly presence: PresenceService) {}

  async create(title: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    const normalized = title.trim();
    const room = await this.prisma.$transaction(async (tx) => {
      const created = await tx.room.create({
        data: {
          appId: identity.appId,
          title: normalized,
          memberships: {
            create: {
              role: RoomRole.OWNER,
              user: {
                connect: {
                  appId_userId: { appId: identity.appId, userId: identity.userId },
                },
              },
            },
          },
        },
        include: roomInclude,
      });
      await tx.auditLog.create({
        data: {
          appId: identity.appId,
          actorId: identity.userId,
          action: 'room.created',
          resourceId: created.id,
        },
      });
      return created;
    });
    return this.toRoomDto(room);
  }

  async list(identity: ExternalIdentity, cursor?: string, limit = 50) {
    const take = Math.min(Math.max(limit, 1), 100);
    const rooms = await this.prisma.room.findMany({
      where: {
        appId: identity.appId,
        deletedAt: null,
        memberships: { some: { userId: identity.userId } },
      },
      include: roomInclude,
      orderBy: { id: 'asc' },
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      take: take + 1,
    });
    const hasMore = rooms.length > take;
    if (hasMore) rooms.pop();
    return {
      items: await Promise.all(rooms.map((room) => this.toRoomDto(room))),
      nextCursor: hasMore ? rooms.at(-1)?.id ?? null : null,
    };
  }

  async get(roomId: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    const room = await this.memberRoom(roomId, identity);
    return this.toRoomDto(room);
  }

  async snapshot(appId: string, roomId: string): Promise<StudyRoomDto | undefined> {
    const room = await this.prisma.room.findFirst({
      where: { id: roomId, appId, deletedAt: null },
      include: roomInclude,
    });
    return room ? this.toRoomDto(room) : undefined;
  }

  async isMember(roomId: string, identity: ExternalIdentity): Promise<boolean> {
    return (await this.prisma.roomMembership.count({
      where: { roomId, appId: identity.appId, userId: identity.userId, room: { deletedAt: null } },
    })) > 0;
  }

  async ownerUserId(roomId: string, appId: string): Promise<string> {
    const owner = await this.prisma.roomMembership.findFirst({
      where: { roomId, appId, role: 'OWNER', room: { deletedAt: null } },
      select: { userId: true },
    });
    if (!owner) throw new NotFoundException('Room owner not found');
    return owner.userId;
  }

  async requestJoin(
    roomId: string,
    identity: ExternalIdentity,
  ): Promise<{ request: JoinRequestDto; created: boolean }> {
    const room = await this.prisma.room.findFirst({
      where: { id: roomId, appId: identity.appId, deletedAt: null },
      select: { id: true },
    });
    if (!room) throw new NotFoundException('Room not found');
    if (await this.isMember(roomId, identity)) throw new ConflictException('Already a room member');
    const existing = await this.prisma.joinRequest.findFirst({
      where: { roomId, appId: identity.appId, userId: identity.userId, status: 'PENDING' },
      include: { user: true },
    });
    if (existing) return { request: this.toJoinRequestDto(existing), created: false };
    try {
      const request = await this.prisma.joinRequest.create({
        data: { roomId, appId: identity.appId, userId: identity.userId },
        include: { user: true },
      });
      return { request: this.toJoinRequestDto(request), created: true };
    } catch (error) {
      if (error instanceof Prisma.PrismaClientKnownRequestError && error.code === 'P2002') {
        const concurrent = await this.prisma.joinRequest.findFirst({
          where: { roomId, appId: identity.appId, userId: identity.userId, status: 'PENDING' },
          include: { user: true },
        });
        if (concurrent) {
          return { request: this.toJoinRequestDto(concurrent), created: false };
        }
      }
      throw error;
    }
  }

  async listMyJoinRequests(identity: ExternalIdentity, cursor?: string, limit = 50) {
    const take = Math.min(Math.max(limit, 1), 100);
    const items = await this.prisma.joinRequest.findMany({
      where: { appId: identity.appId, userId: identity.userId },
      include: { user: true },
      orderBy: [{ createdAt: 'desc' }, { id: 'desc' }],
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      take: take + 1,
    });
    const hasMore = items.length > take;
    if (hasMore) items.pop();
    return {
      items: items.map((item) => this.toJoinRequestDto(item)),
      nextCursor: hasMore ? items.at(-1)?.id ?? null : null,
    };
  }

  async listRoomJoinRequests(roomId: string, identity: ExternalIdentity, cursor?: string, limit = 50) {
    await this.requireOwner(roomId, identity);
    const take = Math.min(Math.max(limit, 1), 100);
    const items = await this.prisma.joinRequest.findMany({
      where: { roomId, appId: identity.appId, status: 'PENDING' },
      include: { user: true },
      orderBy: [{ createdAt: 'asc' }, { id: 'asc' }],
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
      take: take + 1,
    });
    const hasMore = items.length > take;
    if (hasMore) items.pop();
    return {
      items: items.map((item) => this.toJoinRequestDto(item)),
      nextCursor: hasMore ? items.at(-1)?.id ?? null : null,
    };
  }

  async cancelJoinRequest(roomId: string, identity: ExternalIdentity) {
    const request = await this.prisma.joinRequest.findFirst({
      where: { roomId, appId: identity.appId, userId: identity.userId, status: 'PENDING' },
    });
    if (!request) throw new NotFoundException('Pending join request not found');
    await this.prisma.joinRequest.update({
      where: { id: request.id },
      data: { status: 'CANCELLED' },
    });
  }

  async decideJoinRequest(
    roomId: string,
    requestId: string,
    decision: 'approved' | 'rejected',
    identity: ExternalIdentity,
  ) {
    await this.requireOwner(roomId, identity);
    const status: JoinRequestStatus = decision === 'approved' ? 'APPROVED' : 'REJECTED';
    const result = await this.prisma.$transaction(async (tx) => {
      const request = await tx.joinRequest.findFirst({
        where: { id: requestId, roomId, appId: identity.appId, status: 'PENDING' },
        include: { user: true },
      });
      if (!request) throw new NotFoundException('Pending join request not found');
      const updated = await tx.joinRequest.update({
        where: { id: request.id },
        data: { status, decidedBy: identity.userId },
        include: { user: true },
      });
      let roomVersion: number | null = null;
      if (status === 'APPROVED') {
        await tx.roomMembership.upsert({
          where: { roomId_userId: { roomId, userId: request.userId } },
          create: { roomId, appId: identity.appId, userId: request.userId, role: 'MEMBER' },
          update: {},
        });
        roomVersion = (await tx.room.update({
          where: { id: roomId },
          data: { version: { increment: 1 } },
        })).version;
      }
      await tx.auditLog.create({
        data: {
          appId: identity.appId,
          actorId: identity.userId,
          action: `join-request.${decision}`,
          resourceId: request.id,
          metadata: { roomId, userId: request.userId },
        },
      });
      return { request: updated, roomVersion };
    });
    return { request: this.toJoinRequestDto(result.request), roomVersion: result.roomVersion };
  }

  async removeMember(roomId: string, userId: string, identity: ExternalIdentity) {
    await this.requireOwner(roomId, identity);
    const target = await this.prisma.roomMembership.findUnique({
      where: { roomId_userId: { roomId, userId } },
    });
    if (!target) throw new NotFoundException('Room member not found');
    if (target.role === 'OWNER') throw new ConflictException('Transfer ownership before removing the owner');
    await this.prisma.$transaction([
      this.prisma.roomMembership.delete({ where: { roomId_userId: { roomId, userId } } }),
      this.prisma.room.update({ where: { id: roomId }, data: { version: { increment: 1 } } }),
      this.prisma.auditLog.create({
        data: {
          appId: identity.appId,
          actorId: identity.userId,
          action: 'member.removed',
          resourceId: userId,
          metadata: { roomId },
        },
      }),
    ]);
    await this.presence.removeUser(identity.appId, roomId, userId);
    const updated = await this.snapshot(identity.appId, roomId);
    if (!updated) throw new NotFoundException('Room not found');
    return updated;
  }

  async leave(roomId: string, identity: ExternalIdentity) {
    const membership = await this.requireMember(roomId, identity);
    if (membership.role === 'OWNER') {
      throw new ConflictException('Transfer ownership or delete the room before leaving');
    }
    await this.prisma.$transaction([
      this.prisma.roomMembership.delete({
        where: { roomId_userId: { roomId, userId: identity.userId } },
      }),
      this.prisma.room.update({ where: { id: roomId }, data: { version: { increment: 1 } } }),
    ]);
    await this.presence.removeUser(identity.appId, roomId, identity.userId);
    const updated = await this.snapshot(identity.appId, roomId);
    if (!updated) throw new NotFoundException('Room not found');
    return updated;
  }

  async transferOwnership(roomId: string, userId: string, identity: ExternalIdentity) {
    await this.requireOwner(roomId, identity);
    if (userId === identity.userId) return this.get(roomId, identity);
    const target = await this.prisma.roomMembership.findUnique({
      where: { roomId_userId: { roomId, userId } },
    });
    if (!target) throw new NotFoundException('Target owner must already be a room member');
    await this.prisma.$transaction(async (tx) => {
      await tx.roomMembership.update({
        where: { roomId_userId: { roomId, userId: identity.userId } },
        data: { role: 'MEMBER' },
      });
      await tx.roomMembership.update({
        where: { roomId_userId: { roomId, userId } },
        data: { role: 'OWNER' },
      });
      await tx.room.update({ where: { id: roomId }, data: { version: { increment: 1 } } });
      await tx.auditLog.create({
        data: {
          appId: identity.appId,
          actorId: identity.userId,
          action: 'room.owner-transferred',
          resourceId: roomId,
          metadata: { newOwnerId: userId },
        },
      });
    });
    const updated = await this.snapshot(identity.appId, roomId);
    if (!updated) throw new NotFoundException('Room not found');
    return updated;
  }

  async delete(roomId: string, identity: ExternalIdentity) {
    await this.requireOwner(roomId, identity);
    const members = await this.prisma.roomMembership.findMany({
      where: { roomId },
      select: { userId: true },
    });
    const [deleted] = await this.prisma.$transaction([
      this.prisma.room.update({
        where: { id: roomId },
        data: { deletedAt: new Date(), version: { increment: 1 } },
      }),
      this.prisma.auditLog.create({
        data: { appId: identity.appId, actorId: identity.userId, action: 'room.deleted', resourceId: roomId },
      }),
    ]);
    await Promise.all(members.map((member) => this.presence.removeUser(identity.appId, roomId, member.userId)));
    return { userIds: members.map((member) => member.userId), roomVersion: deleted.version };
  }

  async requireMember(roomId: string, identity: ExternalIdentity) {
    const membership = await this.prisma.roomMembership.findFirst({
      where: { roomId, appId: identity.appId, userId: identity.userId, room: { deletedAt: null } },
    });
    if (!membership) throw new ForbiddenException('Room membership is required');
    return membership;
  }

  private async requireOwner(roomId: string, identity: ExternalIdentity) {
    const membership = await this.requireMember(roomId, identity);
    if (membership.role !== 'OWNER') throw new ForbiddenException('Room owner permission is required');
    return membership;
  }

  private async memberRoom(roomId: string, identity: ExternalIdentity): Promise<RoomWithMembers> {
    const room = await this.prisma.room.findFirst({
      where: {
        id: roomId,
        appId: identity.appId,
        deletedAt: null,
        memberships: { some: { userId: identity.userId } },
      },
      include: roomInclude,
    });
    if (!room) throw new ForbiddenException('Room membership is required');
    return room;
  }

  private async toRoomDto(room: RoomWithMembers): Promise<StudyRoomDto> {
    const statuses = await this.presence.statusesFor(
      room.appId,
      room.id,
      room.memberships.map((membership) => membership.userId),
    );
    return toRoomWire({
      id: room.id,
      appId: room.appId,
      title: room.title,
      version: room.version,
      members: room.memberships.map((membership) => ({
        id: membership.userId,
        displayName: membership.user.displayName,
        avatarUrl: membership.user.avatarUrl,
        role: membership.role.toLowerCase() as 'owner' | 'member',
        status: statuses.get(membership.userId) ?? 'offline',
      })),
    });
  }

  private toJoinRequestDto(request: RequestWithUser): JoinRequestDto {
    return {
      id: request.id,
      roomId: request.roomId,
      userId: request.userId,
      displayName: request.user.displayName,
      status: request.status.toLowerCase() as JoinRequestDto['status'],
      createdAt: request.createdAt.toISOString(),
      updatedAt: request.updatedAt.toISOString(),
    };
  }
}
