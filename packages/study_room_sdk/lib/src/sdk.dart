import 'dart:async';
import 'dart:collection';

import 'errors.dart';
import 'models.dart';
import 'realtime.dart';
import 'transport.dart';

typedef StudyRoomClock = DateTime Function();

class StudyRoomSdkConfig {
  const StudyRoomSdkConfig({
    required this.apiBaseUri,
    required this.realtimeUri,
    required this.tokenProvider,
    this.requestTimeout = const Duration(seconds: 15),
    this.realtimeAckTimeout = const Duration(seconds: 5),
    this.realtimeConnectTimeout = const Duration(seconds: 10),
    this.tokenRefreshSkew = const Duration(seconds: 30),
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.clock,
    this.transport,
    this.realtimeConnector,
  });

  final Uri apiBaseUri;
  final Uri realtimeUri;
  final StudyRoomTokenProvider tokenProvider;
  final Duration requestTimeout;
  final Duration realtimeAckTimeout;
  final Duration realtimeConnectTimeout;
  final Duration tokenRefreshSkew;
  final Duration reconnectBaseDelay;
  final StudyRoomClock? clock;
  final StudyRoomTransport? transport;
  final StudyRoomRealtimeConnector? realtimeConnector;
}

class StudyRoomSdk {
  StudyRoomSdk(this.config)
    : _transport =
          config.transport ??
          HttpStudyRoomTransport(
            config.apiBaseUri,
            timeout: config.requestTimeout,
          ),
      _realtimeConnector =
          config.realtimeConnector ??
          SocketIoStudyRoomRealtimeConnector(
            ackTimeout: config.realtimeAckTimeout,
            connectTimeout: config.realtimeConnectTimeout,
          ) {
    _validateUri(config.apiBaseUri, const {'http', 'https'}, 'apiBaseUri');
    _validateUri(config.realtimeUri, const {'ws', 'wss'}, 'realtimeUri');
    if (config.requestTimeout <= Duration.zero ||
        config.realtimeAckTimeout <= Duration.zero ||
        config.realtimeConnectTimeout <= Duration.zero ||
        config.reconnectBaseDelay <= Duration.zero ||
        config.tokenRefreshSkew.isNegative) {
      throw const StudyRoomException(
        'Timeouts must be positive and tokenRefreshSkew cannot be negative',
        kind: StudyRoomExceptionKind.configuration,
        code: 'invalid_config',
      );
    }
    rooms = StudyRoomsApi._(this);
    joinRequests = StudyJoinRequestsApi._(this);
    members = StudyMembersApi._(this);
    sessions = StudySessionsApi._(this);
    chat = StudyChatApi._(this);
  }

  final StudyRoomSdkConfig config;
  final StudyRoomTransport _transport;
  final StudyRoomRealtimeConnector _realtimeConnector;
  late final StudyRoomsApi rooms;
  late final StudyJoinRequestsApi joinRequests;
  late final StudyMembersApi members;
  late final StudySessionsApi sessions;
  late final StudyChatApi chat;

  final _events = StreamController<StudyRoomRealtimeEvent>.broadcast();
  final _states = StreamController<StudyRoomConnectionState>.broadcast();
  final _syncStates = StreamController<StudyRoomSyncState>.broadcast();
  final _joinedRoomIds = <String>{};
  final _pendingRoomSeeds = <String, StudyRoom>{};
  final _seenEventIds = LinkedHashSet<String>();
  final _bufferedEvents = <StudyRoomRealtimeEvent>[];
  final _lifecycleCancellation = StudyRoomCancellationToken();

  StudyRoomRealtimeConnection? _connection;
  StreamSubscription<Map<String, dynamic>>? _eventSubscription;
  StreamSubscription<StudyRoomConnectionState>? _stateSubscription;
  Timer? _refreshTimer;
  Timer? _reconnectTimer;
  Future<void>? _lifecycleTask;
  var _connectionState = StudyRoomConnectionState.stopped;
  var _syncState = StudyRoomSyncState.empty();
  var _generation = 0;
  var _reconnectAttempts = 0;
  var _started = false;
  var _closed = false;
  var _bufferingEvents = false;
  var _replacementRequested = false;
  var _forceRefreshRequested = false;
  var _connectionLost = false;

  DateTime get _now => (config.clock ?? DateTime.now)();

  Stream<StudyRoomRealtimeEvent> get events => _events.stream;
  Stream<StudyRoomConnectionState> get connectionStates async* {
    yield _connectionState;
    yield* _states.stream;
  }

  StudyRoomSyncState get syncState => _syncState;
  Stream<StudyRoomSyncState> get syncStates async* {
    yield _syncState;
    yield* _syncStates.stream;
  }

  Stream<StudyRoom> get roomStates => events
      .where((event) => event.type == 'room.state')
      .map((event) => StudyRoom.fromJson(event.payload));
  Stream<ChatMessage> get messages => events
      .where((event) => event.type == 'chat.message.created')
      .map((event) => ChatMessage.fromJson(event.payload));
  Stream<StudySessionState> get sessionUpdates => events
      .where((event) => event.type == 'session.updated')
      .map((event) => StudySessionState.fromJson(event.payload));

