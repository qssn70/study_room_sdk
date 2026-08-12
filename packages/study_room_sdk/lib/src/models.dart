import 'dart:collection';

import 'errors.dart';
import 'generated_contract.dart' as wire;

typedef StudyRoomTokenProvider =
    Future<StudyRoomAccessToken> Function(StudyRoomTokenRequest request);

class StudyRoomTokenRequest {
  const StudyRoomTokenRequest({
    this.minimumValidity = Duration.zero,
    this.forceRefresh = false,
  });

  final Duration minimumValidity;
  final bool forceRefresh;
}

class StudyRoomAccessToken {
  const StudyRoomAccessToken({required this.token, required this.expiresAt});
  final String token;
  final DateTime expiresAt;
}

enum PresenceStatus { online, focusing, idle, away, offline }

enum RoomRole { owner, member }

enum JoinRequestStatus { pending, approved, rejected, cancelled }

enum StudySessionStatus { idle, running, paused, finished }

enum StudyRoomConnectionState {
  stopped,
  connecting,
  synchronizing,
  connected,
  degraded,
  refreshing,
  reconnecting,
  disconnected,
}

T _decodeWire<T>(
  Map<String, dynamic> json,
  T Function(Map<String, Object?>) decode,
  String model,
) {
  try {
    return decode(Map<String, Object?>.from(json));
  } catch (error) {
    throw StudyRoomException(
      'Invalid $model response payload',
      kind: StudyRoomExceptionKind.protocol,
      code: error is ArgumentError ? 'invalid_enum' : 'invalid_wire',
      cause: error,
    );
  }
}

Map<String, dynamic> jsonObject(Object? value, [String field = 'value']) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return Map<String, dynamic>.from(value);
  throw StudyRoomException(
    'Expected $field to be a JSON object',
    kind: StudyRoomExceptionKind.protocol,
    code: 'invalid_json',
  );
}

DateTime _date(Object? value, String field) {
  if (value is String) {
    final parsed = DateTime.tryParse(value);
    if (parsed != null) return parsed;
  }
  throw StudyRoomException(
    'Expected $field to be an ISO-8601 date',
    kind: StudyRoomExceptionKind.protocol,
    code: 'invalid_date',
  );
}

class StudyMember {
  const StudyMember({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.status,
    this.role = RoomRole.member,
  });
  final String id;
  final String displayName;
  final String avatarUrl;
  final PresenceStatus status;
  final RoomRole role;

  factory StudyMember.fromJson(Map<String, dynamic> json) =>
      StudyMember._fromWire(
        _decodeWire(json, wire.MemberWire.fromJson, 'member'),
      );

  StudyMember._fromWire(wire.MemberWire value)
    : id = value.id,
      displayName = value.displayName,
      avatarUrl = value.avatarUrl,
      status = PresenceStatus.values.byName(value.status.name),
      role = RoomRole.values.byName(value.role.name);

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'status': status.name,
    'role': role.name,
  };
}

class StudyRoom {
  StudyRoom({
    required this.id,
    required this.appId,
    required this.title,
    required this.version,
    required List<StudyMember> members,
  }) : members = List.unmodifiable(members);
  final String id;
  final String appId;
  final String title;
  final int version;
  final List<StudyMember> members;

  factory StudyRoom.fromJson(Map<String, dynamic> json) =>
      StudyRoom._fromWire(_decodeWire(json, wire.RoomWire.fromJson, 'room'));

  StudyRoom._fromWire(wire.RoomWire value)
    : id = value.id,
      appId = value.appId,
      title = value.title,
      version = value.version,
      members = List.unmodifiable(value.members.map(StudyMember._fromWire));
}

class RoomJoinRequest {
  const RoomJoinRequest({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
  });
  final String id;
  final String roomId;
  final String userId;
  final String displayName;
  final JoinRequestStatus status;
  final DateTime createdAt;
  final DateTime updatedAt;

  factory RoomJoinRequest.fromJson(Map<String, dynamic> json) {
    final value = _decodeWire(
      json,
      wire.JoinRequestWire.fromJson,
      'join request',
    );
    return RoomJoinRequest._fromWire(value);
  }

  factory RoomJoinRequest._fromWire(wire.JoinRequestWire value) =>
      RoomJoinRequest(
        id: value.id,
        roomId: value.roomId,
        userId: value.userId,
        displayName: value.displayName,
        status: JoinRequestStatus.values.byName(value.status.name),
        createdAt: _date(value.createdAt, 'createdAt'),
        updatedAt: _date(value.updatedAt, 'updatedAt'),
      );
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt,
  });
  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String text;
  final DateTime sentAt;

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    final value = _decodeWire(
      json,
      wire.ChatMessageWire.fromJson,
      'chat message',
    );
    return ChatMessage._fromWire(value);
  }

  factory ChatMessage._fromWire(wire.ChatMessageWire value) => ChatMessage(
    id: value.id,
    roomId: value.roomId,
    senderId: value.senderId,
    senderName: value.senderName,
    text: value.text,
    sentAt: _date(value.sentAt, 'sentAt'),
  );
}

class StudySessionState {
  const StudySessionState({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.status,
    required this.startedAt,
    required this.updatedAt,
    this.finishedAt,
  });
  const StudySessionState.idle(String roomId)
    : this(
        id: '',
        roomId: roomId,
        userId: '',
        status: StudySessionStatus.idle,
        startedAt: null,
        updatedAt: null,
      );
  final String id;
  final String roomId;
  final String userId;
  final StudySessionStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? updatedAt;

