library study_room_sdk;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:socket_io_client/socket_io_client.dart' as io;

typedef TokenProvider = Future<String> Function();

class StudyRoomError implements Exception {
  const StudyRoomError(this.message, {this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => 'StudyRoomError($message)';
}

class StudyRoomConfig {
  const StudyRoomConfig({
    required this.apiBaseUrl,
    required this.realtimeUrl,
    required this.tokenProvider,
    this.transport,
    this.realtimeConnector,
  });

  final Uri apiBaseUrl;
  final Uri realtimeUrl;
  final TokenProvider tokenProvider;
  final StudyRoomTransport? transport;
  final StudyRoomRealtimeConnector? realtimeConnector;
}

class StudyRoomSdk {
  StudyRoomSdk._(this.config)
    : client = StudyRoomClient(
        config: config,
        transport:
            config.transport ?? HttpStudyRoomTransport(config.apiBaseUrl),
      );

  final StudyRoomConfig config;
  final StudyRoomClient client;

  static StudyRoomSdk initialize(StudyRoomConfig config) {
    _validateUrl(config.apiBaseUrl, allowedSchemes: const ['http', 'https']);
    _validateUrl(config.realtimeUrl, allowedSchemes: const ['ws', 'wss']);
    return StudyRoomSdk._(config);
  }

  static void _validateUrl(Uri url, {required List<String> allowedSchemes}) {
    if (!allowedSchemes.contains(url.scheme) || url.host.isEmpty) {
      throw StudyRoomError('Invalid URL: $url', code: 'invalid_config');
    }
  }
}

abstract class StudyRoomTransport {
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> headers = const {},
  });

  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, String> headers = const {},
  });
}

class HttpStudyRoomTransport implements StudyRoomTransport {
  HttpStudyRoomTransport(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.get(_resolve(path), headers: headers);
    return _decode(response);
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, String> headers = const {},
  }) async {
    final response = await _client.post(
      _resolve(path),
      headers: {'Content-Type': 'application/json', ...headers},
      body: jsonEncode(body),
    );
    return _decode(response);
  }

  Uri _resolve(String path) {
    final normalized = path.startsWith('/') ? path.substring(1) : path;
    return baseUrl.resolve(normalized);
  }

  Map<String, dynamic> _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw StudyRoomError(
        'Request failed with status ${response.statusCode}',
        code: 'http_error',
      );
    }
    if (response.body.isEmpty) {
      return <String, dynamic>{};
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) {
      throw const StudyRoomError('Expected a JSON object response');
    }
    return decoded;
  }
}

abstract class StudyRoomRealtimeConnector {
  StudyRoomRealtimeConnection connect(Uri url, {required String token});
}

abstract class StudyRoomRealtimeConnection {
  Stream<Map<String, dynamic>> get events;

  void joinRoom({required String roomId});

  void leaveRoom({required String roomId});

  void updatePresence({required String roomId, required PresenceStatus status});

  Future<void> close();
}

class SocketIoStudyRoomRealtimeConnector implements StudyRoomRealtimeConnector {
  const SocketIoStudyRoomRealtimeConnector();

  @override
  StudyRoomRealtimeConnection connect(Uri url, {required String token}) {
    final socketUrl = url.replace(
      scheme: switch (url.scheme) {
        'wss' => 'https',
        'ws' => 'http',
        _ => url.scheme,
      },
    );
    final socket = io.io(
      socketUrl.toString(),
      io.OptionBuilder()
          .setTransports(['websocket'])
          .setAuth({'token': token})
          .disableAutoConnect()
          .build(),
    );
    return _SocketIoStudyRoomRealtimeConnection(socket)..connect();
  }
}

class _SocketIoStudyRoomRealtimeConnection
    implements StudyRoomRealtimeConnection {
  _SocketIoStudyRoomRealtimeConnection(this._socket);

  final io.Socket _socket;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _joinedRoomIds = <String>{};
  final _presenceByRoom = <String, PresenceStatus>{};

  void connect() {
    _socket.onConnect((_) {
      for (final roomId in _joinedRoomIds) {
        _emitJoin(roomId);
        final status = _presenceByRoom[roomId];
        if (status != null) {
          _emitPresence(roomId, status);
        }
      }
    });
    _socket.on('study-room.event', (dynamic event) {
      if (event is Map) {
        _events.add(Map<String, dynamic>.from(event));
      }
    });
    _socket.connect();
  }

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  void joinRoom({required String roomId}) {
    _joinedRoomIds.add(roomId);
    if (_socket.connected) {
      _emitJoin(roomId);
    }
  }

  @override
  void leaveRoom({required String roomId}) {
    _joinedRoomIds.remove(roomId);
    _presenceByRoom.remove(roomId);
    if (_socket.connected) {
      _socket.emit('room.leave', {'roomId': roomId});
    }
  }

  @override
  void updatePresence({
    required String roomId,
    required PresenceStatus status,
  }) {
    if (status == PresenceStatus.offline) {
      throw const StudyRoomError(
        'Offline presence is controlled by the server',
        code: 'invalid_presence',
      );
    }
    _presenceByRoom[roomId] = status;
    if (_socket.connected) {
      _emitPresence(roomId, status);
    }
  }

  void _emitJoin(String roomId) {
    _socket.emit('room.join', {'roomId': roomId});
  }

  void _emitPresence(String roomId, PresenceStatus status) {
    _socket.emit('presence.update', {'roomId': roomId, 'status': status.name});
  }

  @override
  Future<void> close() async {
    _socket.dispose();
    await _events.close();
  }
}