  StudyRoom? roomSnapshot(String roomId) => _syncState.rooms[roomId];

  Future<void> start({StudyRoomCancellationToken? cancellationToken}) async {
    if (_closed) throw _closedError();
    if (_started) {
      await _lifecycleTask;
      return;
    }
    _started = true;
    try {
      await _runLifecycle(
        (generation) => _replaceRealtime(
          generation,
          StudyRoomConnectionState.connecting,
          cancellationToken: cancellationToken,
        ),
      );
    } catch (_) {
      _started = false;
      rethrow;
    }
  }

  Future<void> resync({StudyRoomCancellationToken? cancellationToken}) {
    _requireStarted();
    final existing = _lifecycleTask;
    if (existing != null) {
      return existing.then((_) => resync(cancellationToken: cancellationToken));
    }
    return _runLifecycle((generation) async {
      _setState(StudyRoomConnectionState.synchronizing);
      final degraded = await _synchronize(
        generation,
        cancellationToken: cancellationToken,
      );
      _ensureGeneration(generation);
      _setState(
        degraded
            ? StudyRoomConnectionState.degraded
            : StudyRoomConnectionState.connected,
      );
      if (degraded) {
        _replacementRequested = true;
      } else {
        _reconnectAttempts = 0;
      }
    });
  }

  Future<void> _replaceRealtime(
    int generation,
    StudyRoomConnectionState state, {
    bool forceRefresh = false,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    _replacementRequested = false;
    _forceRefreshRequested = false;
    _connectionLost = false;
    _setState(state);
    _refreshTimer?.cancel();
    await _detachRealtime();
    final linked = _linkedCancellation(cancellationToken);
    final token = await _token(
      minimumValidity: config.tokenRefreshSkew,
      forceRefresh: forceRefresh,
      cancellationToken: linked,
    );
    final connection = await _realtimeConnector.connect(
      config.realtimeUri,
      token: token,
      cancellationToken: linked,
    );
    try {
      _ensureGeneration(generation);
      _connection = connection;
      _eventSubscription = connection.events.listen(
        _handleRealtimeEvent,
        onError: _addEventError,
      );
      _stateSubscription = connection.states.listen(_handleConnectionState);
      _beginEventBuffer();
      for (final roomId in _joinedRoomIds.toList(growable: false)) {
        try {
          await connection.emitWithAck('room.subscribe', {
            'roomId': roomId,
          }, cancellationToken: linked);
        } on StudyRoomException catch (error) {
          if (error.kind == StudyRoomExceptionKind.authorization ||
              error.kind == StudyRoomExceptionKind.notFound) {
            _removeRoom(roomId);
            continue;
          }
          rethrow;
        }
      }
      _setState(StudyRoomConnectionState.synchronizing);
      final degraded = await _synchronize(
        generation,
        cancellationToken: linked,
        bufferAlreadyStarted: true,
      );
      _ensureGeneration(generation);
      if (_connectionLost) {
        throw const StudyRoomException(
          'Realtime disconnected while synchronizing',
          kind: StudyRoomExceptionKind.network,
          code: 'realtime_disconnected',
        );
      }
      _reconnectAttempts = 0;
      _setState(
        degraded
            ? StudyRoomConnectionState.degraded
            : StudyRoomConnectionState.connected,
      );
      if (degraded) _replacementRequested = true;
      _scheduleTokenRefresh(token);
    } catch (_) {
      if (identical(_connection, connection)) await _detachRealtime();
      await connection.close();
      rethrow;
    }
  }

  Future<void> _detachRealtime() async {
    final events = _eventSubscription;
    final states = _stateSubscription;
    final connection = _connection;
    _eventSubscription = null;
    _stateSubscription = null;
    _connection = null;
    await events?.cancel();
    await states?.cancel();
    await connection?.close();
  }

  Future<void> _runLifecycle(Future<void> Function(int generation) operation) {
    final existing = _lifecycleTask;
    if (existing != null) return existing;
    final generation = ++_generation;
    late final Future<void> task;
    task = operation(generation).whenComplete(() {
      if (identical(_lifecycleTask, task)) _lifecycleTask = null;
      if (_started && !_closed && (_replacementRequested || _connectionLost)) {
        _scheduleReconnect(forceRefresh: _forceRefreshRequested);
      }
    });
    _lifecycleTask = task;
    return task;
  }

  void _handleConnectionState(StudyRoomConnectionState state) {
    if (state == StudyRoomConnectionState.disconnected) {
      _connectionLost = true;
      _replacementRequested = true;
    } else if (state == StudyRoomConnectionState.refreshing) {
      _replacementRequested = true;
      _forceRefreshRequested = true;
    } else {
      return;
    }
    if (_lifecycleTask == null) {
      _scheduleReconnect(forceRefresh: _forceRefreshRequested);
    }
  }

  void _scheduleReconnect({bool forceRefresh = false}) {
    if (_closed || !_started) return;
    _forceRefreshRequested = _forceRefreshRequested || forceRefresh;
    if (_reconnectTimer?.isActive ?? false) return;
    final multiplier = 1 << _reconnectAttempts.clamp(0, 5);
    final delayMs = (config.reconnectBaseDelay.inMilliseconds * multiplier)
        .clamp(1, const Duration(seconds: 30).inMilliseconds);
    _reconnectAttempts += 1;
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () async {
      if (_closed || !_started) return;
      final refresh = _forceRefreshRequested;
      _forceRefreshRequested = false;
      try {
        await _runLifecycle(
          (generation) => _replaceRealtime(
            generation,
            refresh
                ? StudyRoomConnectionState.refreshing
                : StudyRoomConnectionState.reconnecting,
            forceRefresh: refresh,
          ),
        );
      } catch (error, stackTrace) {
        _addEventError(error, stackTrace);
        _replacementRequested = true;
        _scheduleReconnect(forceRefresh: refresh);
      }
    });
  }

