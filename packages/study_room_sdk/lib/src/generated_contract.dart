// coverage:ignore-file
// GENERATED FILE. Run npm run generate:contracts; do not edit.
const studyRoomContractVersion = "0.4.0-beta.1";
const studyRoomRealtimeSchemaVersion = 1;
const studyRoomRealtimeEventTypes = <String>{
  "room.state",
  "membership.updated",
  "join-request.created",
  "join-request.updated",
  "member.presence.updated",
  "chat.message.created",
  "session.updated",
};

Map<String, Object?> _wireObject(Object? value) => Map<String, Object?>.from(value! as Map);

typedef AppIdWire = String;

enum PresenceStatusWire { online, focusing, idle, away, offline }

enum RoomRoleWire { owner, member }

enum JoinRequestStatusWire { pending, approved, rejected, cancelled }

enum JoinRequestDecisionWire { approved, rejected }

enum SessionStatusWire { running, paused, finished }

final class ApplicationWire {
  ApplicationWire({
    required this.appId,
    required this.issuer,
    required this.audience,
    required this.jwksUri,
    required this.enabled,
    required this.chatRetentionDays,
    required this.sessionRetentionDays,
    required this.createdAt,
    required this.updatedAt
  });

  final AppIdWire appId;
  final String issuer;
  final String audience;
  final String jwksUri;
  final bool enabled;
  final int? chatRetentionDays;
  final int? sessionRetentionDays;
  final String createdAt;
  final String updatedAt;

  factory ApplicationWire.fromJson(Map<String, Object?> json) => ApplicationWire(
      appId: json["appId"] as AppIdWire,
      issuer: json["issuer"] as String,
      audience: json["audience"] as String,
      jwksUri: json["jwksUri"] as String,
      enabled: json["enabled"] as bool,
      chatRetentionDays: json["chatRetentionDays"] == null ? null : json["chatRetentionDays"] as int,
      sessionRetentionDays: json["sessionRetentionDays"] == null ? null : json["sessionRetentionDays"] as int,
      createdAt: json["createdAt"] as String,
      updatedAt: json["updatedAt"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "appId": appId,
      "issuer": issuer,
      "audience": audience,
      "jwksUri": jwksUri,
      "enabled": enabled,
      "chatRetentionDays": chatRetentionDays,
      "sessionRetentionDays": sessionRetentionDays,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
    };
}

final class CreateApplicationRequestWire {
  CreateApplicationRequestWire({
    required this.appId,
    required this.issuer,
    required this.audience,
    required this.jwksUri,
    this.enabled,
    this.chatRetentionDays,
    this.sessionRetentionDays
  });

  final AppIdWire appId;
  final String issuer;
  final String audience;
  final String jwksUri;
  final bool? enabled;
  final int? chatRetentionDays;
  final int? sessionRetentionDays;

  factory CreateApplicationRequestWire.fromJson(Map<String, Object?> json) => CreateApplicationRequestWire(
      appId: json["appId"] as AppIdWire,
      issuer: json["issuer"] as String,
      audience: json["audience"] as String,
      jwksUri: json["jwksUri"] as String,
      enabled: json["enabled"] == null ? null : json["enabled"] as bool,
      chatRetentionDays: json["chatRetentionDays"] == null ? null : json["chatRetentionDays"] as int,
      sessionRetentionDays: json["sessionRetentionDays"] == null ? null : json["sessionRetentionDays"] as int,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "appId": appId,
      "issuer": issuer,
      "audience": audience,
      "jwksUri": jwksUri,
      if (enabled != null) "enabled": enabled,
      if (chatRetentionDays != null) "chatRetentionDays": chatRetentionDays,
      if (sessionRetentionDays != null) "sessionRetentionDays": sessionRetentionDays,
    };
}

final class UpdateApplicationRequestWire {
  UpdateApplicationRequestWire({
    this.issuer,
    this.audience,
    this.jwksUri,
    this.enabled,
    this.chatRetentionDays,
    this.sessionRetentionDays
  });