enum PresenceStatus {
  online,
  focusing,
  idle,
  away,
  offline;

  static PresenceStatus parse(String value) => PresenceStatus.values.firstWhere(
    (status) => status.name == value,
    orElse: () => PresenceStatus.offline,
  );
}

enum StudySessionStatus {
  idle,
  running,
  paused,
  finished;

  static StudySessionStatus parse(String value) =>
      StudySessionStatus.values.firstWhere(
        (status) => status.name == value,
        orElse: () => StudySessionStatus.idle,
      );
}

class StudyMember {
  const StudyMember({
    required this.id,
    required this.displayName,
    required this.avatarUrl,
    required this.status,
  });

  final String id;
  final String displayName;
  final String avatarUrl;
  final PresenceStatus status;

  factory StudyMember.fromJson(Map<String, dynamic> json) {
    return StudyMember(
      id: json['id'] as String,
      displayName: json['displayName'] as String? ?? '',
      avatarUrl: json['avatarUrl'] as String? ?? '',
      status: PresenceStatus.parse(json['status'] as String? ?? 'offline'),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'displayName': displayName,
    'avatarUrl': avatarUrl,
    'status': status.name,
  };
}

class StudyRoomMemberEvent {
  const StudyRoomMemberEvent({required this.roomId, required this.member});

  final String roomId;
  final StudyMember member;
}

class StudyRoom {
  const StudyRoom({
    required this.id,
    required this.title,
    required this.members,
    this.appId = '',
  });

  final String id;
  final String appId;
  final String title;
  final List<StudyMember> members;

  factory StudyRoom.fromJson(Map<String, dynamic> json) {
    return StudyRoom(
      id: json['id'] as String,
      appId: json['appId'] as String? ?? '',
      title: json['title'] as String? ?? 'Room ${json['id']}',
      members: (json['members'] as List<dynamic>? ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(StudyMember.fromJson)
          .toList(growable: false),
    );
  }
}

class StudySessionState {
  const StudySessionState({
    required this.id,
    required this.roomId,
    required this.status,
    this.startedAt,
    this.finishedAt,
  });

  const StudySessionState.idle(String roomId)
    : this(id: '', roomId: roomId, status: StudySessionStatus.idle);

  final String id;
  final String roomId;
  final StudySessionStatus status;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  factory StudySessionState.fromJson(Map<String, dynamic> json) {
    DateTime? parseDate(String key) {
      final value = json[key];
      return value is String ? DateTime.parse(value) : null;
    }

    return StudySessionState(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      status: StudySessionStatus.parse(json['status'] as String? ?? 'idle'),
      startedAt: parseDate('startedAt'),
      finishedAt: parseDate('finishedAt'),
    );
  }
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
    return ChatMessage(
      id: json['id'] as String,
      roomId: json['roomId'] as String,
      senderId: json['senderId'] as String,
      senderName: json['senderName'] as String? ?? '',
      text: json['text'] as String,
      sentAt: DateTime.parse(json['sentAt'] as String),
    );
  }
}

class StudyRoomClient {
  StudyRoomClient({
    required StudyRoomConfig config,
    required StudyRoomTransport transport,
  }) : _config = config,
       _transport = transport;

  final StudyRoomConfig _config;
  final StudyRoomTransport _transport;
  final _roomStateController = StreamController<StudyRoom>.broadcast();
  final _memberEventsController = StreamController<StudyMember>.broadcast();
  final _roomMemberEventsController =
      StreamController<StudyRoomMemberEvent>.broadcast();
  final _chatMessagesController = StreamController<ChatMessage>.broadcast();
  final _sessionEventsController =
      StreamController<StudySessionState>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  StudyRoomRealtimeConnection? _realtimeConnection;
  final _latestRooms = <String, StudyRoom>{};
  final _joinedRoomIds = <String>{};

  Stream<StudyRoom> get roomStateStream async* {
    for (final room in _latestRooms.values) {
      yield room;
    }
    yield* _roomStateController.stream;
  }