  void _scheduleTokenRefresh(StudyRoomAccessToken token) {
    _refreshTimer?.cancel();
    final refreshIn =
        token.expiresAt.difference(_now) - config.tokenRefreshSkew;
    _refreshTimer = Timer(
      refreshIn > Duration.zero ? refreshIn : Duration.zero,
      () {
        _replacementRequested = true;
        _forceRefreshRequested = true;
        _scheduleReconnect(forceRefresh: true);
      },
    );
  }

  Future<bool> _synchronize(
    int generation, {
    StudyRoomCancellationToken? cancellationToken,
    bool bufferAlreadyStarted = false,
  }) async {
    if (!bufferAlreadyStarted) _beginEventBuffer();
    final previous = _syncState;
    final nextRooms = <String, StudyRoom>{};
    final nextSessions = <String, List<StudySessionState>>{};
    final nextMessages = <String, List<ChatMessage>>{};
    final nextOwnerInbox = <String, List<RoomJoinRequest>>{};
    final staleRooms = <String>{};
    var myRequests = previous.myJoinRequests;
    var personalDataStale = false;
    try {
      final roomIds = _joinedRoomIds.toList(growable: false);
      var nextRoomIndex = 0;
      Future<void> worker() async {
        while (nextRoomIndex < roomIds.length) {
          final roomId = roomIds[nextRoomIndex];
          nextRoomIndex += 1;
          _ensureGeneration(generation);
          await _synchronizeRoom(
            roomId,
            previous: previous,
            nextRooms: nextRooms,
            nextSessions: nextSessions,
            nextMessages: nextMessages,
            nextOwnerInbox: nextOwnerInbox,
            staleRooms: staleRooms,
            cancellationToken: cancellationToken,
          );
        }
      }

      await Future.wait(
        List.generate(roomIds.length.clamp(0, 4), (_) => worker()),
      );
      try {
        myRequests = (await joinRequests.mine(
          limit: 100,
          cancellationToken: cancellationToken,
        )).items;
      } on StudyRoomException catch (error) {
        if (error.kind == StudyRoomExceptionKind.authentication ||
            error.kind == StudyRoomExceptionKind.cancelled) {
          rethrow;
        }
        if (!error.retryable) rethrow;
        personalDataStale = true;
      }
      _ensureGeneration(generation);
      var candidate = StudyRoomSyncState(
        rooms: nextRooms,
        activeSessionsByRoom: nextSessions,
        recentMessagesByRoom: nextMessages,
        myJoinRequests: myRequests,
        ownerInboxByRoom: nextOwnerInbox,
        staleRoomIds: staleRooms,
        personalDataStale: personalDataStale,
        lastSyncedAt: staleRooms.isEmpty && !personalDataStale
            ? _now
            : previous.lastSyncedAt,
      );
      candidate = _finishEventBuffer(candidate);
      _publishSyncState(candidate);
      return candidate.isDegraded;
    } catch (_) {
      final recovered = _finishEventBuffer(previous);
      if (!identical(recovered, previous)) _publishSyncState(recovered);
      rethrow;
    }
  }

