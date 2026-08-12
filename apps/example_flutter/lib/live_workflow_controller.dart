import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:study_room_sdk/study_room_sdk.dart';

enum DemoActor { owner, member }

extension DemoActorDetails on DemoActor {
  String get userId => switch (this) {
    DemoActor.owner => 'example-owner',
    DemoActor.member => 'example-member',
  };

  String get displayName => switch (this) {
    DemoActor.owner => 'Owner',
    DemoActor.member => 'Member',
  };
}

class LiveEndpointConfig {
  const LiveEndpointConfig({
    required this.apiBaseUri,
    required this.realtimeUri,
    required this.tokenEndpoint,
  });

  factory LiveEndpointConfig.defaults() => LiveEndpointConfig(
    apiBaseUri: Uri.parse(
      const String.fromEnvironment(
        'STUDY_ROOM_API_URL',
        defaultValue: 'http://localhost:3000',
      ),
    ),
    realtimeUri: Uri.parse(
      const String.fromEnvironment(
        'STUDY_ROOM_REALTIME_URL',
        defaultValue: 'ws://localhost:3000/v1/realtime',
      ),
    ),
    tokenEndpoint: Uri.parse(
      const String.fromEnvironment(
        'STUDY_ROOM_DEV_TOKEN_URL',
        defaultValue: 'http://localhost:4000/token',
      ),
    ),
  );

  final Uri apiBaseUri;
  final Uri realtimeUri;
  final Uri tokenEndpoint;
}

class DevFixtureTokenProvider {
  DevFixtureTokenProvider({
    required this.endpoint,
    required this.userId,
    required this.displayName,
    http.Client? client,
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _ownsClient = client == null,
       _now = now ?? DateTime.now;

  final Uri endpoint;
  final String userId;
  final String displayName;
  final http.Client _client;
  final bool _ownsClient;
  final DateTime Function() _now;
  StudyRoomAccessToken? _cached;

  Future<StudyRoomAccessToken> call(StudyRoomTokenRequest request) async {
    final cached = _cached;
    if (!request.forceRefresh &&
        cached != null &&
        cached.expiresAt.isAfter(_now().add(request.minimumValidity))) {
      return cached;
    }

    final response = await _client.post(
      endpoint,
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'sub': userId, 'displayName': displayName}),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StudyRoomException(
        'Development token endpoint returned ${response.statusCode}',
        kind: StudyRoomExceptionKind.authentication,
        code: 'fixture_token_failed',
      );
    }
    final body = jsonDecode(response.body);
    if (body is! Map) {
      throw const StudyRoomException(
        'Development token endpoint returned invalid JSON',
        kind: StudyRoomExceptionKind.protocol,
        code: 'fixture_token_invalid',
      );
    }
    final token = body['accessToken'];
    final expiresAt = DateTime.tryParse('${body['expiresAt']}');
    if (token is! String || token.trim().isEmpty || expiresAt == null) {
      throw const StudyRoomException(
        'Development token response is missing accessToken or expiresAt',
        kind: StudyRoomExceptionKind.protocol,
        code: 'fixture_token_invalid',
      );
    }
    final result = StudyRoomAccessToken(token: token, expiresAt: expiresAt);
    _cached = result;
    return result;
  }

  void close() {
    if (_ownsClient) _client.close();
  }
}

abstract class LiveActorGateway {
  DemoActor get actor;
  StudyRoomSyncState get syncState;
  StudyRoomConnectionState get connectionState;
  Stream<StudyRoomSyncState> get syncStates;
  Stream<StudyRoomConnectionState> get connectionStates;

