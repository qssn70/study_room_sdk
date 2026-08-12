import 'dart:async';

import 'package:socket_io_client/socket_io_client.dart' as io;

import 'errors.dart';
import 'models.dart';
import 'transport.dart';

abstract class StudyRoomRealtimeConnector {
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  });
}

abstract class StudyRoomRealtimeConnection {
  Stream<Map<String, dynamic>> get events;
  Stream<StudyRoomConnectionState> get states;
  Future<Map<String, dynamic>> emitWithAck(
    String event,
    Map<String, dynamic> data, {
    StudyRoomCancellationToken? cancellationToken,
  });
  Future<void> close();
}

// The concrete socket.io adapter is exercised by the two-instance integration test;
// unit coverage starts again at the transport-independent SDK facade.
// coverage:ignore-start
class SocketIoStudyRoomRealtimeConnector implements StudyRoomRealtimeConnector {
  const SocketIoStudyRoomRealtimeConnector({
    this.ackTimeout = const Duration(seconds: 5),
    this.connectTimeout = const Duration(seconds: 10),
  });
  final Duration ackTimeout;
  final Duration connectTimeout;

  static StudyRoomException mapConnectError(Object? error) =>
      _realtimeConnectException(error);

  @override
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
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
          .setAuth({'token': token.token})
          .setAckTimeout(ackTimeout.inMilliseconds)
          .disableAutoConnect()
          .disableReconnection()
          .build(),
    );
    final connection = _SocketIoStudyRoomRealtimeConnection(
      socket,
      connectTimeout: connectTimeout,
    );
    try {
      await connection.connect(cancellationToken: cancellationToken);
      return connection;
    } catch (_) {
      await connection.close();
      rethrow;
    }
  }
}

class _SocketIoStudyRoomRealtimeConnection
    implements StudyRoomRealtimeConnection {
  _SocketIoStudyRoomRealtimeConnection(
    this._socket, {
    required this.connectTimeout,
  });
  final io.Socket _socket;
  final Duration connectTimeout;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final _states = StreamController<StudyRoomConnectionState>.broadcast();
  var _closed = false;

  Future<void> connect({StudyRoomCancellationToken? cancellationToken}) async {
    final ready = Completer<void>();
    _states.add(StudyRoomConnectionState.connecting);
    _socket.onConnect((_) {
      if (!ready.isCompleted) ready.complete();
      if (!_states.isClosed) _states.add(StudyRoomConnectionState.connected);
    });
    _socket.onConnectError((error) {
      if (!ready.isCompleted) {
        ready.completeError(
          SocketIoStudyRoomRealtimeConnector.mapConnectError(error),
        );
      }
    });
    _socket.onDisconnect((_) {
      if (!_states.isClosed) _states.add(StudyRoomConnectionState.disconnected);
    });
    _socket.on('study-room.event', (dynamic value) {
      if (!_events.isClosed && value is Map)
        _events.add(Map<String, dynamic>.from(value));
    });
    _socket.on('study-room.auth-expired', (_) {
      if (!_states.isClosed) _states.add(StudyRoomConnectionState.refreshing);
    });
    _socket.connect();
    try {
      await Future.any<void>([
        ready.future,
        if (cancellationToken != null)
          cancellationToken.whenCancelled.then((_) {
            throw const StudyRoomException(
              'Realtime connection was cancelled',
              kind: StudyRoomExceptionKind.cancelled,
              code: 'cancelled',
            );
          }),
      ]).timeout(connectTimeout);
    } on TimeoutException catch (error) {
      throw StudyRoomException(
        'Realtime connection timed out',
        kind: StudyRoomExceptionKind.timeout,
        code: 'realtime_connect_timeout',
        cause: error,
      );
    }
  }

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  Stream<StudyRoomConnectionState> get states => _states.stream;

  @override
  Future<Map<String, dynamic>> emitWithAck(
    String event,
    Map<String, dynamic> data, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (!_socket.connected) {
      throw const StudyRoomException(
        'Realtime connection is not connected',
        kind: StudyRoomExceptionKind.network,
        code: 'realtime_disconnected',
      );
    }
    try {
      final ack = _socket.emitWithAckAsync(event, data);
      final value = cancellationToken == null
          ? await ack
          : await Future.any<dynamic>([
              ack,
              cancellationToken.whenCancelled.then((_) {
                throw const StudyRoomException(
                  'Realtime operation was cancelled',
                  kind: StudyRoomExceptionKind.cancelled,
                  code: 'cancelled',
                );
              }),
            ]);
      final response = value is Map
          ? Map<String, dynamic>.from(value)
          : <String, dynamic>{};
      if (response['ok'] != true) {
        final error = response['error'] is Map
            ? Map<String, dynamic>.from(response['error'] as Map)
            : const <String, dynamic>{};
        throw StudyRoomException(
          error['message'] as String? ?? 'Realtime operation failed',
          kind: _realtimeErrorKind(error['code'] as String?),
          code: error['code'] as String? ?? 'realtime_error',
          details: error['details'],
        );
      }
      return response;
    } on StudyRoomException {
      rethrow;
    } catch (error) {
      throw StudyRoomException(
        'Realtime acknowledgement timed out',
        kind: StudyRoomExceptionKind.timeout,
        code: 'realtime_ack_timeout',
        cause: error,
      );
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _socket.dispose();
    await _events.close();
    await _states.close();
  }
}

// coverage:ignore-end

StudyRoomException _realtimeConnectException(Object? error) {
  final root = error is Map
      ? Map<String, dynamic>.from(error)
      : const <String, dynamic>{};
  final data = root['data'] is Map
      ? Map<String, dynamic>.from(root['data'] as Map)
      : const <String, dynamic>{};
  var code = (data['code'] ?? root['code'])?.toString();
  final rawMessage =
      (data['message'] ?? root['message'] ?? error)?.toString() ?? '';
  final normalized = rawMessage.toLowerCase();
  if (code == null &&
      (normalized.contains('unauthorized') ||
          normalized.contains('authentication') ||
          normalized.contains('token expired'))) {
    code = 'unauthorized';
  }
  final mapped = _realtimeErrorKind(code);
  final kind = mapped == StudyRoomExceptionKind.protocol
      ? StudyRoomExceptionKind.network
      : mapped;
  return StudyRoomException(
    rawMessage.isEmpty ? 'Realtime connection failed' : rawMessage,
    kind: kind,
    code:
        code ??
        (kind == StudyRoomExceptionKind.authentication
            ? 'realtime_auth_failed'
            : 'realtime_connect_failed'),
    details: data['details'] ?? root['details'],
    cause: error,
  );
}

StudyRoomExceptionKind _realtimeErrorKind(String? code) => switch (code) {
  'invalid_token' ||
  'token_expired' ||
  'unauthorized' => StudyRoomExceptionKind.authentication,
  'forbidden' || 'membership_required' => StudyRoomExceptionKind.authorization,
  'not_found' => StudyRoomExceptionKind.notFound,
  'conflict' => StudyRoomExceptionKind.conflict,
  'rate_limited' => StudyRoomExceptionKind.rateLimited,
  'invalid_request' || 'validation_error' => StudyRoomExceptionKind.validation,
  _ => StudyRoomExceptionKind.protocol,
};
