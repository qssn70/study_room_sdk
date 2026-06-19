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

  void joinRoom({required String appId, required String roomId});

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

  void connect() {
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
  void joinRoom({required String appId, required String roomId}) {
    _socket.emit('room.join', {'appId': appId, 'roomId': roomId});
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
  final _chatMessagesController = StreamController<ChatMessage>.broadcast();
  final _sessionEventsController =
      StreamController<StudySessionState>.broadcast();
  StreamSubscription<Map<String, dynamic>>? _realtimeSubscription;
  StudyRoomRealtimeConnection? _realtimeConnection;
  StudyRoom? _latestRoom;

  Stream<StudyRoom> get roomStateStream async* {
    final latest = _latestRoom;
    if (latest != null) {
      yield latest;
    }
    yield* _roomStateController.stream;
  }

  Stream<StudyMember> get memberEventsStream => _memberEventsController.stream;
  Stream<ChatMessage> get chatMessagesStream => _chatMessagesController.stream;
  Stream<StudySessionState> get sessionEventsStream =>
      _sessionEventsController.stream;

  Future<StudyRoom> joinRoom(String roomId) async {
    final headers = await _authHeaders();
    final json = await _transport.postJson(
      '/rooms/$roomId/join',
      headers: headers,
    );
    final room = StudyRoom.fromJson(json);
    _latestRoom = room;
    _roomStateController.add(room);
    await _connectRealtime(room);
    return room;
  }

  Future<void> leaveRoom(String roomId) async {
    final headers = await _authHeaders();
    await _transport.postJson('/rooms/$roomId/leave', headers: headers);
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
    if (_realtimeSubscription != null) {
      return;
    }
    final token = await _config.tokenProvider();
    _realtimeConnection = connector.connect(_config.realtimeUrl, token: token);
    _realtimeSubscription = _realtimeConnection!.events.listen(
      _handleRealtimeEvent,
    );
    if (room.appId.isNotEmpty) {
      _realtimeConnection!.joinRoom(appId: room.appId, roomId: room.id);
    }
  }

  void _handleRealtimeEvent(Map<String, dynamic> event) {
    switch (event['type']) {
      case 'room.state':
        final room = StudyRoom.fromJson(
          event['payload'] as Map<String, dynamic>,
        );
        _latestRoom = room;
        _roomStateController.add(room);
      case 'member.updated':
        _memberEventsController.add(
          StudyMember.fromJson(event['payload'] as Map<String, dynamic>),
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
       config = config ?? PomodoroConfig(),
       _now = now ?? DateTime.now {
    state = PomodoroState.initial(this.config);
  }

  final StudyStore _store;
  final PomodoroConfig config;
  final DateTime Function() _now;
  final _states = StreamController<PomodoroState>.broadcast();
  Timer? _timer;
  DateTime? _stageStartedAt;

  late PomodoroState state;

  Stream<PomodoroState> get states async* {
    yield state;
    yield* _states.stream;
  }

  void start() {
    if (state.status == PomodoroStatus.focusing ||
        state.status == PomodoroStatus.breaking) {
      return;
    }
    _beginStage(PomodoroStatus.focusing, config.focusDuration);
  }

  void pause() {
    if (state.status != PomodoroStatus.focusing &&
        state.status != PomodoroStatus.breaking) {
      return;
    }
    _timer?.cancel();
    final startedAt = _stageStartedAt;
    final elapsed = startedAt == null
        ? Duration.zero
        : _now().difference(startedAt);
    final remaining = state.remaining - elapsed;
    _emit(
      state.copyWith(
        status: PomodoroStatus.paused,
        remaining: remaining > Duration.zero ? remaining : Duration.zero,
        previousStatus: state.status,
      ),
    );
  }

  void resume() {
    if (state.status != PomodoroStatus.paused) {
      return;
    }
    _beginStage(
      state.previousStatus ?? PomodoroStatus.focusing,
      state.remaining,
    );
  }

  void end() {
    _timer?.cancel();
    _stageStartedAt = null;
    _emit(
      state.copyWith(
        status: PomodoroStatus.finished,
        remaining: Duration.zero,
        clearPreviousStatus: true,
      ),
    );
  }

  void _beginStage(PomodoroStatus status, Duration duration) {
    _timer?.cancel();
    _stageStartedAt = _now();
    _emit(PomodoroState(status: status, remaining: duration));
    _timer = Timer(duration, () {
      if (status == PomodoroStatus.focusing) {
        _completeFocusStage();
      } else {
        _completeBreakStage();
      }
    });
  }

  Future<void> _completeFocusStage() async {
    await _store.addFocusSession(_now(), config.focusDuration);
    if (config.breakDuration == Duration.zero) {
      _completeBreakStage();
      return;
    }
    _beginStage(PomodoroStatus.breaking, config.breakDuration);
  }

  void _completeBreakStage() {
    _timer?.cancel();
    _stageStartedAt = null;
    _emit(PomodoroState.initial(config));
  }

  void _emit(PomodoroState next) {
    state = next;
    if (!_states.isClosed) {
      _states.add(next);
    }
  }

  void dispose() {
    _timer?.cancel();
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
}

class MemoryStudyStore implements StudyStore {
  final _goals = <String, TodayGoal>{};
  final _records = <String, StudyDayRecord>{};
  final _tasks = <String, List<StudyTaskRecord>>{};

  @override
  Future<TodayGoal> loadTodayGoal(DateTime date) async {
    return _goals[_dateKey(date)] ?? const TodayGoal();
  }

  @override
  Future<void> saveTodayGoal(DateTime date, TodayGoal goal) async {
    _goals[_dateKey(date)] = goal;
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