  factory StudySessionState.fromJson(Map<String, dynamic> json) {
    final value = _decodeWire(
      json,
      wire.StudySessionWire.fromJson,
      'study session',
    );
    return StudySessionState._fromWire(value);
  }

  factory StudySessionState._fromWire(wire.StudySessionWire value) =>
      StudySessionState(
        id: value.id,
        roomId: value.roomId,
        userId: value.userId,
        status: StudySessionStatus.values.byName(value.status.name),
        startedAt: _date(value.startedAt, 'startedAt'),
        finishedAt: value.finishedAt == null
            ? null
            : _date(value.finishedAt, 'finishedAt'),
        updatedAt: _date(value.updatedAt, 'updatedAt'),
      );
}

class StudyRoomPage<T> {
  StudyRoomPage({required List<T> items, required this.nextCursor})
    : items = List.unmodifiable(items);
  final List<T> items;
  final String? nextCursor;

  static StudyRoomPage<StudyRoom> roomsFromJson(Map<String, dynamic> json) {
    final page = _decodeWire(json, wire.RoomPageWire.fromJson, 'room page');
    return StudyRoomPage(
      items: page.items.map(StudyRoom._fromWire).toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }

  static StudyRoomPage<RoomJoinRequest> joinRequestsFromJson(
    Map<String, dynamic> json,
  ) {
    final page = _decodeWire(
      json,
      wire.JoinRequestPageWire.fromJson,
      'join-request page',
    );
    return StudyRoomPage(
      items: page.items.map(RoomJoinRequest._fromWire).toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }

  static StudyRoomPage<StudySessionState> sessionsFromJson(
    Map<String, dynamic> json,
  ) {
    final page = _decodeWire(
      json,
      wire.SessionPageWire.fromJson,
      'session page',
    );
    return StudyRoomPage(
      items: page.items
          .map(StudySessionState._fromWire)
          .toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }

  static StudyRoomPage<ChatMessage> messagesFromJson(
    Map<String, dynamic> json,
  ) {
    final page = _decodeWire(
      json,
      wire.MessagePageWire.fromJson,
      'message page',
    );
    return StudyRoomPage(
      items: page.items.map(ChatMessage._fromWire).toList(growable: false),
      nextCursor: page.nextCursor,
    );
  }
}

class StudyRoomSyncState {
  StudyRoomSyncState({
    Map<String, StudyRoom> rooms = const {},
    Map<String, List<StudySessionState>> activeSessionsByRoom = const {},
    Map<String, List<ChatMessage>> recentMessagesByRoom = const {},
    List<RoomJoinRequest> myJoinRequests = const [],
    Map<String, List<RoomJoinRequest>> ownerInboxByRoom = const {},
    Set<String> staleRoomIds = const {},
    this.personalDataStale = false,
    this.lastSyncedAt,
  }) : rooms = UnmodifiableMapView(Map<String, StudyRoom>.from(rooms)),
       activeSessionsByRoom = _immutableLists(activeSessionsByRoom),
       recentMessagesByRoom = _immutableLists(recentMessagesByRoom),
       myJoinRequests = List.unmodifiable(myJoinRequests),
       ownerInboxByRoom = _immutableLists(ownerInboxByRoom),
       staleRoomIds = Set.unmodifiable(staleRoomIds);

  factory StudyRoomSyncState.empty() => StudyRoomSyncState();

  final Map<String, StudyRoom> rooms;
  final Map<String, List<StudySessionState>> activeSessionsByRoom;
  final Map<String, List<ChatMessage>> recentMessagesByRoom;
  final List<RoomJoinRequest> myJoinRequests;
  final Map<String, List<RoomJoinRequest>> ownerInboxByRoom;
  final Set<String> staleRoomIds;
  final bool personalDataStale;
  final DateTime? lastSyncedAt;

  bool get isDegraded => staleRoomIds.isNotEmpty || personalDataStale;

  static Map<String, List<T>> _immutableLists<T>(Map<String, List<T>> source) =>
      UnmodifiableMapView(
        source.map((key, value) => MapEntry(key, List<T>.unmodifiable(value))),
      );
}

class StudyRoomRealtimeEvent {
  const StudyRoomRealtimeEvent({
    required this.schemaVersion,
    required this.eventId,
    required this.type,
    required this.occurredAt,
    required this.payload,
    this.roomId,
    this.roomVersion,
  });
  final int schemaVersion;
  final String eventId;
  final String type;
  final String? roomId;
  final int? roomVersion;
  final DateTime occurredAt;
  final Map<String, dynamic> payload;

  factory StudyRoomRealtimeEvent.fromJson(Map<String, dynamic> json) {
    final value = _decodeWire(
      json,
      wire.RealtimeEnvelopeWire.fromJson,
      'realtime event',
    );
    final encoded = value.toJson();
    return StudyRoomRealtimeEvent(
      schemaVersion: value.schemaVersion,
      eventId: value.eventId,
      type: value.type,
      roomId: value.roomId,
      roomVersion: value.roomVersion,
      occurredAt: _date(value.occurredAt, 'occurredAt'),
      payload: jsonObject(encoded['payload'], 'payload'),
    );
  }
}