  Future<void> start();
  Future<StudyRoom> createRoom(String title);
  Future<RoomJoinRequest> requestJoin(String roomId);
  Future<List<RoomJoinRequest>> pendingRequests(String roomId);
  Future<void> approve(String roomId, String requestId);
  Future<StudyRoom> subscribe(String roomId);
  Future<void> unsubscribe(String roomId);
  Future<ChatMessage> sendMessage(String roomId, String text);
  Future<StudySessionState> startSession(String roomId);
  Future<StudySessionState> updateSession(
    String sessionId,
    StudySessionStatus status,
  );
  Future<void> setAway(String roomId, bool away);
  Future<void> removeMember(String roomId, String userId);
  Future<void> leave(String roomId);
  Future<StudyRoom> transferOwnership(String roomId, String userId);
  Future<void> deleteRoom(String roomId);
  Future<void> close();
}

typedef LiveActorGatewayFactory =
    LiveActorGateway Function(DemoActor actor, LiveEndpointConfig endpoints);

class SdkLiveActorGateway implements LiveActorGateway {
  SdkLiveActorGateway({
    required this.actor,
    required LiveEndpointConfig endpoints,
  }) : _tokenProvider = DevFixtureTokenProvider(
         endpoint: endpoints.tokenEndpoint,
         userId: actor.userId,
         displayName: actor.displayName,
       ) {
    _sdk = StudyRoomSdk(
      StudyRoomSdkConfig(
        apiBaseUri: endpoints.apiBaseUri,
        realtimeUri: endpoints.realtimeUri,
        tokenProvider: _tokenProvider.call,
      ),
    );
    _syncSubscription = _sdk.syncStates.listen((value) => _sync = value);
    _connectionSubscription = _sdk.connectionStates.listen(
      (value) => _connection = value,
    );
  }

  @override
  final DemoActor actor;
  final DevFixtureTokenProvider _tokenProvider;
  late final StudyRoomSdk _sdk;
  late final StreamSubscription<StudyRoomSyncState> _syncSubscription;
  late final StreamSubscription<StudyRoomConnectionState>
  _connectionSubscription;
  StudyRoomSyncState _sync = StudyRoomSyncState.empty();
  StudyRoomConnectionState _connection = StudyRoomConnectionState.stopped;

  @override
  StudyRoomSyncState get syncState => _sync;
  @override
  StudyRoomConnectionState get connectionState => _connection;
  @override
  Stream<StudyRoomSyncState> get syncStates => _sdk.syncStates;
  @override
  Stream<StudyRoomConnectionState> get connectionStates =>
      _sdk.connectionStates;

  @override
  Future<void> start() => _sdk.start();
  @override
  Future<StudyRoom> createRoom(String title) => _sdk.rooms.create(title);
  @override
  Future<RoomJoinRequest> requestJoin(String roomId) =>
      _sdk.joinRequests.request(roomId);
  @override
  Future<List<RoomJoinRequest>> pendingRequests(String roomId) async =>
      (await _sdk.joinRequests.forRoom(roomId)).items;
  @override
  Future<void> approve(String roomId, String requestId) async {
    await _sdk.joinRequests.decide(
      roomId,
      requestId,
      JoinRequestStatus.approved,
    );
  }

  @override
  Future<StudyRoom> subscribe(String roomId) => _sdk.rooms.subscribe(roomId);
  @override
  Future<void> unsubscribe(String roomId) => _sdk.rooms.unsubscribe(roomId);
  @override
  Future<ChatMessage> sendMessage(String roomId, String text) =>
      _sdk.chat.send(roomId, text);
  @override
  Future<StudySessionState> startSession(String roomId) =>
      _sdk.sessions.start(roomId);
  @override
  Future<StudySessionState> updateSession(
    String sessionId,
    StudySessionStatus status,
  ) => _sdk.sessions.update(sessionId, status);
  @override
  Future<void> setAway(String roomId, bool away) => _sdk.setAway(roomId, away);
  @override
  Future<void> removeMember(String roomId, String userId) =>
      _sdk.members.remove(roomId, userId);
  @override
  Future<void> leave(String roomId) => _sdk.members.leave(roomId);
  @override
  Future<StudyRoom> transferOwnership(String roomId, String userId) =>
      _sdk.members.transferOwnership(roomId, userId);
  @override
  Future<void> deleteRoom(String roomId) => _sdk.rooms.delete(roomId);

