import 'dart:async';

import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:test/test.dart';

void main() {
  test(
    'HTTP authentication retries once with a forced token refresh',
    () async {
      final tokenRequests = <StudyRoomTokenRequest>[];
      var calls = 0;
      final transport = TestTransport((
        method,
        path,
        body,
        cancellationToken,
      ) async {
        calls += 1;
        if (calls == 1) {
          throw const StudyRoomException(
            'expired',
            kind: StudyRoomExceptionKind.authentication,
            code: 'token_expired',
          );
        }
        return {'items': <Object>[], 'nextCursor': null};
      });
      final sdk = _sdk(
        transport: transport,
        tokenProvider: (request) async {
          tokenRequests.add(request);
          return _accessToken(request.forceRefresh ? 'fresh' : 'old');
        },
      );

      expect((await sdk.rooms.list()).items, isEmpty);
      expect(tokenRequests.map((request) => request.forceRefresh), [
        false,
        true,
      ]);
      expect(calls, 2);
      await sdk.close();
    },
  );

  test(
    'public REST methods pass cancellation and active-session paging',
    () async {
      final transport = TestTransport((
        method,
        path,
        body,
        cancellationToken,
      ) async {
        expect(cancellationToken, isNotNull);
        return {
          'items': [_sessionJson()],
          'nextCursor': null,
        };
      });
      final sdk = _sdk(transport: transport);
      final cancellation = StudyRoomCancellationToken();

      final page = await sdk.sessions.listActive(
        'room/1',
        cursor: 'cursor/1',
        limit: 25,
        cancellationToken: cancellation,
      );
      expect(page.items.single.id, 'session-1');
      expect(
        transport.paths.single,
        '/v1/rooms/room%2F1/active-sessions?cursor=cursor%2F1&limit=25',
      );

      cancellation.cancel();
      await expectLater(
        sdk.chat.history('room-1', cancellationToken: cancellation),
        throwsA(
          isA<StudyRoomException>().having(
            (error) => error.kind,
            'kind',
            StudyRoomExceptionKind.cancelled,
          ),
        ),
      );
      await sdk.close();
    },
  );

  test(
    'sync publishes one immutable snapshot and replays buffered events',
    () async {
      var holdRoom = false;
      var failFragments = false;
      var ownerDenied = false;
      Completer<Map<String, dynamic>?>? heldRoom;
      Completer<void>? roomRequested;
      final transport = TestTransport((
        method,
        path,
        body,
        cancellationToken,
      ) async {
        if (path.startsWith('/v1/join-requests')) {
          return {
            'items': [_requestJson(id: 'mine-1')],
            'nextCursor': null,
          };
        }
        if (path == '/v1/rooms/room-1') {
          if (holdRoom) {
            heldRoom = Completer<Map<String, dynamic>?>();
            roomRequested?.complete();
            return heldRoom!.future;
          }
          return _roomJson();
        }
        if (path.contains('/active-sessions')) {
          if (failFragments) {
            throw const StudyRoomException(
              'offline fragment',
              kind: StudyRoomExceptionKind.network,
              code: 'network_error',
            );
          }
          return {
            'items': [_sessionJson()],
            'nextCursor': null,
          };
        }
        if (path.contains('/messages')) {
          if (failFragments) {
            throw const StudyRoomException(
              'server fragment',
              kind: StudyRoomExceptionKind.server,
              code: 'server_error',
            );
          }
          return {
            'items': [_messageJson(id: 'old-message', text: 'old')],
            'nextCursor': null,
          };
        }
        if (path.contains('/join-requests')) {
          if (ownerDenied) {
            throw const StudyRoomException(
              'no longer owner',
              kind: StudyRoomExceptionKind.authorization,
              code: 'forbidden',
            );
          }
          if (failFragments) {
            throw const StudyRoomException(
              'owner fragment limited',
              kind: StudyRoomExceptionKind.rateLimited,
              code: 'rate_limited',
            );
          }
          return {
            'items': [_requestJson(id: 'owner-1')],
            'nextCursor': null,
          };
        }
        throw StateError('Unexpected request: $method $path');
      });
      final realtime = QueueRealtimeConnector();
      final sdk = _sdk(
        transport: transport,
        realtimeConnector: realtime,
        reconnectBaseDelay: const Duration(hours: 1),
      );

      await sdk.start();
      await sdk.rooms.subscribe('room-1');
      expect(sdk.syncState.rooms.keys, ['room-1']);
      expect(sdk.syncState.activeSessionsByRoom['room-1'], hasLength(1));
      expect(sdk.syncState.recentMessagesByRoom['room-1']!.single.text, 'old');
      expect(sdk.syncState.myJoinRequests.single.id, 'mine-1');
      expect(sdk.syncState.ownerInboxByRoom['room-1']!.single.id, 'owner-1');
      expect(() => sdk.syncState.rooms.clear(), throwsUnsupportedError);

      holdRoom = true;
      roomRequested = Completer<void>();
      final published = <StudyRoomSyncState>[];
      final subscription = sdk.syncStates.listen(published.add);
      await Future<void>.delayed(Duration.zero);
      final resync = sdk.resync();
      await roomRequested.future;
      final event = _event(
        'chat.message.created',
        _messageJson(id: 'new-message', text: 'new'),
        eventId: 'buffered-event',
      );
      realtime.connections.single.eventController.add(event);
      realtime.connections.single.eventController.add(event);
      await Future<void>.delayed(Duration.zero);
      heldRoom!.complete(_roomJson());
      await resync;
      await Future<void>.delayed(Duration.zero);

      expect(
        sdk.syncState.recentMessagesByRoom['room-1']!.map(
          (message) => message.text,
        ),
        ['old', 'new'],
      );
      expect(
        published.where(
          (state) =>
              state.recentMessagesByRoom['room-1']?.any(
                (message) => message.id == 'new-message',
              ) ??
              false,
        ),
        hasLength(1),
      );

      holdRoom = false;
      ownerDenied = true;
      await sdk.resync();
      expect(sdk.syncState.ownerInboxByRoom.containsKey('room-1'), isFalse);
      expect(sdk.syncState.isDegraded, isFalse);
      ownerDenied = false;
      await sdk.resync();
      expect(sdk.syncState.ownerInboxByRoom['room-1'], hasLength(1));

      failFragments = true;
      await sdk.resync();
      expect(sdk.syncState.isDegraded, isTrue);
      expect(sdk.syncState.staleRoomIds, {'room-1'});
      expect(sdk.roomSnapshot('room-1'), isNotNull);
      expect(sdk.syncState.activeSessionsByRoom['room-1'], hasLength(1));
      expect(sdk.syncState.recentMessagesByRoom['room-1']!.single.text, 'old');
      expect(sdk.syncState.ownerInboxByRoom['room-1']!.single.id, 'owner-1');
      expect(
        await sdk.connectionStates.first,
        StudyRoomConnectionState.degraded,
      );

      await subscription.cancel();
      await sdk.close();
    },
  );

  test(
    'session, chat, request, and revocation events update the cache',
    () async {
      final transport = _syncTransport();
      final realtime = QueueRealtimeConnector();
      final sdk = _sdk(transport: transport, realtimeConnector: realtime);
      await sdk.start();
      await sdk.rooms.subscribe('room-1');
      final connection = realtime.connections.single;

      connection.eventController.add(
        _event('session.updated', {
          ..._sessionJson(),
          'status': 'finished',
          'finishedAt': '2026-08-09T00:20:00Z',
        }),
      );
      connection.eventController.add(
        _event('join-request.created', _requestJson(id: 'owner-new')),
      );
      connection.eventController.add(
        _event('join-request.updated', {
          ..._requestJson(id: 'mine-1'),
          'status': 'approved',
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sdk.syncState.activeSessionsByRoom['room-1'], isEmpty);
      expect(sdk.syncState.ownerInboxByRoom['room-1']!.last.id, 'owner-new');
      expect(
        sdk.syncState.myJoinRequests.single.status,
        JoinRequestStatus.approved,
      );

      connection.eventController.add(
        _event('membership.updated', {'roomId': 'room-1', 'active': false}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sdk.roomSnapshot('room-1'), isNull);
      expect(sdk.syncState.recentMessagesByRoom.containsKey('room-1'), isFalse);
      await sdk.close();
    },
  );

  test(
    'concurrent starts share one lifecycle and close cancels connect',
    () async {
      final connector = BlockingRealtimeConnector();
      final sdk = _sdk(
        transport: _syncTransport(),
        realtimeConnector: connector,
      );
      final first = sdk.start();
      final second = sdk.start();
      await connector.connectStarted.future;
      expect(connector.connectCount, 1);
      connector.release.complete();
      await Future.wait([first, second]);
      expect(connector.connectCount, 1);
      await sdk.close();

      final cancelledConnector = BlockingRealtimeConnector();
      final closingSdk = _sdk(
        transport: _syncTransport(),
        realtimeConnector: cancelledConnector,
      );
      final starting = closingSdk.start();
      await cancelledConnector.connectStarted.future;
      final closing = closingSdk.close();
      await expectLater(
        starting,
        throwsA(
          isA<StudyRoomException>().having(
            (error) => error.kind,
            'kind',
            StudyRoomExceptionKind.cancelled,
          ),
        ),
      );
      await closing;
      expect(cancelledConnector.connectCount, 1);
    },
  );

  test('auth-expired state reconnects with forceRefresh', () async {
    final requests = <StudyRoomTokenRequest>[];
    final connector = QueueRealtimeConnector();
    final sdk = _sdk(
      transport: _syncTransport(),
      realtimeConnector: connector,
      reconnectBaseDelay: const Duration(milliseconds: 1),
      tokenProvider: (request) async {
        requests.add(request);
        return _accessToken('token-${requests.length}');
      },
    );
    await sdk.start();
    connector.connections.single.stateController.add(
      StudyRoomConnectionState.refreshing,
    );
    await _waitUntil(() => connector.connectCount == 2);

    expect(requests.any((request) => request.forceRefresh), isTrue);
    expect(connector.connections.first.closed, isTrue);
    await sdk.close();
  });

  test('non-owner inbox denial does not revoke room membership', () async {
    final realtime = QueueRealtimeConnector();
    final transport = TestTransport((method, path, body, token) async {
      if (path.startsWith('/v1/join-requests')) {
        return {'items': <Object>[], 'nextCursor': null};
      }
      if (path == '/v1/rooms/room-1') return _roomJson();
      if (path.contains('/active-sessions') || path.contains('/messages')) {
        return {'items': <Object>[], 'nextCursor': null};
      }
      if (path.contains('/join-requests')) {
        throw const StudyRoomException(
          'owner only',
          kind: StudyRoomExceptionKind.authorization,
          code: 'forbidden',
        );
      }
      throw StateError('Unexpected request: $method $path');
    });
    final sdk = _sdk(transport: transport, realtimeConnector: realtime);
    await sdk.start();
    await sdk.rooms.subscribe('room-1');

    expect(sdk.roomSnapshot('room-1'), isNotNull);
    expect(sdk.syncState.ownerInboxByRoom.containsKey('room-1'), isFalse);
    realtime.connections.single.eventController.add(
      _event('join-request.created', _requestJson(id: 'member-must-ignore')),
    );
    await Future<void>.delayed(Duration.zero);
    expect(sdk.syncState.ownerInboxByRoom.containsKey('room-1'), isFalse);
    await sdk.close();
  });

  test('personal sync failure degrades and a room 403 revokes cache', () async {
    var personalFails = true;
    var roomRevoked = false;
    var fragmentDenied = false;
    final transport = TestTransport((method, path, body, token) async {
      if (path.startsWith('/v1/join-requests')) {
        if (personalFails) {
          throw const StudyRoomException(
            'offline',
            kind: StudyRoomExceptionKind.network,
            code: 'network_error',
          );
        }
        return {'items': <Object>[], 'nextCursor': null};
      }
      if (path == '/v1/rooms/room-1') {
        if (roomRevoked) {
          throw const StudyRoomException(
            'revoked',
            kind: StudyRoomExceptionKind.authorization,
            code: 'forbidden',
          );
        }
        return _roomJson();
      }
      if (path.contains('/active-sessions') ||
          path.contains('/messages') ||
          path.contains('/join-requests')) {
        if (fragmentDenied && path.contains('/active-sessions')) {
          throw const StudyRoomException(
            'fragment denied',
            kind: StudyRoomExceptionKind.authorization,
            code: 'forbidden',
          );
        }
        return {'items': <Object>[], 'nextCursor': null};
      }
      throw StateError('Unexpected request: $method $path');
    });
    final sdk = _sdk(
      transport: transport,
      reconnectBaseDelay: const Duration(hours: 1),
    );
    await sdk.start();
    expect(sdk.syncState.personalDataStale, isTrue);
    personalFails = false;
    await sdk.rooms.subscribe('room-1');
    expect(sdk.syncState.isDegraded, isFalse);

    fragmentDenied = true;
    await expectLater(
      sdk.resync(),
      throwsA(
        isA<StudyRoomException>().having(
          (error) => error.kind,
          'kind',
          StudyRoomExceptionKind.authorization,
        ),
      ),
    );
    expect(sdk.roomSnapshot('room-1'), isNotNull);
    fragmentDenied = false;

    roomRevoked = true;
    await sdk.resync();
    expect(sdk.roomSnapshot('room-1'), isNull);
    await sdk.close();
  });

  test(
    'room synchronization runs concurrently with a maximum of four',
    () async {
      var delayRoomGets = false;
      var activeRoomGets = 0;
      var maximumRoomGets = 0;
      final transport = TestTransport((method, path, body, token) async {
        if (path.startsWith('/v1/join-requests')) {
          return {'items': <Object>[], 'nextCursor': null};
        }
        if (RegExp(r'^/v1/rooms/room-[0-9]+$').hasMatch(path)) {
          if (delayRoomGets) {
            activeRoomGets += 1;
            if (activeRoomGets > maximumRoomGets)
              maximumRoomGets = activeRoomGets;
            await Future<void>.delayed(const Duration(milliseconds: 10));
            activeRoomGets -= 1;
          }
          return _roomJson(path.split('/').last);
        }
        if (path.contains('/active-sessions') ||
            path.contains('/messages') ||
            path.contains('/join-requests')) {
          return {'items': <Object>[], 'nextCursor': null};
        }
        throw StateError('Unexpected request: $method $path');
      });
      final sdk = _sdk(transport: transport);
      await sdk.start();
      for (var index = 1; index <= 6; index += 1) {
        await sdk.rooms.subscribe('room-$index');
      }

      delayRoomGets = true;
      await sdk.resync();
      expect(maximumRoomGets, 4);
      await sdk.close();
    },
  );

  test('personal join-request synchronization only fetches one page', () async {
    var personalCalls = 0;
    final transport = TestTransport((method, path, body, token) async {
      if (path.startsWith('/v1/join-requests')) {
        personalCalls += 1;
        return {
          'items': [_requestJson(id: 'recent')],
          'nextCursor': 'older-page',
        };
      }
      throw StateError('Unexpected request: $method $path');
    });
    final sdk = _sdk(transport: transport);
    await sdk.start();

    expect(personalCalls, 1);
    expect(sdk.syncState.myJoinRequests.single.id, 'recent');
    await sdk.close();
  });
}

StudyRoomSdk _sdk({
  required StudyRoomTransport transport,
  StudyRoomRealtimeConnector? realtimeConnector,
  StudyRoomTokenProvider? tokenProvider,
  Duration reconnectBaseDelay = const Duration(seconds: 1),
}) => StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('https://example.com'),
    realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
    tokenProvider: tokenProvider ?? (_) async => _accessToken('token'),
    reconnectBaseDelay: reconnectBaseDelay,
    transport: transport,
    realtimeConnector: realtimeConnector ?? QueueRealtimeConnector(),
  ),
);

StudyRoomAccessToken _accessToken(String value) => StudyRoomAccessToken(
  value: value,
  expiresAt: DateTime.now().add(const Duration(hours: 1)),
);

TestTransport _syncTransport() =>
    TestTransport((method, path, body, token) async {
      if (path.startsWith('/v1/join-requests')) {
        return {
          'items': [_requestJson(id: 'mine-1')],
          'nextCursor': null,
        };
      }
      if (path == '/v1/rooms/room-1') return _roomJson();
      if (path.contains('/active-sessions')) {
        return {
          'items': [_sessionJson()],
          'nextCursor': null,
        };
      }
      if (path.contains('/messages')) {
        return {
          'items': [_messageJson(id: 'old-message', text: 'old')],
          'nextCursor': null,
        };
      }
      if (path.contains('/join-requests')) {
        return {'items': <Object>[], 'nextCursor': null};
      }
      throw StateError('Unexpected request: $method $path');
    });

typedef TestHandler =
    Future<Map<String, dynamic>?> Function(
      String method,
      String path,
      Map<String, dynamic>? body,
      StudyRoomCancellationToken? cancellationToken,
    );

class TestTransport implements StudyRoomTransport {
  TestTransport(this.handler);
  final TestHandler handler;
  final paths = <String>[];
  bool closed = false;

  @override
  Future<Map<String, dynamic>?> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    StudyRoomCancellationToken? cancellationToken,
  }) {
    paths.add(path);
    return handler(method, path, body, cancellationToken);
  }

  @override
  Future<void> close() async => closed = true;
}

