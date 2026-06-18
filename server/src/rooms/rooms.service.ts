import { Injectable } from '@nestjs/common';
import { ExternalIdentity, StudyMemberDto, StudyRoomDto } from '../domain';

@Injectable()
export class RoomsService {
  private readonly rooms = new Map<string, StudyRoomDto>();

  async joinRoom(roomId: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    const room = this.ensureRoom(roomId, identity.appId);
    const member: StudyMemberDto = {
      id: identity.userId,
      displayName: identity.displayName,
      avatarUrl: identity.avatarUrl,
      status: 'online',
    };
    const index = room.members.findIndex((candidate) => candidate.id === member.id);
    if (index >= 0) {
      room.members[index] = member;
    } else {
      room.members.push(member);
    }
    return this.clone(room);
  }

  async leaveRoom(roomId: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    const room = this.ensureRoom(roomId, identity.appId);
    room.members = room.members.filter((member) => member.id !== identity.userId);
    return this.clone(room);
  }

  async getRoom(roomId: string, appId: string): Promise<StudyRoomDto> {
    return this.clone(this.ensureRoom(roomId, appId));
  }

  private ensureRoom(roomId: string, appId: string): StudyRoomDto {
    const key = this.key(appId, roomId);
    const existing = this.rooms.get(key);
    if (existing) {
      return existing;
    }
    const created: StudyRoomDto = {
      id: roomId,
      appId,
      title: `Room ${roomId}`,
      members: [],
    };
    this.rooms.set(key, created);
    return created;
  }

  private key(appId: string, roomId: string): string {
    return `${appId}:${roomId}`;
  }

  private clone(room: StudyRoomDto): StudyRoomDto {
    return {
      ...room,
      members: room.members.map((member) => ({ ...member })),
    };
  }
}