  @override
  Future<void> close() async {
    await _syncSubscription.cancel();
    await _connectionSubscription.cancel();
    await _sdk.close();
    _tokenProvider.close();
  }
}

enum WorkflowAction {
  createRoom,
  requestJoin,
  approve,
  subscribeBoth,
  ownerChat,
  memberChat,
  startSession,
  pauseSession,
  resumeSession,
  finishSession,
  presenceAway,
  removeMember,
  requestAgain,
  leave,
  rejoin,
  transferOwnership,
  originalOwnerLeave,
  deleteRoom,
}

class LiveWorkflowController extends ChangeNotifier {
  LiveWorkflowController({
    LiveEndpointConfig? endpoints,
    LiveActorGatewayFactory? gatewayFactory,
  }) : endpoints = endpoints ?? LiveEndpointConfig.defaults(),
       _gatewayFactory =
           gatewayFactory ??
           ((actor, config) =>
               SdkLiveActorGateway(actor: actor, endpoints: config));

  LiveEndpointConfig endpoints;
  final LiveActorGatewayFactory _gatewayFactory;
  final Map<DemoActor, LiveActorGateway> _gateways = {};
  final Map<DemoActor, StreamSubscription<Object?>> _syncSubscriptions = {};
  final Map<DemoActor, StreamSubscription<Object?>> _connectionSubscriptions =
      {};
  final Set<String> _pending = {};
  final Map<String, String> _errors = {};
  final Set<WorkflowAction> _completed = {};
  final Map<DemoActor, StudySessionState> _sessions = {};
  Future<void>? _connectionOperation;
  String? roomId;
  RoomJoinRequest? joinRequest;
  bool connected = false;
  bool disposed = false;

  Set<WorkflowAction> get completedActions => Set.unmodifiable(_completed);
  bool isPending(String command) => _pending.contains(command);
  String? errorFor(String command) => _errors[command];
  LiveActorGateway? gatewayFor(DemoActor actor) => _gateways[actor];
  StudyRoomSyncState syncFor(DemoActor actor) =>
      _gateways[actor]?.syncState ?? StudyRoomSyncState.empty();
  StudyRoomConnectionState connectionFor(DemoActor actor) =>
      _gateways[actor]?.connectionState ?? StudyRoomConnectionState.stopped;
  StudyRoom? roomFor(DemoActor actor) {
    final id = roomId;
    return id == null ? null : syncFor(actor).rooms[id];
  }

  StudyMember? membershipFor(DemoActor actor) => roomFor(
    actor,
  )?.members.where((member) => member.id == actor.userId).firstOrNull;
  bool isRoomOwner(DemoActor actor) =>
      membershipFor(actor)?.role == RoomRole.owner;
  bool isMember(DemoActor actor) => membershipFor(actor) != null;
  List<ChatMessage> messagesFor(DemoActor actor) {
    final id = roomId;
    return id == null
        ? const []
        : syncFor(actor).recentMessagesByRoom[id] ?? const [];
  }

  StudySessionState? sessionFor(DemoActor actor) {
    final id = roomId;
    final synced = id == null
        ? const <StudySessionState>[]
        : syncFor(actor).activeSessionsByRoom[id] ?? const [];
    return synced.where((item) => item.userId == actor.userId).firstOrNull ??
        _sessions[actor];
  }

  Future<void> connect() => _connect(endpoints);

  Future<void> updateEndpoints(LiveEndpointConfig value) async {
    await _connect(value);
  }

  Future<void> createRoom(String title) => _command('create', () async {
    final room = await _gateway(DemoActor.owner).createRoom(title);
    roomId = room.id;
    await _gateway(DemoActor.owner).subscribe(room.id);
    _completed.add(WorkflowAction.createRoom);
  });