  final String? issuer;
  final String? audience;
  final String? jwksUri;
  final bool? enabled;
  final int? chatRetentionDays;
  final int? sessionRetentionDays;

  factory UpdateApplicationRequestWire.fromJson(Map<String, Object?> json) => UpdateApplicationRequestWire(
      issuer: json["issuer"] == null ? null : json["issuer"] as String,
      audience: json["audience"] == null ? null : json["audience"] as String,
      jwksUri: json["jwksUri"] == null ? null : json["jwksUri"] as String,
      enabled: json["enabled"] == null ? null : json["enabled"] as bool,
      chatRetentionDays: json["chatRetentionDays"] == null ? null : json["chatRetentionDays"] as int,
      sessionRetentionDays: json["sessionRetentionDays"] == null ? null : json["sessionRetentionDays"] as int,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      if (issuer != null) "issuer": issuer,
      if (audience != null) "audience": audience,
      if (jwksUri != null) "jwksUri": jwksUri,
      if (enabled != null) "enabled": enabled,
      if (chatRetentionDays != null) "chatRetentionDays": chatRetentionDays,
      if (sessionRetentionDays != null) "sessionRetentionDays": sessionRetentionDays,
    };
}

final class ApplicationPageWire {
  ApplicationPageWire({
    required List<ApplicationWire> items,
    required this.nextCursor
  }) : items = List.unmodifiable(items);

  final List<ApplicationWire> items;
  final String? nextCursor;

  factory ApplicationPageWire.fromJson(Map<String, Object?> json) => ApplicationPageWire(
      items: List<ApplicationWire>.unmodifiable((json["items"] as List<Object?>).map((value) => ApplicationWire.fromJson(_wireObject(value)))),
      nextCursor: json["nextCursor"] == null ? null : json["nextCursor"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "items": items.map((value) => value.toJson()).toList(growable: false),
      "nextCursor": nextCursor,
    };
}

final class MemberWire {
  MemberWire({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.role,
    required this.status
  });

  final String id;
  final String displayName;
  final String avatarUrl;
  final RoomRoleWire role;
  final PresenceStatusWire status;

  factory MemberWire.fromJson(Map<String, Object?> json) => MemberWire(
      id: json["id"] as String,
      displayName: json["displayName"] as String,
      avatarUrl: json["avatarUrl"] as String,
      role: RoomRoleWire.values.byName(json["role"] as String),
      status: PresenceStatusWire.values.byName(json["status"] as String),
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "id": id,
      "displayName": displayName,
      "avatarUrl": avatarUrl,
      "role": role.name,
      "status": status.name,
    };
}

final class RoomWire {
  RoomWire({
    required this.id,
    required this.appId,
    required this.title,
    required this.version,
    required List<MemberWire> members
  }) : members = List.unmodifiable(members);

  final String id;
  final AppIdWire appId;
  final String title;
  final int version;
  final List<MemberWire> members;

  factory RoomWire.fromJson(Map<String, Object?> json) => RoomWire(
      id: json["id"] as String,
      appId: json["appId"] as AppIdWire,
      title: json["title"] as String,
      version: json["version"] as int,
      members: List<MemberWire>.unmodifiable((json["members"] as List<Object?>).map((value) => MemberWire.fromJson(_wireObject(value)))),
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "id": id,
      "appId": appId,
      "title": title,
      "version": version,
      "members": members.map((value) => value.toJson()).toList(growable: false),
    };
}

final class RoomPageWire {
  RoomPageWire({
    required List<RoomWire> items,
    required this.nextCursor
  }) : items = List.unmodifiable(items);

  final List<RoomWire> items;
  final String? nextCursor;

  factory RoomPageWire.fromJson(Map<String, Object?> json) => RoomPageWire(
      items: List<RoomWire>.unmodifiable((json["items"] as List<Object?>).map((value) => RoomWire.fromJson(_wireObject(value)))),
      nextCursor: json["nextCursor"] == null ? null : json["nextCursor"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "items": items.map((value) => value.toJson()).toList(growable: false),
      "nextCursor": nextCursor,
    };
}

final class JoinRequestWire {
  JoinRequestWire({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.displayName,
    required this.status,
    required this.createdAt,
    required this.updatedAt
  });