  Future<void> _synchronizeRoom(
    String roomId, {
    required StudyRoomSyncState previous,
    required Map<String, StudyRoom> nextRooms,
    required Map<String, List<StudySessionState>> nextSessions,
    required Map<String, List<ChatMessage>> nextMessages,
    required Map<String, List<RoomJoinRequest>> nextOwnerInbox,
    required Set<String> staleRooms,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    StudyRoom room;
    try {
      room = await rooms.get(roomId, cancellationToken: cancellationToken);
    } on StudyRoomException catch (error) {
      if (error.kind == StudyRoomExceptionKind.authentication ||
          error.kind == StudyRoomExceptionKind.cancelled) {
        rethrow;
      }
      if (error.kind == StudyRoomExceptionKind.authorization ||
          error.kind == StudyRoomExceptionKind.notFound) {
        _removeRoom(roomId, publish: false);
        return;
      }
      if (!error.retryable) rethrow;
      final oldRoom = previous.rooms[roomId] ?? _pendingRoomSeeds[roomId];
      if (oldRoom != null) nextRooms[roomId] = oldRoom;
      nextSessions[roomId] = previous.activeSessionsByRoom[roomId] ?? const [];
      nextMessages[roomId] = previous.recentMessagesByRoom[roomId] ?? const [];
      if (previous.ownerInboxByRoom.containsKey(roomId)) {
        nextOwnerInbox[roomId] = previous.ownerInboxByRoom[roomId] ?? const [];
      }
      staleRooms.add(roomId);
      return;
    }

    nextRooms[roomId] = room;
    try {
      nextSessions[roomId] = await _allActiveSessions(
        roomId,
        cancellationToken: cancellationToken,
      );
    } on StudyRoomException catch (error) {
      _rethrowGlobalSyncError(error);
      if (!error.retryable) throw error;
      nextSessions[roomId] = previous.activeSessionsByRoom[roomId] ?? const [];
      staleRooms.add(roomId);
    }

    try {
      nextMessages[roomId] = (await chat.history(
        roomId,
        limit: 100,
        cancellationToken: cancellationToken,
      )).items;
    } on StudyRoomException catch (error) {
      _rethrowGlobalSyncError(error);
      if (!error.retryable) throw error;
      nextMessages[roomId] = previous.recentMessagesByRoom[roomId] ?? const [];
      staleRooms.add(roomId);
    }

    try {
      nextOwnerInbox[roomId] = await _allOwnerJoinRequests(
        roomId,
        cancellationToken: cancellationToken,
      );
    } on StudyRoomException catch (error) {
      _rethrowGlobalSyncError(error);
      if (error.kind == StudyRoomExceptionKind.authorization) {
        nextOwnerInbox.remove(roomId);
        return;
      }
      if (!error.retryable) throw error;
      if (previous.ownerInboxByRoom.containsKey(roomId)) {
        nextOwnerInbox[roomId] = previous.ownerInboxByRoom[roomId] ?? const [];
      }
      staleRooms.add(roomId);
    }
  }

  static void _rethrowGlobalSyncError(StudyRoomException error) {
    if (error.kind == StudyRoomExceptionKind.authentication ||
        error.kind == StudyRoomExceptionKind.cancelled) {
      throw error;
    }
  }

  Future<List<StudySessionState>> _allActiveSessions(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final items = <StudySessionState>[];
    String? cursor;
    final seenCursors = <String>{};
    do {
      final page = await sessions.listActive(
        roomId,
        cursor: cursor,
        limit: 100,
        cancellationToken: cancellationToken,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw const StudyRoomException(
          'Active-session pagination returned a repeated cursor',
          kind: StudyRoomExceptionKind.protocol,
          code: 'invalid_cursor',
        );
      }
    } while (cursor != null);
    return items;
  }

  Future<List<RoomJoinRequest>> _allOwnerJoinRequests(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final items = <RoomJoinRequest>[];
    String? cursor;
    final seenCursors = <String>{};
    do {
      final page = await joinRequests.forRoom(
        roomId,
        cursor: cursor,
        limit: 100,
        cancellationToken: cancellationToken,
      );
      items.addAll(page.items);
      cursor = page.nextCursor;
      if (cursor != null && !seenCursors.add(cursor)) {
        throw const StudyRoomException(
          'Owner join-request pagination returned a repeated cursor',
          kind: StudyRoomExceptionKind.protocol,
          code: 'invalid_cursor',
        );
      }
    } while (cursor != null);
    return items;
  }

  void _beginEventBuffer() {
    _bufferedEvents.clear();
    _bufferingEvents = true;
  }

  StudyRoomSyncState _finishEventBuffer(StudyRoomSyncState state) {
    var next = state;
    _bufferingEvents = false;
    final buffered = List<StudyRoomRealtimeEvent>.of(_bufferedEvents);
    _bufferedEvents.clear();
    for (final event in buffered) {
      next = _applyEvent(next, event);
    }
    return next;
  }

  void _handleRealtimeEvent(Map<String, dynamic> value) {
    try {
      final event = StudyRoomRealtimeEvent.fromJson(value);
      if (!_rememberEvent(event.eventId)) return;
      if (_bufferingEvents) {
        _bufferedEvents.add(event);
      } else {
        _publishSyncState(_applyEvent(_syncState, event));
      }
      _events.add(event);
    } catch (error, stackTrace) {
      _addEventError(error, stackTrace);
    }
  }

  bool _rememberEvent(String eventId) {
    if (!_seenEventIds.add(eventId)) return false;
    if (_seenEventIds.length > 1024) _seenEventIds.remove(_seenEventIds.first);
    return true;
  }

  StudyRoomSyncState _applyEvent(
    StudyRoomSyncState state,
    StudyRoomRealtimeEvent event,
  ) {
    final roomId = event.roomId;
    final rooms = Map<String, StudyRoom>.of(state.rooms);
    final sessionsByRoom = _copyLists(state.activeSessionsByRoom);
    final messagesByRoom = _copyLists(state.recentMessagesByRoom);
    final ownerInboxByRoom = _copyLists(state.ownerInboxByRoom);
    var myRequests = List<RoomJoinRequest>.of(state.myJoinRequests);

    switch (event.type) {
      case 'room.state':
        final room = StudyRoom.fromJson(event.payload);
        final current = rooms[room.id];
        if (current == null || current.version <= room.version)
          rooms[room.id] = room;
      case 'membership.updated':
        if (event.payload['active'] == false && roomId != null) {
          _joinedRoomIds.remove(roomId);
          rooms.remove(roomId);
          sessionsByRoom.remove(roomId);
          messagesByRoom.remove(roomId);
          ownerInboxByRoom.remove(roomId);
        }
      case 'member.presence.updated':
        if (roomId != null && rooms[roomId] != null) {
          final memberId = event.payload['id'] as String?;
          final status = event.payload['status'];
          if (memberId != null && status != null) {
            final room = rooms[roomId]!;
            rooms[roomId] = StudyRoom(
              id: room.id,
              appId: room.appId,
              title: room.title,
              version: event.roomVersion ?? room.version,
              members: room.members
                  .map(
                    (member) => member.id == memberId
                        ? StudyMember(
                            id: member.id,
                            displayName: member.displayName,
                            avatarUrl: member.avatarUrl,
                            status: PresenceStatus.values.firstWhere(
                              (candidate) => candidate.name == status,
                            ),
                            role: member.role,
                          )
                        : member,
                  )
                  .toList(growable: false),
            );
          }
        }
      case 'chat.message.created':
        if (roomId != null) {
          final message = ChatMessage.fromJson(event.payload);
          final messages = messagesByRoom[roomId] ?? <ChatMessage>[];
          if (!messages.any((item) => item.id == message.id)) {
            messages.add(message);
            messages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
            if (messages.length > 100)
              messages.removeRange(0, messages.length - 100);
          }
          messagesByRoom[roomId] = messages;
        }
      case 'session.updated':
        if (roomId != null) {
          final session = StudySessionState.fromJson(event.payload);
          final sessions = sessionsByRoom[roomId] ?? <StudySessionState>[];
          sessions.removeWhere((item) => item.id == session.id);
          if (session.status != StudySessionStatus.finished)
            sessions.add(session);
          sessionsByRoom[roomId] = sessions;
        }
      case 'join-request.created':
        if (roomId != null && ownerInboxByRoom.containsKey(roomId)) {
          final request = RoomJoinRequest.fromJson(event.payload);
          final requests = ownerInboxByRoom[roomId] ?? <RoomJoinRequest>[];
          _upsertJoinRequest(requests, request);
          ownerInboxByRoom[roomId] = requests;
        }
      case 'join-request.updated':
        final request = RoomJoinRequest.fromJson(event.payload);
        _upsertJoinRequest(myRequests, request);
    }

    return StudyRoomSyncState(
      rooms: rooms,
      activeSessionsByRoom: sessionsByRoom,
      recentMessagesByRoom: messagesByRoom,
      myJoinRequests: myRequests,
      ownerInboxByRoom: ownerInboxByRoom,
      staleRoomIds: state.staleRoomIds,
      personalDataStale: state.personalDataStale,
      lastSyncedAt: state.lastSyncedAt,
    );
  }

  static Map<String, List<T>> _copyLists<T>(Map<String, List<T>> source) =>
      source.map((key, value) => MapEntry(key, List<T>.of(value)));

  static void _upsertJoinRequest(
    List<RoomJoinRequest> requests,
    RoomJoinRequest request,
  ) {
    requests.removeWhere((item) => item.id == request.id);
    requests.add(request);
  }

  void _publishSyncState(StudyRoomSyncState state) {
    _syncState = state;
    if (!_syncStates.isClosed) _syncStates.add(state);
  }

  Future<StudyRoom> _subscribe(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    _requireStarted();
    final linked = _linkedCancellation(cancellationToken);
    final room = await rooms.get(roomId, cancellationToken: linked);
    await _connection!.emitWithAck('room.subscribe', {
      'roomId': roomId,
    }, cancellationToken: linked);
    _joinedRoomIds.add(roomId);
    _pendingRoomSeeds[roomId] = room;
    try {
      await resync(cancellationToken: linked);
      return _syncState.rooms[roomId] ?? room;
    } catch (_) {
      try {
        await _connection?.emitWithAck('room.unsubscribe', {'roomId': roomId});
      } catch (_) {
        // The connection may already be closing; reconnect will not restore it.
      }
      _removeRoom(roomId);
      rethrow;
    } finally {
      _pendingRoomSeeds.remove(roomId);
    }
  }

  Future<void> _unsubscribe(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final linked = _linkedCancellation(cancellationToken);
    if (_connectionState == StudyRoomConnectionState.connected ||
        _connectionState == StudyRoomConnectionState.degraded) {
      await _connection?.emitWithAck('room.unsubscribe', {
        'roomId': roomId,
      }, cancellationToken: linked);
    }
    _removeRoom(roomId);
  }

  Future<void> setAway(
    String roomId,
    bool away, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    _requireStarted();
    if (!_joinedRoomIds.contains(roomId)) {
      throw const StudyRoomException(
        'Subscribe to the room before updating presence',
        kind: StudyRoomExceptionKind.validation,
        code: 'subscription_required',
      );
    }
    await _connection!.emitWithAck(
      'presence.set-away',
      {'roomId': roomId, 'away': away},
      cancellationToken: _linkedCancellation(cancellationToken),
    );
  }

  Future<Map<String, dynamic>?> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (_closed) throw _closedError();
    final linked = _linkedCancellation(cancellationToken);
    for (var attempt = 0; attempt < 2; attempt += 1) {
      final token = await _token(
        forceRefresh: attempt == 1,
        cancellationToken: linked,
      );
      try {
        return await _transport.requestJson(
          method,
          path,
          body: body,
          headers: {'Authorization': 'Bearer ${token.value}'},
          cancellationToken: linked,
        );
      } on StudyRoomException catch (error) {
        if (attempt == 0 &&
            error.kind == StudyRoomExceptionKind.authentication) {
          continue;
        }
        rethrow;
      }
    }
    throw StateError('unreachable');
  }

