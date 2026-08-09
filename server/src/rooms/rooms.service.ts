import { ForbiddenException, Injectable } from '@nestjs/common';
import {
  ExternalIdentity,
  PresenceStatus,
  StudyMemberDto,
  StudyRoomDto,
} from '../domain';

@Injectable()
export class RoomsService {
  private readonly roomsByApp = new Map<string, Map<string, StudyRoomDto>>();
  private readonly connectionsByApp = new Map<
    string,
    Map<string, Map<string, Map<string, PresenceStatus>>>
  >();

  async joinRoom(roomId: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    const room = this.ensureRoom(roomId, identity.appId);
    const existingConnections = this.connectionsByApp
      .get(identity.appId)
      ?.get(roomId)
      ?.get(identity.userId);
    const member: StudyMemberDto = {
      id: identity.userId,
      displayName: identity.displayName,
      avatarUrl: identity.avatarUrl,
      status: 'offline',
    };
    const index = room.members.findIndex((candidate) => candidate.id === member.id);
    if (index >= 0) {
      room.members[index] = {
        ...member,
        status: room.members[index].status,
      };
    } else {
      room.members.push(member);
    }
    if (existingConnections) {
      this.applyEffectivePresence(room, identity.userId, existingConnections);
    }
    return this.clone(room);
  }

  async leaveRoom(roomId: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    const room = this.requireMember(roomId, identity);
    room.members = room.members.filter((member) => member.id !== identity.userId);
    this.connectionsByApp.get(identity.appId)?.get(roomId)?.delete(identity.userId);
    return this.clone(room);
  }

  async getRoom(roomId: string, identity: ExternalIdentity): Promise<StudyRoomDto> {
    return this.clone(this.requireMember(roomId, identity));
  }

  requireMember(roomId: string, identity: ExternalIdentity): StudyRoomDto {
    const room = this.roomsByApp.get(identity.appId)?.get(roomId);
    const member = room?.members.some((candidate) => candidate.id === identity.userId);
    if (!room || !member) {
      throw new ForbiddenException('Room membership is required');
    }
    return room;
  }

  roomSnapshot(appId: string, roomId: string): StudyRoomDto | undefined {
    const room = this.roomsByApp.get(appId)?.get(roomId);
    return room ? this.clone(room) : undefined;
  }

  registerConnection(
    roomId: string,
    identity: ExternalIdentity,
    socketId: string,
  ): StudyRoomDto {
    const room = this.requireMember(roomId, identity);
    const connections = this.userConnections(identity.appId, roomId, identity.userId);
    if (connections.has(socketId)) {
      return this.clone(room);
    }
    const member = this.member(room, identity.userId);
    const initialStatus =
      member.status === 'focusing' || member.status === 'idle'
        ? member.status
        : 'online';
    connections.set(socketId, initialStatus);
    this.applyEffectivePresence(room, identity.userId, connections);
    return this.clone(room);
  }

  unregisterConnection(
    roomId: string,
    identity: ExternalIdentity,
    socketId: string,
  ): StudyRoomDto | undefined {
    const room = this.roomsByApp.get(identity.appId)?.get(roomId);
    const connections = this.connectionsByApp
      .get(identity.appId)
      ?.get(roomId)
      ?.get(identity.userId);
    if (!room || !connections || !room.members.some((member) => member.id === identity.userId)) {
      return undefined;
    }
    connections.delete(socketId);
    this.applyEffectivePresence(room, identity.userId, connections);
    return this.clone(room);
  }

  updateConnectionPresence(
    roomId: string,
    identity: ExternalIdentity,
    socketId: string,
    status: Exclude<PresenceStatus, 'offline'>,
  ): StudyRoomDto {
    const room = this.requireMember(roomId, identity);
    const connections = this.connectionsByApp
      .get(identity.appId)
      ?.get(roomId)
      ?.get(identity.userId);
    if (!connections?.has(socketId)) {
      throw new ForbiddenException('Realtime room subscription is required');
    }
    connections.set(socketId, status);
    this.applyEffectivePresence(room, identity.userId, connections);
    return this.clone(room);
  }

  setMemberPresenceIfPresent(
    appId: string,
    roomId: string,
    userId: string,
    status: 'focusing' | 'idle',
  ): StudyRoomDto | undefined {
    const room = this.roomsByApp.get(appId)?.get(roomId);
    const member = room?.members.find((candidate) => candidate.id === userId);
    if (!room || !member) {
      return undefined;
    }
    const connections = this.connectionsByApp.get(appId)?.get(roomId)?.get(userId);
    if (connections?.size) {
      for (const [socketId, current] of connections) {
        if (current !== 'away') {
          connections.set(socketId, status);
        }
      }
      this.applyEffectivePresence(room, userId, connections);
    } else if (member.status !== 'offline') {
      member.status = status;
    }
    return this.clone(room);
  }

  private ensureRoom(roomId: string, appId: string): StudyRoomDto {
    let appRooms = this.roomsByApp.get(appId);
    if (!appRooms) {
      appRooms = new Map<string, StudyRoomDto>();
      this.roomsByApp.set(appId, appRooms);
    }
    const existing = appRooms.get(roomId);
    if (existing) {
      return existing;
    }
    const created: StudyRoomDto = {
      id: roomId,
      appId,
      title: `Room ${roomId}`,
      members: [],
    };
    appRooms.set(roomId, created);
    return created;
  }

  private userConnections(
    appId: string,
    roomId: string,
    userId: string,
  ): Map<string, PresenceStatus> {
    let appConnections = this.connectionsByApp.get(appId);
    if (!appConnections) {
      appConnections = new Map();
      this.connectionsByApp.set(appId, appConnections);
    }
    let roomConnections = appConnections.get(roomId);
    if (!roomConnections) {
      roomConnections = new Map();
      appConnections.set(roomId, roomConnections);
    }
    let userConnections = roomConnections.get(userId);
    if (!userConnections) {
      userConnections = new Map();
      roomConnections.set(userId, userConnections);
    }
    return userConnections;
  }

  private applyEffectivePresence(
    room: StudyRoomDto,
    userId: string,
    connections: Map<string, PresenceStatus>,
  ) {
    const member = this.member(room, userId);
    const statuses = [...connections.values()];
    member.status = statuses.length === 0
      ? 'offline'
      : statuses.every((status) => status === 'away')
        ? 'away'
        : statuses.includes('focusing')
          ? 'focusing'
          : statuses.includes('idle')
            ? 'idle'
            : 'online';
  }

  private member(room: StudyRoomDto, userId: string): StudyMemberDto {
    const member = room.members.find((candidate) => candidate.id === userId);
    if (!member) {
      throw new ForbiddenException('Room membership is required');
    }
    return member;
  }

  private clone(room: StudyRoomDto): StudyRoomDto {
    return {
      ...room,
      members: room.members.map((member) => ({ ...member })),
    };
  }
}