  final String id;
  final String roomId;
  final String userId;
  final String displayName;
  final JoinRequestStatusWire status;
  final String createdAt;
  final String updatedAt;

  factory JoinRequestWire.fromJson(Map<String, Object?> json) => JoinRequestWire(
      id: json["id"] as String,
      roomId: json["roomId"] as String,
      userId: json["userId"] as String,
      displayName: json["displayName"] as String,
      status: JoinRequestStatusWire.values.byName(json["status"] as String),
      createdAt: json["createdAt"] as String,
      updatedAt: json["updatedAt"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "id": id,
      "roomId": roomId,
      "userId": userId,
      "displayName": displayName,
      "status": status.name,
      "createdAt": createdAt,
      "updatedAt": updatedAt,
    };
}

final class JoinRequestPageWire {
  JoinRequestPageWire({
    required List<JoinRequestWire> items,
    required this.nextCursor
  }) : items = List.unmodifiable(items);

  final List<JoinRequestWire> items;
  final String? nextCursor;

  factory JoinRequestPageWire.fromJson(Map<String, Object?> json) => JoinRequestPageWire(
      items: List<JoinRequestWire>.unmodifiable((json["items"] as List<Object?>).map((value) => JoinRequestWire.fromJson(_wireObject(value)))),
      nextCursor: json["nextCursor"] == null ? null : json["nextCursor"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "items": items.map((value) => value.toJson()).toList(growable: false),
      "nextCursor": nextCursor,
    };
}

final class ChatMessageWire {
  ChatMessageWire({
    required this.id,
    required this.roomId,
    required this.senderId,
    required this.senderName,
    required this.text,
    required this.sentAt
  });

  final String id;
  final String roomId;
  final String senderId;
  final String senderName;
  final String text;
  final String sentAt;

  factory ChatMessageWire.fromJson(Map<String, Object?> json) => ChatMessageWire(
      id: json["id"] as String,
      roomId: json["roomId"] as String,
      senderId: json["senderId"] as String,
      senderName: json["senderName"] as String,
      text: json["text"] as String,
      sentAt: json["sentAt"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "id": id,
      "roomId": roomId,
      "senderId": senderId,
      "senderName": senderName,
      "text": text,
      "sentAt": sentAt,
    };
}

final class MessagePageWire {
  MessagePageWire({
    required List<ChatMessageWire> items,
    required this.nextCursor
  }) : items = List.unmodifiable(items);

  final List<ChatMessageWire> items;
  final String? nextCursor;

  factory MessagePageWire.fromJson(Map<String, Object?> json) => MessagePageWire(
      items: List<ChatMessageWire>.unmodifiable((json["items"] as List<Object?>).map((value) => ChatMessageWire.fromJson(_wireObject(value)))),
      nextCursor: json["nextCursor"] == null ? null : json["nextCursor"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "items": items.map((value) => value.toJson()).toList(growable: false),
      "nextCursor": nextCursor,
    };
}

final class StudySessionWire {
  StudySessionWire({
    required this.id,
    required this.roomId,
    required this.userId,
    required this.status,
    required this.startedAt,
    required this.finishedAt,
    required this.updatedAt
  });

  final String id;
  final String roomId;
  final String userId;
  final SessionStatusWire status;
  final String startedAt;
  final String? finishedAt;
  final String updatedAt;

  factory StudySessionWire.fromJson(Map<String, Object?> json) => StudySessionWire(
      id: json["id"] as String,
      roomId: json["roomId"] as String,
      userId: json["userId"] as String,
      status: SessionStatusWire.values.byName(json["status"] as String),
      startedAt: json["startedAt"] as String,
      finishedAt: json["finishedAt"] == null ? null : json["finishedAt"] as String,
      updatedAt: json["updatedAt"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "id": id,
      "roomId": roomId,
      "userId": userId,
      "status": status.name,
      "startedAt": startedAt,
      "finishedAt": finishedAt,
      "updatedAt": updatedAt,
    };
}

final class SessionPageWire {
  SessionPageWire({
    required List<StudySessionWire> items,
    required this.nextCursor
  }) : items = List.unmodifiable(items);