  Future<StudyRoomAccessToken> _token({
    Duration minimumValidity = Duration.zero,
    bool forceRefresh = false,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    _throwIfCancelled(cancellationToken);
    final token = await config.tokenProvider(
      StudyRoomTokenRequest(
        minimumValidity: minimumValidity,
        forceRefresh: forceRefresh,
      ),
    );
    _throwIfCancelled(cancellationToken);
    if (token.value.trim().isEmpty ||
        !token.expiresAt.isAfter(_now.add(minimumValidity))) {
      throw const StudyRoomException(
        'Token provider returned an empty or expiring token',
        kind: StudyRoomExceptionKind.authentication,
        code: 'invalid_token',
      );
    }
    return token;
  }

  StudyRoomCancellationToken _linkedCancellation(
    StudyRoomCancellationToken? cancellationToken,
  ) => StudyRoomCancellationToken.linked([
    _lifecycleCancellation,
    cancellationToken,
  ]);

  static void _throwIfCancelled(StudyRoomCancellationToken? cancellationToken) {
    if (cancellationToken?.isCancelled ?? false) {
      throw const StudyRoomException(
        'Operation was cancelled',
        kind: StudyRoomExceptionKind.cancelled,
        code: 'cancelled',
      );
    }
  }

  void _publishRoom(StudyRoom room) {
    final rooms = Map<String, StudyRoom>.of(_syncState.rooms)..[room.id] = room;
    _publishSyncState(_copySyncState(rooms: rooms));
  }

  void _publishMessage(ChatMessage message) {
    final messages = _copyLists(_syncState.recentMessagesByRoom);
    final roomMessages = messages[message.roomId] ?? <ChatMessage>[];
    if (!roomMessages.any((item) => item.id == message.id)) {
      roomMessages.add(message);
      roomMessages.sort((a, b) => a.sentAt.compareTo(b.sentAt));
      if (roomMessages.length > 100) {
        roomMessages.removeRange(0, roomMessages.length - 100);
      }
    }
    messages[message.roomId] = roomMessages;
    _publishSyncState(_copySyncState(recentMessagesByRoom: messages));
  }

  void _publishSession(StudySessionState session) {
    final sessions = _copyLists(_syncState.activeSessionsByRoom);
    final roomSessions = sessions[session.roomId] ?? <StudySessionState>[];
    roomSessions.removeWhere((item) => item.id == session.id);
    if (session.status != StudySessionStatus.finished)
      roomSessions.add(session);
    sessions[session.roomId] = roomSessions;
    _publishSyncState(_copySyncState(activeSessionsByRoom: sessions));
  }

  void _publishMyRequest(RoomJoinRequest request) {
    final requests = List<RoomJoinRequest>.of(_syncState.myJoinRequests);
    _upsertJoinRequest(requests, request);
    _publishSyncState(_copySyncState(myJoinRequests: requests));
  }

  void _removeOwnerRequest(String roomId, String requestId) {
    final owner = _copyLists(_syncState.ownerInboxByRoom);
    owner[roomId]?.removeWhere((request) => request.id == requestId);
    _publishSyncState(_copySyncState(ownerInboxByRoom: owner));
  }

  StudyRoomSyncState _copySyncState({
    Map<String, StudyRoom>? rooms,
    Map<String, List<StudySessionState>>? activeSessionsByRoom,
    Map<String, List<ChatMessage>>? recentMessagesByRoom,
    List<RoomJoinRequest>? myJoinRequests,
    Map<String, List<RoomJoinRequest>>? ownerInboxByRoom,
  }) => StudyRoomSyncState(
    rooms: rooms ?? _syncState.rooms,
    activeSessionsByRoom:
        activeSessionsByRoom ?? _syncState.activeSessionsByRoom,
    recentMessagesByRoom:
        recentMessagesByRoom ?? _syncState.recentMessagesByRoom,
    myJoinRequests: myJoinRequests ?? _syncState.myJoinRequests,
    ownerInboxByRoom: ownerInboxByRoom ?? _syncState.ownerInboxByRoom,
    staleRoomIds: _syncState.staleRoomIds,
    personalDataStale: _syncState.personalDataStale,
    lastSyncedAt: _syncState.lastSyncedAt,
  );

  void _removeRoom(String roomId, {bool publish = true}) {
    _joinedRoomIds.remove(roomId);
    _pendingRoomSeeds.remove(roomId);
    final rooms = Map<String, StudyRoom>.of(_syncState.rooms)..remove(roomId);
    final sessions = _copyLists(_syncState.activeSessionsByRoom)
      ..remove(roomId);
    final messages = _copyLists(_syncState.recentMessagesByRoom)
      ..remove(roomId);
    final owner = _copyLists(_syncState.ownerInboxByRoom)..remove(roomId);
    final stale = Set<String>.of(_syncState.staleRoomIds)..remove(roomId);
    if (publish) {
      _publishSyncState(
        StudyRoomSyncState(
          rooms: rooms,
          activeSessionsByRoom: sessions,
          recentMessagesByRoom: messages,
          myJoinRequests: _syncState.myJoinRequests,
          ownerInboxByRoom: owner,
          staleRoomIds: stale,
          personalDataStale: _syncState.personalDataStale,
          lastSyncedAt: _syncState.lastSyncedAt,
        ),
      );
    }
  }

  void _requireStarted() {
    if (!_started || _connection == null) {
      throw const StudyRoomException(
        'Call StudyRoomSdk.start() before using realtime features',
        kind: StudyRoomExceptionKind.configuration,
        code: 'sdk_not_started',
      );
    }
  }

  void _ensureGeneration(int generation) {
    if (_closed || generation != _generation) throw _closedError();
  }

  void _setState(StudyRoomConnectionState state) {
    if (_connectionState == state) return;
    _connectionState = state;
    if (!_states.isClosed) _states.add(state);
  }

  void _addEventError(Object error, [StackTrace? stackTrace]) {
    if (!_events.isClosed) _events.addError(error, stackTrace);
  }

  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _started = false;
    _generation += 1;
    _lifecycleCancellation.cancel();
    _refreshTimer?.cancel();
    _reconnectTimer?.cancel();
    await _detachRealtime();
    try {
      await _lifecycleTask;
    } catch (_) {
      // Closing deliberately cancels any in-flight lifecycle operation.
    }
    await _transport.close();
    _setState(StudyRoomConnectionState.stopped);
    await _events.close();
    await _states.close();
    await _syncStates.close();
  }