  @Deprecated('Use roomMemberEventsStream for room-aware member events.')
  Stream<StudyMember> get memberEventsStream => _memberEventsController.stream;
  Stream<StudyRoomMemberEvent> get roomMemberEventsStream =>
      _roomMemberEventsController.stream;
  Stream<ChatMessage> get chatMessagesStream => _chatMessagesController.stream;
  Stream<StudySessionState> get sessionEventsStream =>
      _sessionEventsController.stream;

  StudyRoom? roomSnapshot(String roomId) => _latestRooms[roomId];

  Stream<StudyRoom> roomStateFor(String roomId) async* {
    final latest = _latestRooms[roomId];
    if (latest != null) {
      yield latest;
    }
    yield* _roomStateController.stream.where((room) => room.id == roomId);
  }

  Stream<StudyRoomMemberEvent> memberEventsFor(String roomId) =>
      _roomMemberEventsController.stream.where(
        (event) => event.roomId == roomId,
      );

  Future<StudyRoom> joinRoom(String roomId) async {
    final headers = await _authHeaders();
    final json = await _transport.postJson(
      '/rooms/$roomId/join',
      headers: headers,
    );
    final room = StudyRoom.fromJson(json);
    _latestRooms[room.id] = room;
    _joinedRoomIds.add(room.id);
    _roomStateController.add(room);
    await _connectRealtime(room);
    return room;
  }

  Future<void> leaveRoom(String roomId) async {
    _realtimeConnection?.leaveRoom(roomId: roomId);
    _joinedRoomIds.remove(roomId);
    _latestRooms.remove(roomId);
    final headers = await _authHeaders();
    await _transport.postJson('/rooms/$roomId/leave', headers: headers);
  }

  void updatePresence(String roomId, PresenceStatus status) {
    if (!_joinedRoomIds.contains(roomId)) {
      throw StudyRoomError(
        'Join room $roomId before updating presence',
        code: 'room_not_joined',
      );
    }
    if (status == PresenceStatus.offline) {
      throw const StudyRoomError(
        'Offline presence is controlled by the server',
        code: 'invalid_presence',
      );
    }
    _realtimeConnection!.updatePresence(roomId: roomId, status: status);
  }

  StudySession session(String roomId) => StudySession(
    roomId: roomId,
    transport: _transport,
    tokenProvider: _config.tokenProvider,
  );

  ChatClient chat(String roomId) => ChatClient(
    roomId: roomId,
    transport: _transport,
    tokenProvider: _config.tokenProvider,
  );

  Future<Map<String, String>> _authHeaders() async {
    final token = await _config.tokenProvider();
    if (token.trim().isEmpty) {
      throw const StudyRoomError('Token provider returned an empty token');
    }
    return {'Authorization': 'Bearer $token'};
  }

  Future<void> _connectRealtime(StudyRoom room) async {
    final connector =
        _config.realtimeConnector ?? const SocketIoStudyRoomRealtimeConnector();
    if (_realtimeSubscription == null) {
      final token = await _config.tokenProvider();
      if (token.trim().isEmpty) {
        throw const StudyRoomError('Token provider returned an empty token');
      }
      _realtimeConnection = connector.connect(
        _config.realtimeUrl,
        token: token,
      );
      _realtimeSubscription = _realtimeConnection!.events.listen(
        _handleRealtimeEvent,
      );
    }
    _realtimeConnection!.joinRoom(roomId: room.id);
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'room.state':
        final room = StudyRoom.fromJson(
          event['payload'] as Map<String, dynamic>,
        );
        _latestRooms[room.id] = room;
        _roomStateController.add(room);
      case 'member.updated':
        final member = StudyMember.fromJson(
          event['payload'] as Map<String, dynamic>,
        );
        final roomId = event['roomId'] as String? ?? '';
        _memberEventsController.add(member);
        _roomMemberEventsController.add(
          StudyRoomMemberEvent(roomId: roomId, member: member),
        );
      case 'chat.message':
        _chatMessagesController.add(
          ChatMessage.fromJson(event['payload'] as Map<String, dynamic>),
        );
      case 'session.updated':
        _sessionEventsController.add(
          StudySessionState.fromJson(event['payload'] as Map<String, dynamic>),
        );
    }
  }

  Future<void> dispose() async {
    await _realtimeSubscription?.cancel();
    await _realtimeConnection?.close();
    await _roomStateController.close();
    await _memberEventsController.close();
    await _roomMemberEventsController.close();
    await _chatMessagesController.close();
    await _sessionEventsController.close();
  }
}

class StudySession {
  StudySession({
    required this.roomId,
    required StudyRoomTransport transport,
    required TokenProvider tokenProvider,
  }) : _transport = transport,
       _tokenProvider = tokenProvider,
       current = StudySessionState.idle(roomId);

  final String roomId;
  final StudyRoomTransport _transport;
  final TokenProvider _tokenProvider;
  StudySessionState current;