class QueueRealtimeConnector implements StudyRoomRealtimeConnector {
  final connections = <TestRealtimeConnection>[];
  int get connectCount => connections.length;

  @override
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final connection = TestRealtimeConnection();
    connections.add(connection);
    return connection;
  }
}

class BlockingRealtimeConnector implements StudyRoomRealtimeConnector {
  final connectStarted = Completer<void>();
  final release = Completer<void>();
  var connectCount = 0;

  @override
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    connectCount += 1;
    if (!connectStarted.isCompleted) connectStarted.complete();
    await Future.any<void>([
      release.future,
      if (cancellationToken != null)
        cancellationToken.whenCancelled.then((_) {
          throw const StudyRoomException(
            'cancelled',
            kind: StudyRoomExceptionKind.cancelled,
            code: 'cancelled',
          );
        }),
    ]);
    return TestRealtimeConnection();
  }
}

class TestRealtimeConnection implements StudyRoomRealtimeConnection {
  final eventController = StreamController<Map<String, dynamic>>.broadcast();
  final stateController =
      StreamController<StudyRoomConnectionState>.broadcast();
  final acks = <(String, Map<String, dynamic>)>[];
  bool closed = false;

  @override
  Stream<Map<String, dynamic>> get events => eventController.stream;
  @override
  Stream<StudyRoomConnectionState> get states => stateController.stream;