  Future<void> requestJoin({bool again = false}) =>
      _command('request', () async {
        final id = _requireRoom();
        joinRequest = await _gateway(DemoActor.member).requestJoin(id);
        _completed.add(
          again ? WorkflowAction.requestAgain : WorkflowAction.requestJoin,
        );
      });

  Future<void> approve() => _command('approve', () async {
    final id = _requireRoom();
    final owner = currentOwner;
    final requests = await _gateway(owner).pendingRequests(id);
    final pending = requests
        .where(
          (request) =>
              request.userId == otherActor(owner).userId &&
              request.status == JoinRequestStatus.pending,
        )
        .firstOrNull;
    if (pending == null) {
      throw StateError('No pending request for the other actor');
    }
    await _gateway(owner).approve(id, pending.id);
    joinRequest = pending;
    _completed.add(WorkflowAction.approve);
  });

  Future<void> subscribeBoth() => _command('subscribe', () async {
    final id = _requireRoom();
    await Future.wait(
      DemoActor.values.map((actor) => _gateway(actor).subscribe(id)),
    );
    _completed.add(WorkflowAction.subscribeBoth);
    if (_completed.contains(WorkflowAction.leave) &&
        _completed.contains(WorkflowAction.requestAgain)) {
      _completed.add(WorkflowAction.rejoin);
    }
  });

  Future<void> sendMessage(DemoActor actor, String text) =>
      _command('${actor.name}-chat', () async {
        await _gateway(actor).sendMessage(_requireRoom(), text);
        _completed.add(
          actor == DemoActor.owner
              ? WorkflowAction.ownerChat
              : WorkflowAction.memberChat,
        );
      });

  Future<void> startSession(DemoActor actor) =>
      _command('${actor.name}-session', () async {
        _sessions[actor] = await _gateway(actor).startSession(_requireRoom());
        _completed.add(WorkflowAction.startSession);
      });

  Future<void> updateSession(
    DemoActor actor,
    StudySessionStatus status,
  ) => _command('${actor.name}-session', () async {
    final session = sessionFor(actor);
    if (session == null || session.id.isEmpty) {
      throw StateError('Start a session first');
    }
    _sessions[actor] = await _gateway(actor).updateSession(session.id, status);
    _completed.add(switch (status) {
      StudySessionStatus.paused => WorkflowAction.pauseSession,
      StudySessionStatus.running => WorkflowAction.resumeSession,
      StudySessionStatus.finished => WorkflowAction.finishSession,
      StudySessionStatus.idle => throw StateError('Idle cannot be persisted'),
    });
  });

  Future<void> setAway(DemoActor actor, bool away) =>
      _command('${actor.name}-presence', () async {
        await _gateway(actor).setAway(_requireRoom(), away);
        if (away) _completed.add(WorkflowAction.presenceAway);
      });

  Future<void> removeOther(DemoActor actor) => _command('remove', () async {
    final target = otherActor(actor);
    await _gateway(actor).removeMember(_requireRoom(), target.userId);
    await _bestEffortUnsubscribe(target);
    _sessions.remove(target);
    _completed.add(WorkflowAction.removeMember);
  });

  Future<void> leave(DemoActor actor) =>
      _command('${actor.name}-leave', () async {
        final isOriginalOwnerLeaving =
            actor == DemoActor.owner &&
            _completed.contains(WorkflowAction.transferOwnership);
        await _gateway(actor).leave(_requireRoom());
        await _bestEffortUnsubscribe(actor);
        _sessions.remove(actor);
        _completed.add(
          isOriginalOwnerLeaving
              ? WorkflowAction.originalOwnerLeave
              : WorkflowAction.leave,
        );
      });