  Future<StudySessionState> start() =>
      _transition('/rooms/$roomId/sessions/start');

  Future<StudySessionState> pause() {
    _requireActive();
    return _transition('/sessions/${current.id}/pause');
  }

  Future<StudySessionState> resume() {
    _requireActive();
    return _transition('/sessions/${current.id}/resume');
  }

  Future<StudySessionState> finish() {
    _requireActive();
    return _transition('/sessions/${current.id}/finish');
  }

  Future<StudySessionState> _transition(String path) async {
    final token = await _tokenProvider();
    final json = await _transport.postJson(
      path,
      headers: {'Authorization': 'Bearer $token'},
    );
    current = StudySessionState.fromJson(json);
    return current;
  }

  void _requireActive() {
    if (current.id.isEmpty) {
      throw const StudyRoomError('Study session has not started');
    }
  }
}

class ChatClient {
  ChatClient({
    required this.roomId,
    required StudyRoomTransport transport,
    required TokenProvider tokenProvider,
  }) : _transport = transport,
       _tokenProvider = tokenProvider;

  final String roomId;
  final StudyRoomTransport _transport;
  final TokenProvider _tokenProvider;

  Future<List<ChatMessage>> loadHistory() async {
    final token = await _tokenProvider();
    if (token.trim().isEmpty) {
      throw const StudyRoomError('Token provider returned an empty token');
    }
    final json = await _transport.getJson(
      '/rooms/$roomId/chat',
      headers: {'Authorization': 'Bearer $token'},
    );
    return (json['messages'] as List<dynamic>? ?? const [])
        .whereType<Map<String, dynamic>>()
        .map(ChatMessage.fromJson)
        .toList(growable: false);
  }

  Future<ChatMessage> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw const StudyRoomError('Message text is required');
    }
    final token = await _tokenProvider();
    final json = await _transport.postJson(
      '/rooms/$roomId/chat',
      body: {'text': trimmed},
      headers: {'Authorization': 'Bearer $token'},
    );
    return ChatMessage.fromJson(json);
  }
}

enum PomodoroPreset { twentyFiveFive, fiftyTen, custom }

enum PomodoroStatus { idle, focusing, paused, breaking, finished }

class PomodoroConfig {
  factory PomodoroConfig({
    Duration focusDuration = const Duration(minutes: 25),
    Duration breakDuration = const Duration(minutes: 5),
    PomodoroPreset preset = PomodoroPreset.twentyFiveFive,
  }) {
    _validateDurations(focusDuration, breakDuration);
    return PomodoroConfig._(
      focusDuration: focusDuration,
      breakDuration: breakDuration,
      preset: preset,
    );
  }

  factory PomodoroConfig.fiftyTen() => PomodoroConfig(
    focusDuration: const Duration(minutes: 50),
    breakDuration: const Duration(minutes: 10),
    preset: PomodoroPreset.fiftyTen,
  );

  factory PomodoroConfig.custom({
    required Duration focusDuration,
    required Duration breakDuration,
  }) => PomodoroConfig(
    focusDuration: focusDuration,
    breakDuration: breakDuration,
    preset: PomodoroPreset.custom,
  );

  const PomodoroConfig._({
    required this.focusDuration,
    required this.breakDuration,
    required this.preset,
  });

  final Duration focusDuration;
  final Duration breakDuration;
  final PomodoroPreset preset;

  static void _validateDurations(Duration focus, Duration rest) {
    if (focus <= Duration.zero) {
      throw const StudyRoomError(
        'Focus duration must be greater than zero',
        code: 'invalid_pomodoro_config',
      );
    }
    if (rest < Duration.zero) {
      throw const StudyRoomError(
        'Break duration cannot be negative',
        code: 'invalid_pomodoro_config',
      );
    }
  }
}

class PomodoroState {
  const PomodoroState({
    required this.status,
    required this.remaining,
    this.previousStatus,
  });

  PomodoroState.initial(PomodoroConfig config)
    : this(status: PomodoroStatus.idle, remaining: config.focusDuration);

  final PomodoroStatus status;
  final Duration remaining;
  final PomodoroStatus? previousStatus;

  PomodoroState copyWith({
    PomodoroStatus? status,
    Duration? remaining,
    PomodoroStatus? previousStatus,
    bool clearPreviousStatus = false,
  }) {
    return PomodoroState(
      status: status ?? this.status,
      remaining: remaining ?? this.remaining,
      previousStatus: clearPreviousStatus
          ? null
          : previousStatus ?? this.previousStatus,
    );
  }
}

class PomodoroController {
  PomodoroController({
    required StudyStore store,
    PomodoroConfig? config,
    DateTime Function()? now,
  }) : _store = store,
       _config = config ?? PomodoroConfig(),
       _now = now ?? DateTime.now {
    state = PomodoroState.initial(_config);
  }

