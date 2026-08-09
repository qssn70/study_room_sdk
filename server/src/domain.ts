import type {
  ChatMessageWire,
  JoinRequestStatusWire,
  JoinRequestWire,
  MemberWire,
  PresenceStatusWire,
  RoomRoleWire,
  RoomWire,
  SessionStatusWire,
  StudySessionWire,
} from './generated/contract-types';

export type PresenceStatus = PresenceStatusWire;
export type RoomRole = RoomRoleWire;
export type JoinRequestStatus = JoinRequestStatusWire;
export type StudySessionStatus = SessionStatusWire;

export interface ExternalIdentity {
  userId: string;
  appId: string;
  displayName: string;
  avatarUrl: string;
  expiresAt: Date;
}

export interface AdminIdentity {
  subject: string;
  scopes: string[];
  expiresAt: Date;
}

export type StudyMemberDto = MemberWire;
export type StudyRoomDto = RoomWire;
export type JoinRequestDto = JoinRequestWire;
export type StudySessionDto = StudySessionWire;
export type ChatMessageDto = ChatMessageWire;