  static void _validateUri(Uri uri, Set<String> schemes, String field) {
    if (!schemes.contains(uri.scheme) || uri.host.isEmpty) {
      throw StudyRoomException(
        'Invalid $field: $uri',
        kind: StudyRoomExceptionKind.configuration,
        code: 'invalid_config',
      );
    }
  }

  StudyRoomException _closedError() => const StudyRoomException(
    'StudyRoomSdk is closed',
    kind: StudyRoomExceptionKind.configuration,
    code: 'sdk_closed',
  );
}

String _segment(String value) => Uri.encodeComponent(value);

String _withQuery(String path, Map<String, String?> values) {
  final query = values.entries
      .where((entry) => entry.value != null)
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value!)}',
      )
      .join('&');
  return query.isEmpty ? path : '$path?$query';
}

class StudyRoomsApi {
  StudyRoomsApi._(this._sdk);
  final StudyRoomSdk _sdk;

  Future<StudyRoom> create(
    String title, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'POST',
      '/v1/rooms',
      body: {'title': title.trim()},
      cancellationToken: cancellationToken,
    );
    return StudyRoom.fromJson(value!);
  }

  Future<StudyRoomPage<StudyRoom>> list({
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms', {'cursor': cursor, 'limit': '$limit'}),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.roomsFromJson(value!);
  }

  Future<StudyRoom> get(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      '/v1/rooms/${_segment(roomId)}',
      cancellationToken: cancellationToken,
    );
    return StudyRoom.fromJson(value!);
  }

  Future<StudyRoom> subscribe(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) => _sdk._subscribe(roomId, cancellationToken: cancellationToken);

  Future<void> unsubscribe(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) => _sdk._unsubscribe(roomId, cancellationToken: cancellationToken);

  Future<void> delete(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    await _sdk._request(
      'DELETE',
      '/v1/rooms/${_segment(roomId)}',
      cancellationToken: cancellationToken,
    );
    await _sdk._unsubscribe(roomId, cancellationToken: cancellationToken);
  }
}