  final StudyStore _store;
  PomodoroConfig _config;
  final DateTime Function() _now;
  final _states = StreamController<PomodoroState>.broadcast();
  Timer? _ticker;
  Timer? _completionTimer;
  DateTime? _stageEndsAt;
  var _stageGeneration = 0;
  var _completing = false;
  var _disposed = false;

  late PomodoroState state;

  PomodoroConfig get config => _config;

  Stream<PomodoroState> get states async* {
    yield state;
    yield* _states.stream;
  }

  void start() {
    if (state.status != PomodoroStatus.idle &&
        state.status != PomodoroStatus.finished) {
      return;
    }
    _beginStage(PomodoroStatus.focusing, config.focusDuration);
  }

  void pause() {
    if (state.status != PomodoroStatus.focusing &&
        state.status != PomodoroStatus.breaking) {
      return;
    }
    final previousStatus = state.status;
    final remaining = _remainingNow();
    _cancelStage();
    _emit(
      state.copyWith(
        status: PomodoroStatus.paused,
        remaining: remaining > Duration.zero ? remaining : Duration.zero,
        previousStatus: previousStatus,
      ),
    );
  }

  void resume() {
    if (state.status != PomodoroStatus.paused) {
      return;
    }
    final stage = state.previousStatus ?? PomodoroStatus.focusing;
    if (state.remaining <= Duration.zero) {
      _skipStage(stage);
      return;
    }
    _beginStage(stage, state.remaining);
  }

  void skip() {
    final stage = switch (state.status) {
      PomodoroStatus.focusing || PomodoroStatus.breaking => state.status,
      PomodoroStatus.paused => state.previousStatus,
      _ => null,
    };
    if (stage != null) {
      _skipStage(stage);
    }
  }

  void end() {
    if (state.status == PomodoroStatus.idle ||
        state.status == PomodoroStatus.finished) {
      return;
    }
    _cancelStage();
    _emit(
      state.copyWith(
        status: PomodoroStatus.finished,
        remaining: Duration.zero,
        clearPreviousStatus: true,
      ),
    );
  }

  void setConfig(PomodoroConfig config) {
    if (state.status == PomodoroStatus.focusing ||
        state.status == PomodoroStatus.breaking ||
        state.status == PomodoroStatus.paused) {
      throw const StudyRoomError(
        'Cannot change pomodoro config during an active stage',
        code: 'pomodoro_active',
      );
    }
    _cancelStage();
    _config = config;
    _emit(PomodoroState.initial(config));
  }

  void _beginStage(PomodoroStatus status, Duration duration) {
    _cancelStage();
    final generation = _stageGeneration;
    _completing = false;
    _stageEndsAt = _now().add(duration);
    _emit(PomodoroState(status: status, remaining: duration));
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (generation != _stageGeneration || _disposed) {
        return;
      }
      final remaining = _remainingNow();
      _emit(state.copyWith(remaining: remaining));
      if (remaining <= Duration.zero) {
        unawaited(_completeStage(generation, status));
      }
    });
    _completionTimer = Timer(
      duration,
      () => unawaited(_completeStage(generation, status)),
    );
  }

  Future<void> _completeStage(int generation, PomodoroStatus stage) async {
    if (_disposed || generation != _stageGeneration || _completing) {
      return;
    }
    _completing = true;
    _ticker?.cancel();
    _completionTimer?.cancel();
    _stageEndsAt = null;
    _emit(state.copyWith(remaining: Duration.zero));

    if (stage == PomodoroStatus.focusing) {
      try {
        await _store.addFocusSession(_now(), config.focusDuration);
      } catch (error, stackTrace) {
        if (!_disposed && generation == _stageGeneration) {
          _emit(
            state.copyWith(
              status: PomodoroStatus.finished,
              remaining: Duration.zero,
              clearPreviousStatus: true,
            ),
          );
          if (!_states.isClosed) {
            _states.addError(error, stackTrace);
          }
        }
        return;
      }
      if (_disposed || generation != _stageGeneration) {
        return;
      }
      if (config.breakDuration > Duration.zero) {
        _beginStage(PomodoroStatus.breaking, config.breakDuration);
      } else {
        _resetToIdle();
      }
      return;
    }
    _resetToIdle();
  }

  void _skipStage(PomodoroStatus stage) {
    _cancelStage();
    if (stage == PomodoroStatus.focusing &&
        config.breakDuration > Duration.zero) {
      _beginStage(PomodoroStatus.breaking, config.breakDuration);
    } else {
      _resetToIdle();
    }
  }

  void _resetToIdle() {
    _cancelStage();
    _emit(PomodoroState.initial(config));
  }

  Duration _remainingNow() {
    final endsAt = _stageEndsAt;
    if (endsAt == null) {
      return state.remaining;
    }
    final remaining = endsAt.difference(_now());
    return remaining > Duration.zero ? remaining : Duration.zero;
  }

  void _cancelStage() {
    _stageGeneration += 1;
    _ticker?.cancel();
    _completionTimer?.cancel();
    _ticker = null;
    _completionTimer = null;
    _stageEndsAt = null;
    _completing = false;
  }

  void _emit(PomodoroState next) {
    if (_disposed) {
      return;
    }
    state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _cancelStage();
    _disposed = true;
    _states.close();
  }
}

