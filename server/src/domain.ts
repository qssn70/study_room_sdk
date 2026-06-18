export type PresenceStatus = 'online' | 'focusing' | 'idle' | 'away' | 'offline';
export type StudySessionStatus = 'idle' | 'running' | 'paused' | 'finished';

export interface ExternalIdentity {
  userId: string;
  appId: string;
  displayName: string;
  avatarUrl: string;
}

export interface StudyMemberDto {
  id: string;
  displayName: string;
  avatarUrl: string;
  status: PresenceStatus;
}

export interface StudyRoomDto {
  id: string;
  appId: string;
  title: string;
  members: StudyMemberDto[];
}

export interface StudySessionDto {
  id: string;
  appId: string;
  roomId: string;
  userId: string;
  status: StudySessionStatus;
  startedAt: string;
  finishedAt?: string;
}

export interface ChatMessageDto {
  id: string;
  appId: string;
  roomId: string;
  senderId: string;
  senderName: string;
  text: string;
  sentAt: string;
}