  @override
  Future<Map<String, dynamic>> emitWithAck(
    String event,
    Map<String, dynamic> data, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (cancellationToken?.isCancelled ?? false) {
      throw const StudyRoomException(
        'cancelled',
        kind: StudyRoomExceptionKind.cancelled,
        code: 'cancelled',
      );
    }
    acks.add((event, data));
    return {'ok': true};
  }

  @override
  Future<void> close() async {
    if (closed) return;
    closed = true;
    await eventController.close();
    await stateController.close();
  }
}

Future<void> _waitUntil(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 2));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) throw TimeoutException('condition');
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
}

Map<String, dynamic> _roomJson([String id = 'room-1']) => {
  'id': id,
  'appId': 'app-1',
  'title': 'Room',
  'version': 3,
  'members': [
    {
      'id': 'user-1',
      'displayName': 'Lin',
      'avatarUrl': '',
      'status': 'online',
      'role': 'owner',
    },
  ],
};

Map<String, dynamic> _requestJson({required String id}) => {
  'id': id,
  'roomId': 'room-1',
  'userId': 'user-2',
  'displayName': 'Ada',
  'status': 'pending',
  'createdAt': '2026-08-09T00:00:00Z',
  'updatedAt': '2026-08-09T00:00:00Z',
};

Map<String, dynamic> _sessionJson() => {
  'id': 'session-1',
  'roomId': 'room-1',
  'userId': 'user-1',
  'status': 'running',
  'startedAt': '2026-08-09T00:00:00Z',
  'finishedAt': null,
  'updatedAt': '2026-08-09T00:00:00Z',
};

Map<String, dynamic> _messageJson({required String id, required String text}) =>
    {
      'id': id,
      'roomId': 'room-1',
      'senderId': 'user-1',
      'senderName': 'Lin',
      'text': text,
      'sentAt': '2026-08-09T00:00:00Z',
    };

Map<String, dynamic> _event(
  String type,
  Map<String, dynamic> payload, {
  String? eventId,
}) => {
  'schemaVersion': 1,
  'eventId': eventId ?? 'event-$type',
  'type': type,
  'roomId': 'room-1',
  'roomVersion': 3,
  'occurredAt': '2026-08-09T00:00:00Z',
  'payload': payload,
};