  Future<void> transferToOther(DemoActor actor) =>
      _command('transfer', () async {
        await _gateway(
          actor,
        ).transferOwnership(_requireRoom(), otherActor(actor).userId);
        _completed.add(WorkflowAction.transferOwnership);
      });

  Future<void> deleteRoom(DemoActor actor) => _command('delete', () async {
    final id = _requireRoom();
    await _gateway(actor).deleteRoom(id);
    for (final candidate in DemoActor.values) {
      await _bestEffortUnsubscribe(candidate);
    }
    roomId = null;
    joinRequest = null;
    _sessions.clear();
    _completed.add(WorkflowAction.deleteRoom);
  });

  DemoActor get currentOwner {
    for (final actor in DemoActor.values) {
      if (isRoomOwner(actor)) return actor;
    }
    return DemoActor.owner;
  }

  static DemoActor otherActor(DemoActor actor) =>
      actor == DemoActor.owner ? DemoActor.member : DemoActor.owner;

  Future<void> _replaceGateways() async {
    await _closeGateways();
    for (final actor in DemoActor.values) {
      final gateway = _gatewayFactory(actor, endpoints);
      _gateways[actor] = gateway;
      _syncSubscriptions[actor] = gateway.syncStates.listen((_) {
        if (!disposed) notifyListeners();
      });
      _connectionSubscriptions[actor] = gateway.connectionStates.listen((_) {
        if (!disposed) notifyListeners();
      });
    }
  }

  Future<void> _connect(LiveEndpointConfig requestedEndpoints) {
    final operation = _connectionOperation;
    final next = () async {
      if (operation != null) {
        try {
          await operation;
        } catch (_) {
          // A queued reconnect must still be allowed to replace a failed
          // connection attempt. The original caller keeps the first error.
        }
      }
      if (disposed) return;
      endpoints = requestedEndpoints;
      roomId = null;
      joinRequest = null;
      _sessions.clear();
      _completed.clear();
      connected = false;
      await _command('connect', () async {
        await _replaceGateways();
        await Future.wait(_gateways.values.map((gateway) => gateway.start()));
        connected = true;
      });
    }();
    late final Future<void> tracked;
    tracked = next.whenComplete(() {
      if (identical(_connectionOperation, tracked)) {
        _connectionOperation = null;
      }
    });
    _connectionOperation = tracked;
    return tracked;
  }

  Future<void> _command(String key, Future<void> Function() action) async {
    if (_pending.contains(key)) return;
    _pending.add(key);
    _errors.remove(key);
    notifyListeners();
    try {
      await action();
    } catch (error) {
      _errors[key] = error.toString();
      rethrow;
    } finally {
      _pending.remove(key);
      if (!disposed) notifyListeners();
    }
  }

  LiveActorGateway _gateway(DemoActor actor) {
    final gateway = _gateways[actor];
    if (gateway == null) throw StateError('Connect both actors first');
    return gateway;
  }

  String _requireRoom() {
    final id = roomId;
    if (id == null) throw StateError('Create a room first');
    return id;
  }

  Future<void> _bestEffortUnsubscribe(DemoActor actor) async {
    final id = roomId;
    if (id == null) return;
    try {
      await _gateway(actor).unsubscribe(id);
    } catch (_) {
      // Removal and deletion events already evict SDK state when access is gone.
    }
  }

  Future<void> _closeGateways() async {
    for (final subscription in _syncSubscriptions.values) {
      await subscription.cancel();
    }
    for (final subscription in _connectionSubscriptions.values) {
      await subscription.cancel();
    }
    _syncSubscriptions.clear();
    _connectionSubscriptions.clear();
    await Future.wait(_gateways.values.map((gateway) => gateway.close()));
    _gateways.clear();
  }

  Future<void> close() async {
    if (disposed) return;
    disposed = true;
    await _closeGateways();
    super.dispose();
  }
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    final iterator = this.iterator;
    return iterator.moveNext() ? iterator.current : null;
  }
}