class TodayGoal {
  const TodayGoal({
    this.text = '',
    this.targetPomodoros,
    this.completed = false,
  });

  final String text;
  final int? targetPomodoros;
  final bool completed;

  TodayGoal copyWith({
    String? text,
    int? targetPomodoros,
    bool? completed,
    bool clearTargetPomodoros = false,
  }) {
    return TodayGoal(
      text: text ?? this.text,
      targetPomodoros: clearTargetPomodoros
          ? null
          : targetPomodoros ?? this.targetPomodoros,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'text': text,
    'targetPomodoros': targetPomodoros,
    'completed': completed,
  };

  factory TodayGoal.fromJson(Map<String, dynamic> json) {
    return TodayGoal(
      text: json['text'] as String? ?? '',
      targetPomodoros: json['targetPomodoros'] as int?,
      completed: json['completed'] as bool? ?? false,
    );
  }
}

class StudyTaskRecord {
  const StudyTaskRecord({
    required this.id,
    required this.title,
    required this.completed,
  });

  final String id;
  final String title;
  final bool completed;

  StudyTaskRecord copyWith({String? id, String? title, bool? completed}) {
    return StudyTaskRecord(
      id: id ?? this.id,
      title: title ?? this.title,
      completed: completed ?? this.completed,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'completed': completed,
  };

  factory StudyTaskRecord.fromJson(Map<String, dynamic> json) {
    return StudyTaskRecord(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      completed: json['completed'] as bool? ?? false,
    );
  }
}

class StudyFocusSettings {
  factory StudyFocusSettings({
    String? soundTrackId,
    double soundVolume = 0.5,
    String? backgroundId,
    double backgroundMaskOpacity = 0.25,
    String? desktopSection,
  }) {
    return StudyFocusSettings._(
      soundTrackId: soundTrackId,
      soundVolume: soundVolume.clamp(0.0, 1.0).toDouble(),
      backgroundId: backgroundId,
      backgroundMaskOpacity: backgroundMaskOpacity.clamp(0.0, 0.85).toDouble(),
      desktopSection: desktopSection,
    );
  }

  const StudyFocusSettings._({
    required this.soundTrackId,
    required this.soundVolume,
    required this.backgroundId,
    required this.backgroundMaskOpacity,
    required this.desktopSection,
  });

  final String? soundTrackId;
  final double soundVolume;
  final String? backgroundId;
  final double backgroundMaskOpacity;
  final String? desktopSection;

  StudyFocusSettings copyWith({
    String? soundTrackId,
    double? soundVolume,
    String? backgroundId,
    double? backgroundMaskOpacity,
    String? desktopSection,
    bool clearSoundTrackId = false,
    bool clearBackgroundId = false,
    bool clearDesktopSection = false,
  }) {
    return StudyFocusSettings(
      soundTrackId: clearSoundTrackId
          ? null
          : soundTrackId ?? this.soundTrackId,
      soundVolume: soundVolume ?? this.soundVolume,
      backgroundId: clearBackgroundId
          ? null
          : backgroundId ?? this.backgroundId,
      backgroundMaskOpacity:
          backgroundMaskOpacity ?? this.backgroundMaskOpacity,
      desktopSection: clearDesktopSection
          ? null
          : desktopSection ?? this.desktopSection,
    );
  }

  Map<String, dynamic> toJson() => {
    'soundTrackId': soundTrackId,
    'soundVolume': soundVolume,
    'backgroundId': backgroundId,
    'backgroundMaskOpacity': backgroundMaskOpacity,
    'desktopSection': desktopSection,
  };

  factory StudyFocusSettings.fromJson(Map<String, dynamic> json) {
    return StudyFocusSettings(
      soundTrackId: json['soundTrackId'] as String?,
      soundVolume: (json['soundVolume'] as num?)?.toDouble() ?? 0.5,
      backgroundId: json['backgroundId'] as String?,
      backgroundMaskOpacity:
          (json['backgroundMaskOpacity'] as num?)?.toDouble() ?? 0.25,
      desktopSection: json['desktopSection'] as String?,
    );
  }
}

enum StudyStoreChangeKind { goal, dayRecord, tasks, settings }

class StudyStoreChange {
  StudyStoreChange(this.kind, {DateTime? date})
    : date = date == null ? null : _dateOnly(date);