  final List<StudySessionWire> items;
  final String? nextCursor;

  factory SessionPageWire.fromJson(Map<String, Object?> json) => SessionPageWire(
      items: List<StudySessionWire>.unmodifiable((json["items"] as List<Object?>).map((value) => StudySessionWire.fromJson(_wireObject(value)))),
      nextCursor: json["nextCursor"] == null ? null : json["nextCursor"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "items": items.map((value) => value.toJson()).toList(growable: false),
      "nextCursor": nextCursor,
    };
}

final class CreateRoomRequestWire {
  CreateRoomRequestWire({
    required this.title
  });

  final String title;

  factory CreateRoomRequestWire.fromJson(Map<String, Object?> json) => CreateRoomRequestWire(
      title: json["title"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "title": title,
    };
}

final class DecideJoinRequestRequestWire {
  DecideJoinRequestRequestWire({
    required this.decision
  });

  final JoinRequestDecisionWire decision;

  factory DecideJoinRequestRequestWire.fromJson(Map<String, Object?> json) => DecideJoinRequestRequestWire(
      decision: JoinRequestDecisionWire.values.byName(json["decision"] as String),
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "decision": decision.name,
    };
}

final class TransferOwnershipRequestWire {
  TransferOwnershipRequestWire({
    required this.userId
  });

  final String userId;

  factory TransferOwnershipRequestWire.fromJson(Map<String, Object?> json) => TransferOwnershipRequestWire(
      userId: json["userId"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "userId": userId,
    };
}

final class SendMessageRequestWire {
  SendMessageRequestWire({
    required this.text
  });

  final String text;

  factory SendMessageRequestWire.fromJson(Map<String, Object?> json) => SendMessageRequestWire(
      text: json["text"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "text": text,
    };
}

final class UpdateSessionRequestWire {
  UpdateSessionRequestWire({
    required this.status
  });

  final SessionStatusWire status;

  factory UpdateSessionRequestWire.fromJson(Map<String, Object?> json) => UpdateSessionRequestWire(
      status: SessionStatusWire.values.byName(json["status"] as String),
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "status": status.name,
    };
}

final class ErrorResponseWire {
  ErrorResponseWire({
    required this.code,
    required this.message,
    this.details,
    required this.requestId
  });

  final String code;
  final String message;
  final Object? details;
  final String requestId;

  factory ErrorResponseWire.fromJson(Map<String, Object?> json) => ErrorResponseWire(
      code: json["code"] as String,
      message: json["message"] as String,
      details: json["details"] == null ? null : json["details"],
      requestId: json["requestId"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "code": code,
      "message": message,
      if (details != null) "details": details,
      "requestId": requestId,
    };
}

final class LivenessResponseWire {
  LivenessResponseWire({
    required this.status
  });

  final String status;

  factory LivenessResponseWire.fromJson(Map<String, Object?> json) => LivenessResponseWire(
      status: json["status"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "status": status,
    };
}

final class ReadinessResponseWire {
  ReadinessResponseWire({
    required this.status
  });

  final String status;

  factory ReadinessResponseWire.fromJson(Map<String, Object?> json) => ReadinessResponseWire(
      status: json["status"] as String,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "status": status,
    };
}

typedef MetricsResponseWire = String;

final class MembershipUpdatedPayloadWire {
  MembershipUpdatedPayloadWire({
    required this.roomId,
    required this.active
  });

  final String roomId;
  final bool active;

  factory MembershipUpdatedPayloadWire.fromJson(Map<String, Object?> json) => MembershipUpdatedPayloadWire(
      roomId: json["roomId"] as String,
      active: json["active"] as bool,
    );

  Map<String, Object?> toJson() => <String, Object?>{
      "roomId": roomId,
      "active": active,
    };
}

sealed class RealtimeEnvelopeWire {
  const RealtimeEnvelopeWire({required this.eventId, required this.roomId, required this.roomVersion, required this.occurredAt});