class StudyJoinRequestsApi {
  StudyJoinRequestsApi._(this._sdk);
  final StudyRoomSdk _sdk;

  Future<RoomJoinRequest> request(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'POST',
      '/v1/rooms/${_segment(roomId)}/join-requests',
      cancellationToken: cancellationToken,
    );
    final request = RoomJoinRequest.fromJson(value!);
    _sdk._publishMyRequest(request);
    return request;
  }

  Future<StudyRoomPage<RoomJoinRequest>> mine({
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/join-requests', {'cursor': cursor, 'limit': '$limit'}),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.joinRequestsFromJson(value!);
  }

  Future<StudyRoomPage<RoomJoinRequest>> forRoom(
    String roomId, {
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms/${_segment(roomId)}/join-requests', {
        'cursor': cursor,
        'limit': '$limit',
      }),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.joinRequestsFromJson(value!);
  }

  Future<void> cancel(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    await _sdk._request(
      'DELETE',
      '/v1/rooms/${_segment(roomId)}/join-requests',
      cancellationToken: cancellationToken,
    );
    final requests = _sdk._syncState.myJoinRequests
        .where((request) => request.roomId != roomId)
        .toList(growable: false);
    _sdk._publishSyncState(_sdk._copySyncState(myJoinRequests: requests));
  }

  Future<RoomJoinRequest> decide(
    String roomId,
    String requestId,
    JoinRequestStatus decision, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (decision != JoinRequestStatus.approved &&
        decision != JoinRequestStatus.rejected) {
      throw const StudyRoomException(
        'Decision must be approved or rejected',
        kind: StudyRoomExceptionKind.validation,
        code: 'invalid_decision',
      );
    }
    final value = await _sdk._request(
      'PATCH',
      '/v1/rooms/${_segment(roomId)}/join-requests/${_segment(requestId)}',
      body: {'decision': decision.name},
      cancellationToken: cancellationToken,
    );
    final request = RoomJoinRequest.fromJson(value!);
    _sdk._removeOwnerRequest(roomId, requestId);
    return request;
  }
}