  final StudyStoreChangeKind kind;
  final DateTime? date;
}

class StudyDayRecord {
  const StudyDayRecord({
    required this.date,
    this.focusDuration = Duration.zero,
    this.pomodoroCount = 0,
  });

  final DateTime date;
  final Duration focusDuration;
  final int pomodoroCount;

  bool get hasStudied => pomodoroCount > 0 || focusDuration > Duration.zero;

  StudyDayRecord copyWith({
    DateTime? date,
    Duration? focusDuration,
    int? pomodoroCount,
  }) {
    return StudyDayRecord(
      date: date ?? this.date,
      focusDuration: focusDuration ?? this.focusDuration,
      pomodoroCount: pomodoroCount ?? this.pomodoroCount,
    );
  }

  Map<String, dynamic> toJson() => {
    'date': _dateKey(date),
    'focusSeconds': focusDuration.inSeconds,
    'pomodoroCount': pomodoroCount,
  };

  factory StudyDayRecord.fromJson(Map<String, dynamic> json) {
    return StudyDayRecord(
      date: _parseDateKey(json['date'] as String),
      focusDuration: Duration(seconds: json['focusSeconds'] as int? ?? 0),
      pomodoroCount: json['pomodoroCount'] as int? ?? 0,
    );
  }
}

class StudyStats {
  const StudyStats({
    required this.todayFocusDuration,
    required this.todayPomodoroCount,
    required this.streakDays,
    required this.lastSevenDays,
  });

  final Duration todayFocusDuration;
  final int todayPomodoroCount;
  final int streakDays;
  final List<StudyDayRecord> lastSevenDays;
}

enum StudyReportRange { day, week, month }

class StudyReport {
  const StudyReport({
    required this.range,
    required this.startDate,
    required this.endDate,
    required this.days,
    required this.totalFocusDuration,
    required this.totalPomodoroCount,
    required this.streakDays,
    required this.taskCompletionRate,
    required this.summary,
  });

  final StudyReportRange range;
  final DateTime startDate;
  final DateTime endDate;
  final List<StudyDayRecord> days;
  final Duration totalFocusDuration;
  final int totalPomodoroCount;
  final int streakDays;
  final double? taskCompletionRate;
  final String summary;
}

abstract class StudyStore {
  Stream<StudyStoreChange> get changes;

  Future<TodayGoal> loadTodayGoal(DateTime date);

  Future<void> saveTodayGoal(DateTime date, TodayGoal goal);

  Future<StudyDayRecord> loadDayRecord(DateTime date);

  Future<List<StudyDayRecord>> loadDayRecords({
    required DateTime start,
    required DateTime end,
  });

  Future<void> saveDayRecord(StudyDayRecord record);

  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  });

  Future<List<StudyTaskRecord>> loadTaskRecords(DateTime date);

  Future<void> saveTaskRecord(DateTime date, StudyTaskRecord task);

  Future<void> deleteTaskRecord(DateTime date, String taskId);

  Future<StudyFocusSettings> loadSettings();

  Future<void> saveSettings(StudyFocusSettings settings);
}

class MemoryStudyStore implements StudyStore {
  final _goals = <String, TodayGoal>{};
  final _records = <String, StudyDayRecord>{};
  final _tasks = <String, List<StudyTaskRecord>>{};
  final _changes = StreamController<StudyStoreChange>.broadcast(sync: true);
  var _settings = StudyFocusSettings();

  @override
  Stream<StudyStoreChange> get changes => _changes.stream;

  @override
  Future<TodayGoal> loadTodayGoal(DateTime date) async {
    return _goals[_dateKey(date)] ?? const TodayGoal();
  }

  @override
  Future<void> saveTodayGoal(DateTime date, TodayGoal goal) async {
    _goals[_dateKey(date)] = goal;
    _changes.add(StudyStoreChange(StudyStoreChangeKind.goal, date: date));
  }

  @override
  Future<StudyDayRecord> loadDayRecord(DateTime date) async {
    final day = _dateOnly(date);
    return _records[_dateKey(day)] ?? StudyDayRecord(date: day);
  }

  @override
  Future<List<StudyDayRecord>> loadDayRecords({
    required DateTime start,
    required DateTime end,
  }) async {
    final days = <StudyDayRecord>[];
    var cursor = _dateOnly(start);
    final last = _dateOnly(end);
    while (!cursor.isAfter(last)) {
      days.add(await loadDayRecord(cursor));
      cursor = cursor.add(const Duration(days: 1));
    }
    return days;
  }

  @override
  Future<void> saveDayRecord(StudyDayRecord record) async {
    final normalized = record.copyWith(date: _dateOnly(record.date));
    _records[_dateKey(normalized.date)] = normalized;
    _changes.add(
      StudyStoreChange(StudyStoreChangeKind.dayRecord, date: normalized.date),
    );
  }

