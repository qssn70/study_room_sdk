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
    _realtimeSubscription =
        _realtimeConnection!.events.listen(_handleRealtimeEvent);
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
