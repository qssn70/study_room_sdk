part of 'sdk.dart';

/// Main SDK lifecycle, REST API facade, realtime connection, and sync cache.
///
/// Call [start] before realtime operations. [close] is idempotent and terminal:
/// after closing, create a new instance rather than reusing this one. Pending
/// operations can be cancelled with [StudyRoomCancellationToken]. Temporary
/// connection loss triggers bounded reconnect and authoritative resynchronization.
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
  final _seenEventIds = <String>{};
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

  /// Validated realtime events plus asynchronous lifecycle errors.
  Stream<StudyRoomRealtimeEvent> get events => _events.stream;

  /// Connection states, beginning with the current state for each listener.
  Stream<StudyRoomConnectionState> get connectionStates async* {
    yield _connectionState;
    yield* _states.stream;
  }

  /// Latest immutable authoritative cache snapshot.
  StudyRoomSyncState get syncState => _syncState;

  /// Cache snapshots, beginning with [syncState] for each listener.
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

  /// Starts token acquisition, realtime connection, and initial synchronization.
  ///
  /// Repeated calls while started wait for the same lifecycle work. Cancelling
  /// the supplied token aborts this start attempt without closing the SDK.
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

  /// Rebuilds the local cache from REST while buffering and replaying events.
  ///
  /// Reconnects perform this synchronization automatically. Call this method
  /// when the host wants an explicit authoritative refresh.
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
    bool ignoreRealtimeError = false,
  }) async {
    final linked = _linkedCancellation(cancellationToken);
    Object? realtimeError;
    StackTrace? realtimeStackTrace;
    try {
      if (_connectionState == StudyRoomConnectionState.connected ||
          _connectionState == StudyRoomConnectionState.degraded) {
        await _connection?.emitWithAck('room.unsubscribe', {
          'roomId': roomId,
        }, cancellationToken: linked);
      }
    } catch (error, stackTrace) {
      realtimeError = error;
      realtimeStackTrace = stackTrace;
    } finally {
      // Local eviction is authoritative even when the realtime ACK is lost.
      _removeRoom(roomId);
    }
    if (!ignoreRealtimeError && realtimeError != null) {
      Error.throwWithStackTrace(realtimeError, realtimeStackTrace!);
    }
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
    Map<String, String> headers = const {},
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
          headers: {'Authorization': 'Bearer ${token.token}', ...headers},
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
    if (token.token.trim().isEmpty ||
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

  /// Permanently stops reconnects and refreshes and releases owned transports.
  ///
  /// This method is idempotent. It cancels pending SDK operations and closes
  /// all public streams; a closed instance cannot be started again.
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