  @override
  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  }) async {
    final current = await loadDayRecord(date);
    await saveDayRecord(
      current.copyWith(
        focusDuration: current.focusDuration + duration,
        pomodoroCount: current.pomodoroCount + pomodoros,
      ),
    );
  }

  @override
  Future<List<StudyTaskRecord>> loadTaskRecords(DateTime date) async {
    return List.unmodifiable(_tasks[_dateKey(date)] ?? const []);
  }

  @override
  Future<void> saveTaskRecord(DateTime date, StudyTaskRecord task) async {
    final key = _dateKey(date);
    final tasks = List<StudyTaskRecord>.of(_tasks[key] ?? const []);
    final index = tasks.indexWhere((existing) => existing.id == task.id);
    if (index == -1) {
      tasks.add(task);
    } else {
      tasks[index] = task;
    }
    _tasks[key] = tasks;
    _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
  }

  @override
  Future<void> deleteTaskRecord(DateTime date, String taskId) async {
    final key = _dateKey(date);
    final tasks = List<StudyTaskRecord>.of(_tasks[key] ?? const []);
    tasks.removeWhere((task) => task.id == taskId);
    _tasks[key] = tasks;
    _changes.add(StudyStoreChange(StudyStoreChangeKind.tasks, date: date));
  }

  @override
  Future<StudyFocusSettings> loadSettings() async => _settings;

  @override
  Future<void> saveSettings(StudyFocusSettings settings) async {
    _settings = settings;
    _changes.add(StudyStoreChange(StudyStoreChangeKind.settings));
  }
}

class StudyAnalytics {
  const StudyAnalytics(this.store);

  final StudyStore store;

  Future<StudyStats> statsFor(DateTime today) async {
    final day = _dateOnly(today);
    final todayRecord = await store.loadDayRecord(day);
    final lastSevenDays = await store.loadDayRecords(
      start: day.subtract(const Duration(days: 6)),
      end: day,
    );
    return StudyStats(
      todayFocusDuration: todayRecord.focusDuration,
      todayPomodoroCount: todayRecord.pomodoroCount,
      streakDays: await streakDaysEnding(day),
      lastSevenDays: lastSevenDays,
    );
  }

  Future<int> streakDaysEnding(DateTime day) async {
    var streak = 0;
    var cursor = _dateOnly(day);
    while (true) {
      final record = await store.loadDayRecord(cursor);
      if (!record.hasStudied) {
        return streak;
      }
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  double? taskCompletionRate(List<StudyTaskRecord> tasks) {
    if (tasks.isEmpty) {
      return null;
    }
    final completed = tasks.where((task) => task.completed).length;
    return completed / tasks.length;
  }

  Future<StudyReport> report(StudyReportRange range, DateTime anchor) async {
    final anchorDay = _dateOnly(anchor);
    final start = switch (range) {
      StudyReportRange.day => anchorDay,
      StudyReportRange.week => anchorDay.subtract(
        Duration(days: anchorDay.weekday - 1),
      ),
      StudyReportRange.month => DateTime(anchorDay.year, anchorDay.month),
    };
    final end = switch (range) {
      StudyReportRange.day => anchorDay,
      StudyReportRange.week => start.add(const Duration(days: 6)),
      StudyReportRange.month => DateTime(
        anchorDay.year,
        anchorDay.month + 1,
        0,
      ),
    };
    final days = await store.loadDayRecords(start: start, end: end);
    final tasks = <StudyTaskRecord>[];
    var totalFocus = Duration.zero;
    var totalPomodoros = 0;
    for (final day in days) {
      totalFocus += day.focusDuration;
      totalPomodoros += day.pomodoroCount;
      tasks.addAll(await store.loadTaskRecords(day.date));
    }
    final streak = await streakDaysEnding(end);
    return StudyReport(
      range: range,
      startDate: start,
      endDate: end,
      days: days,
      totalFocusDuration: totalFocus,
      totalPomodoroCount: totalPomodoros,
      streakDays: streak,
      taskCompletionRate: taskCompletionRate(tasks),
      summary: _summary(totalFocus, totalPomodoros, streak),
    );
  }

  String _summary(Duration focus, int pomodoros, int streak) {
    if (pomodoros == 0 && focus == Duration.zero) {
      return 'No focus sessions yet.';
    }
    return '${focus.inMinutes} focused minutes, $pomodoros pomodoros, $streak day streak.';
  }
}

DateTime _dateOnly(DateTime date) => DateTime(date.year, date.month, date.day);

String _dateKey(DateTime date) {
  final day = _dateOnly(date);
  final month = day.month.toString().padLeft(2, '0');
  final datePart = day.day.toString().padLeft(2, '0');
  return '${day.year}-$month-$datePart';
}

DateTime _parseDateKey(String key) {
  final parts = key.split('-').map(int.parse).toList(growable: false);
  return DateTime(parts[0], parts[1], parts[2]);
}