class StudyMembersApi {
  StudyMembersApi._(this._sdk);
  final StudyRoomSdk _sdk;

  Future<void> leave(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    await _sdk._request(
      'DELETE',
      '/v1/rooms/${_segment(roomId)}/members/me',
      cancellationToken: cancellationToken,
    );
    await _sdk._unsubscribe(roomId, cancellationToken: cancellationToken);
  }

  Future<void> remove(
    String roomId,
    String userId, {
    StudyRoomCancellationToken? cancellationToken,
  }) => _sdk._request(
    'DELETE',
    '/v1/rooms/${_segment(roomId)}/members/${_segment(userId)}',
    cancellationToken: cancellationToken,
  );

  Future<StudyRoom> transferOwnership(
    String roomId,
    String userId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'PUT',
      '/v1/rooms/${_segment(roomId)}/owner',
      body: {'userId': userId},
      cancellationToken: cancellationToken,
    );
    final room = StudyRoom.fromJson(value!);
    _sdk._publishRoom(room);
    return room;
  }
}

class StudySessionsApi {
  StudySessionsApi._(this._sdk);
  final StudyRoomSdk _sdk;

  Future<StudyRoomPage<StudySessionState>> listActive(
    String roomId, {
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms/${_segment(roomId)}/active-sessions', {
        'cursor': cursor,
        'limit': '$limit',
      }),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.sessionsFromJson(value!);
  }

  Future<StudySessionState> start(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'POST',
      '/v1/rooms/${_segment(roomId)}/sessions',
      cancellationToken: cancellationToken,
    );
    final session = StudySessionState.fromJson(value!);
    _sdk._publishSession(session);
    return session;
  }

  Future<StudySessionState> update(
    String sessionId,
    StudySessionStatus status, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (status == StudySessionStatus.idle) {
      throw const StudyRoomException(
        'Idle is not a persisted session state',
        kind: StudyRoomExceptionKind.validation,
        code: 'invalid_session_status',
      );
    }
    final value = await _sdk._request(
      'PATCH',
      '/v1/sessions/${_segment(sessionId)}',
      body: {'status': status.name},
      cancellationToken: cancellationToken,
    );
    final session = StudySessionState.fromJson(value!);
    _sdk._publishSession(session);
    return session;
  }
}

class StudyChatApi {
  StudyChatApi._(this._sdk);
  final StudyRoomSdk _sdk;

  Future<StudyRoomPage<ChatMessage>> history(
    String roomId, {
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms/${_segment(roomId)}/messages', {
        'cursor': cursor,
        'limit': '$limit',
      }),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.messagesFromJson(value!);
  }

  Future<ChatMessage> send(
    String roomId,
    String text, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > 2000) {
      throw const StudyRoomException(
        'Message must contain 1 to 2000 characters',
        kind: StudyRoomExceptionKind.validation,
        code: 'invalid_message',
      );
    }
    final value = await _sdk._request(
      'POST',
      '/v1/rooms/${_segment(roomId)}/messages',
      body: {'text': normalized},
      cancellationToken: cancellationToken,
    );
    final message = ChatMessage.fromJson(value!);
    _sdk._publishMessage(message);
    return message;
  }
}