  final String eventId;
  final String? roomId;
  final int? roomVersion;
  final String occurredAt;
  int get schemaVersion => studyRoomRealtimeSchemaVersion;
  String get type;
  Object get payload;

  factory RealtimeEnvelopeWire.fromJson(Map<String, Object?> json) {
    if (json['schemaVersion'] != studyRoomRealtimeSchemaVersion) {
      throw FormatException('Unsupported realtime schemaVersion: ${json['schemaVersion']}');
    }
    return switch (json['type']) {
      "room.state" => RoomStateEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: RoomWire.fromJson(_wireObject(json['payload'])),
      ),
      "membership.updated" => MembershipUpdatedEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: MembershipUpdatedPayloadWire.fromJson(_wireObject(json['payload'])),
      ),
      "join-request.created" => JoinRequestCreatedEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: JoinRequestWire.fromJson(_wireObject(json['payload'])),
      ),
      "join-request.updated" => JoinRequestUpdatedEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: JoinRequestWire.fromJson(_wireObject(json['payload'])),
      ),
      "member.presence.updated" => MemberPresenceUpdatedEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: MemberWire.fromJson(_wireObject(json['payload'])),
      ),
      "chat.message.created" => ChatMessageCreatedEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: ChatMessageWire.fromJson(_wireObject(json['payload'])),
      ),
      "session.updated" => SessionUpdatedEventWire(
        eventId: json['eventId'] as String,
        roomId: json['roomId'] as String?,
        roomVersion: json['roomVersion'] as int?,
        occurredAt: json['occurredAt'] as String,
        payload: StudySessionWire.fromJson(_wireObject(json['payload'])),
      ),
      final value => throw FormatException('Unsupported realtime event type: $value'),
    };
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'eventId': eventId,
    'type': type,
    'roomId': roomId,
    'roomVersion': roomVersion,
    'occurredAt': occurredAt,
    'payload': switch (payload) {
      final RoomWire value => value.toJson(),
      final MembershipUpdatedPayloadWire value => value.toJson(),
      final JoinRequestWire value => value.toJson(),
      final MemberWire value => value.toJson(),
      final ChatMessageWire value => value.toJson(),
      final StudySessionWire value => value.toJson(),
      _ => throw StateError('Unsupported realtime payload'),
    },
  };
}

final class RoomStateEventWire extends RealtimeEnvelopeWire {
  const RoomStateEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "room.state";
  @override
  String get type => eventType;
  @override
  final RoomWire payload;
}

final class MembershipUpdatedEventWire extends RealtimeEnvelopeWire {
  const MembershipUpdatedEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "membership.updated";
  @override
  String get type => eventType;
  @override
  final MembershipUpdatedPayloadWire payload;
}

final class JoinRequestCreatedEventWire extends RealtimeEnvelopeWire {
  const JoinRequestCreatedEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "join-request.created";
  @override
  String get type => eventType;
  @override
  final JoinRequestWire payload;
}

final class JoinRequestUpdatedEventWire extends RealtimeEnvelopeWire {
  const JoinRequestUpdatedEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "join-request.updated";
  @override
  String get type => eventType;
  @override
  final JoinRequestWire payload;
}

final class MemberPresenceUpdatedEventWire extends RealtimeEnvelopeWire {
  const MemberPresenceUpdatedEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "member.presence.updated";
  @override
  String get type => eventType;
  @override
  final MemberWire payload;
}

final class ChatMessageCreatedEventWire extends RealtimeEnvelopeWire {
  const ChatMessageCreatedEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "chat.message.created";
  @override
  String get type => eventType;
  @override
  final ChatMessageWire payload;
}

final class SessionUpdatedEventWire extends RealtimeEnvelopeWire {
  const SessionUpdatedEventWire({
    required super.eventId,
    required super.roomId,
    required super.roomVersion,
    required super.occurredAt,
    required this.payload,
  });

  static const eventType = "session.updated";
  @override
  String get type => eventType;
  @override
  final StudySessionWire payload;
}
