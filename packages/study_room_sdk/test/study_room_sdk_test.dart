import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('access token exposes the public token field', () {
    final accessToken = StudyRoomAccessToken(
      token: 'jwt',
      expiresAt: DateTime.utc(2026, 8, 11, 12),
    );

    expect(accessToken.token, 'jwt');
  });

  test('configuration rejects invalid URLs', () {
    expect(
      () => StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse('localhost:3000'),
          realtimeUri: Uri.parse('ws://localhost:3000/v1/realtime'),
          tokenProvider: _token,
        ),
      ),
      throwsA(isA<StudyRoomException>()),
    );
    expect(
      () => StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse('https://example.com'),
          realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
          tokenProvider: _token,
          realtimeAckTimeout: Duration.zero,
        ),
      ),
      throwsA(isA<StudyRoomException>()),
    );
  });

  test(
    'start, subscribe, presence, and close use explicit lifecycle',
    () async {
      final transport = FakeTransport();
      final realtime = FakeRealtimeConnector();
      final sdk = StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse('https://example.com/api'),
          realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
          tokenProvider: _token,
          transport: transport,
          realtimeConnector: realtime,
        ),
      );
      transport.handler = (method, path, body) async {
        if (path.startsWith('/v1/join-requests') ||
            path.contains('/active-sessions') ||
            path.contains('/messages') ||
            path.contains('/join-requests')) {
          return {'items': <Object>[], 'nextCursor': null};
        }
        return _roomJson('room/with?delimiter');
      };

      await sdk.start();
      final room = await sdk.rooms.subscribe('room/with?delimiter');
      await sdk.setAway(room.id, true);

      expect(
        transport.requests
            .firstWhere((request) => request.path.contains('room%2F'))
            .path,
        '/v1/rooms/room%2Fwith%3Fdelimiter',
      );
      expect(realtime.connection.acks.map((ack) => ack.$1), [
        'room.subscribe',
        'presence.set-away',
      ]);
      expect(realtime.connection.acks[0].$2, {'roomId': room.id});
      expect(realtime.connection.acks[1].$2, {'roomId': room.id, 'away': true});
      await sdk.close();
      expect(transport.closed, isTrue);
      expect(realtime.connection.closed, isTrue);
    },
  );

  test(
    'room, request, member, session, and chat APIs use v1 contract',
    () async {
      final transport = FakeTransport();
      final sdk = StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse('https://example.com'),
          realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
          tokenProvider: _token,
          transport: transport,
          realtimeConnector: FakeRealtimeConnector(),
        ),
      );
      transport.handler = (method, path, body) async {
        if (path == '/v1/rooms' && method == 'POST') return _roomJson('room-1');
        if (path.startsWith('/v1/rooms?'))
          return {
            'items': [_roomJson('room-1')],
            'nextCursor': null,
          };
        if (path.startsWith('/v1/join-requests'))
          return {
            'items': [_requestJson()],
            'nextCursor': null,
          };
        if (path.endsWith('/join-requests') && method == 'POST')
          return _requestJson();
        if (path.contains('/join-requests/') && method == 'PATCH') {
          return {..._requestJson(), 'status': body!['decision']};
        }
        if (path.endsWith('/owner')) return _roomJson('room-1');
        if (path.endsWith('/sessions')) return _sessionJson();
        if (path.startsWith('/v1/sessions/'))
          return {..._sessionJson(), 'status': body!['status']};
        if (path.contains('/messages') && method == 'GET') {
          return {
            'items': [_messageJson()],
            'nextCursor': 'next',
          };
        }
        if (path.contains('/messages') && method == 'POST')
          return _messageJson(text: body!['text'] as String);
        return null;
      };

      expect((await sdk.rooms.create(' Focus ')).title, 'Focus Room');
      expect((await sdk.rooms.list(limit: 25)).items, hasLength(1));
      expect(
        (await sdk.joinRequests.request('room-1')).status,
        JoinRequestStatus.pending,
      );
      expect((await sdk.joinRequests.mine()).items, hasLength(1));
      expect(
        (await sdk.joinRequests.decide(
          'room-1',
          'request-1',
          JoinRequestStatus.approved,
        )).status,
        JoinRequestStatus.approved,
      );
      expect(
        (await sdk.members.transferOwnership('room-1', 'user-2')).version,
        3,
      );
      final session = await sdk.sessions.start('room-1');
      expect(
        (await sdk.sessions.update(
          session.id,
          StudySessionStatus.paused,
        )).status,
        StudySessionStatus.paused,
      );
      expect((await sdk.chat.history('room-1')).nextCursor, 'next');
      expect((await sdk.chat.send('room-1', ' hello ')).text, 'hello');
      await sdk.close();
    },
  );

  test(
    'unsubscribe evicts room state even when the realtime ack fails',
    () async {
      final fixture = await _subscribedSdkFixture();
      addTearDown(fixture.sdk.close);
      _expectRoomCachePresent(fixture.sdk);
      fixture.realtime.connection.failEvent = 'room.unsubscribe';

      await expectLater(
        fixture.sdk.rooms.unsubscribe('room-1'),
        throwsA(
          isA<StateError>().having(
            (error) => error.message,
            'message',
            'room.unsubscribe failed',
          ),
        ),
      );

      expect(
        fixture.realtime.connection.acks.where(
          (ack) => ack.$1 == 'room.unsubscribe',
        ),
        hasLength(1),
      );
      _expectRoomCacheEvicted(fixture.sdk);
    },
  );

  for (final operation in ['leave', 'delete']) {
    test(
      '$operation succeeds and evicts room state when the realtime ack fails',
      () async {
        final fixture = await _subscribedSdkFixture();
        addTearDown(fixture.sdk.close);
        _expectRoomCachePresent(fixture.sdk);
        fixture.realtime.connection.failEvent = 'room.unsubscribe';

        if (operation == 'leave') {
          await fixture.sdk.members.leave('room-1');
          expect(
            fixture.transport.requests,
            contains(
              isA<_Request>()
                  .having((request) => request.method, 'method', 'DELETE')
                  .having(
                    (request) => request.path,
                    'path',
                    '/v1/rooms/room-1/members/me',
                  ),
            ),
          );
        } else {
          await fixture.sdk.rooms.delete('room-1');
          expect(
            fixture.transport.requests,
            contains(
              isA<_Request>()
                  .having((request) => request.method, 'method', 'DELETE')
                  .having(
                    (request) => request.path,
                    'path',
                    '/v1/rooms/room-1',
                  ),
            ),
          );
        }

        expect(fixture.realtime.connection.acks.last.$1, 'room.unsubscribe');
        expect(fixture.realtime.connection.acks.last.$2, {'roomId': 'room-1'});
        expect(
          fixture.realtime.connection.acks.where(
            (ack) => ack.$1 == 'room.unsubscribe',
          ),
          hasLength(1),
        );
        _expectRoomCacheEvicted(fixture.sdk);
      },
    );
  }

  test(
    'HTTP transport preserves base path and decodes structured errors',
    () async {
      final client = MockClient((request) async {
        expect(request.url.toString(), 'https://example.com/api/v1/rooms');
        return http.Response(
          jsonEncode({
            'code': 'conflict',
            'message': 'Already exists',
            'requestId': 'req-1',
          }),
          409,
          headers: {'content-type': 'application/json'},
        );
      });
      final transport = HttpStudyRoomTransport(
        Uri.parse('https://example.com/api'),
        timeout: const Duration(seconds: 1),
        client: client,
      );
      await expectLater(
        transport.requestJson('GET', '/v1/rooms'),
        throwsA(
          isA<StudyRoomException>()
              .having(
                (error) => error.kind,
                'kind',
                StudyRoomExceptionKind.conflict,
              )
              .having((error) => error.requestId, 'requestId', 'req-1'),
        ),
      );
      await transport.close();
    },
  );

  test('realtime events reject unsupported schema versions', () {
    expect(
      () => StudyRoomRealtimeEvent.fromJson({
        'schemaVersion': 2,
        'eventId': 'event-1',
        'type': 'room.state',
        'occurredAt': DateTime.now().toIso8601String(),
        'payload': <String, dynamic>{},
      }),
      throwsA(isA<StudyRoomException>()),
    );
  });

  group('HTTP transport failure semantics', () {
    test(
      'decodes empty responses and all structured status categories',
      () async {
        final client = MockClient((request) async {
          final status = int.parse(request.url.pathSegments.last);
          if (status == 204) return http.Response('', status);
          return http.Response(
            jsonEncode({
              'code': 'status_$status',
              'message': 'failed',
              'details': {'status': status},
            }),
            status,
          );
        });
        final transport = HttpStudyRoomTransport(
          Uri.parse('https://example.com'),
          timeout: const Duration(seconds: 1),
          client: client,
        );
        expect(await transport.requestJson('DELETE', '/204'), isNull);
        const expected = {
          400: StudyRoomExceptionKind.validation,
          401: StudyRoomExceptionKind.authentication,
          403: StudyRoomExceptionKind.authorization,
          404: StudyRoomExceptionKind.notFound,
          409: StudyRoomExceptionKind.conflict,
          429: StudyRoomExceptionKind.rateLimited,
          503: StudyRoomExceptionKind.server,
        };
        for (final entry in expected.entries) {
          await expectLater(
            transport.requestJson('GET', '/${entry.key}'),
            throwsA(
              isA<StudyRoomException>()
                  .having((error) => error.kind, 'kind', entry.value)
                  .having((error) => error.details, 'details', {
                    'status': entry.key,
                  }),
            ),
          );
        }
        await transport.close();
        await transport.close();
        await expectLater(
          transport.requestJson('GET', '/200'),
          throwsA(
            isA<StudyRoomException>().having(
              (error) => error.code,
              'code',
              'transport_closed',
            ),
          ),
        );
      },
    );

    test(
      'reports invalid JSON, cancellation, timeout, and network errors',
      () async {
        final invalid = HttpStudyRoomTransport(
          Uri.parse('https://example.com/'),
          timeout: const Duration(seconds: 1),
          client: MockClient((_) async => http.Response('[]', 200)),
        );
        await expectLater(
          invalid.requestJson('GET', 'value'),
          throwsA(
            isA<StudyRoomException>().having(
              (error) => error.kind,
              'kind',
              StudyRoomExceptionKind.protocol,
            ),
          ),
        );

        final cancellation = StudyRoomCancellationToken();
        final never = Completer<http.Response>();
        final cancellable = HttpStudyRoomTransport(
          Uri.parse('https://example.com'),
          timeout: const Duration(seconds: 10),
          client: MockClient((_) => never.future),
        );
        final cancelled = cancellable.requestJson(
          'GET',
          '/wait',
          cancellationToken: cancellation,
        );
        expect(cancellation.isCancelled, isFalse);
        cancellation.cancel();
        cancellation.cancel();
        await expectLater(
          cancelled,
          throwsA(
            isA<StudyRoomException>().having(
              (error) => error.kind,
              'kind',
              StudyRoomExceptionKind.cancelled,
            ),
          ),
        );

        final timeout = HttpStudyRoomTransport(
          Uri.parse('https://example.com'),
          timeout: const Duration(milliseconds: 1),
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 20));
            return http.Response('{}', 200);
          }),
        );
        await expectLater(
          timeout.requestJson('GET', '/slow'),
          throwsA(
            isA<StudyRoomException>().having(
              (error) => error.kind,
              'kind',
              StudyRoomExceptionKind.timeout,
            ),
          ),
        );

        final network = HttpStudyRoomTransport(
          Uri.parse('https://example.com'),
          timeout: const Duration(seconds: 1),
          client: MockClient((_) => throw StateError('offline')),
        );
        await expectLater(
          network.requestJson('POST', '/send', body: {'ok': true}),
          throwsA(
            isA<StudyRoomException>().having(
              (error) => error.kind,
              'kind',
              StudyRoomExceptionKind.network,
            ),
          ),
        );
      },
    );
  });

  test('models validate wire data and expose immutable collections', () {
    final members = _roomJson('room-1')['members']! as List<dynamic>;
    final member = StudyMember.fromJson(
      Map<String, dynamic>.from(members.first as Map),
    );
    expect(member.toJson(), containsPair('role', 'owner'));
    final room = StudyRoom.fromJson(_roomJson('room-1'));
    expect(() => room.members.add(member), throwsUnsupportedError);
    expect(StudySessionState.idle('room-1').status, StudySessionStatus.idle);
    expect(
      StudySessionState.fromJson({
        ..._sessionJson(),
        'finishedAt': '2026-08-09T01:00:00Z',
      }).finishedAt,
      isNotNull,
    );
    expect(
      () => StudyMember.fromJson({...member.toJson(), 'status': 'unknown'}),
      throwsA(
        isA<StudyRoomException>().having(
          (error) => error.code,
          'code',
          'invalid_enum',
        ),
      ),
    );
    expect(
      () => RoomJoinRequest.fromJson({..._requestJson(), 'createdAt': 'bad'}),
      throwsA(isA<StudyRoomException>()),
    );
    expect(
      () => jsonObject('not-an-object'),
      throwsA(isA<StudyRoomException>()),
    );
    final page = StudyRoomPage.roomsFromJson({
      'items': [_roomJson('room-1')],
      'nextCursor': null,
    });
    expect(() => page.items.clear(), throwsUnsupportedError);
    expect(
      () => StudyRoomPage.roomsFromJson({'nextCursor': null}),
      throwsA(
        isA<StudyRoomException>().having(
          (error) => error.kind,
          'kind',
          StudyRoomExceptionKind.protocol,
        ),
      ),
    );
    final event = StudyRoomRealtimeEvent.fromJson(
      _event('chat.message.created', _messageJson()),
    );
    expect(event.roomVersion, 3);
  });

  test('public model adapters wrap generated wire failures', () {
    final malformedPayloads = <Object Function()>[
      () => StudyMember.fromJson({
        'id': 'user-1',
        'displayName': 'Lin',
        'avatarUrl': '',
        'role': 'owner',
      }),
      () => StudyRoom.fromJson({..._roomJson('room-1')}..remove('members')),
      () => RoomJoinRequest.fromJson({..._requestJson(), 'status': 1}),
      () => ChatMessage.fromJson({..._messageJson()}..remove('senderName')),
      () => StudySessionState.fromJson({..._sessionJson(), 'status': 'idle'}),
      () => StudyRoomRealtimeEvent.fromJson({
        ..._event('chat.message.created', _messageJson()),
        'payload': {'id': 'message-1'},
      }),
    ];

    for (final decode in malformedPayloads) {
      expect(
        decode,
        throwsA(
          isA<StudyRoomException>()
              .having(
                (error) => error.kind,
                'kind',
                StudyRoomExceptionKind.protocol,
              )
              .having((error) => error.cause, 'cause', isNotNull),
        ),
      );
    }
  });

  test('structured exceptions identify retryable failures', () {
    expect(
      const StudyRoomException(
        'slow',
        kind: StudyRoomExceptionKind.timeout,
      ).retryable,
      isTrue,
    );
    expect(
      const StudyRoomException(
        'server',
        kind: StudyRoomExceptionKind.validation,
        statusCode: 500,
      ).retryable,
      isTrue,
    );
    expect(const StudyRoomError('bad', code: 'bad').retryable, isFalse);
    expect(
      const StudyRoomError('bad', code: 'bad').toString(),
      contains('bad'),
    );
  });

  test('realtime connect errors distinguish authentication failures', () {
    final authentication = SocketIoStudyRoomRealtimeConnector.mapConnectError({
      'message': 'denied',
      'data': {
        'code': 'invalid_token',
        'details': {'reason': 'expired'},
      },
    });
    expect(authentication.kind, StudyRoomExceptionKind.authentication);
    expect(authentication.code, 'invalid_token');
    expect(authentication.details, {'reason': 'expired'});
    expect(
      SocketIoStudyRoomRealtimeConnector.mapConnectError(
        'Unauthorized websocket',
      ).kind,
      StudyRoomExceptionKind.authentication,
    );
    expect(
      SocketIoStudyRoomRealtimeConnector.mapConnectError(
        'connection reset',
      ).kind,
      StudyRoomExceptionKind.network,
    );
  });

  test(
    'SDK validates operations, handles events, and clears revoked snapshots',
    () async {
      final transport = FakeTransport();
      final realtime = FakeRealtimeConnector();
      final sdk = StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse('https://example.com'),
          realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
          tokenProvider: _token,
          transport: transport,
          realtimeConnector: realtime,
        ),
      );
      transport.handler = (method, path, body) async {
        if (path == '/v1/rooms/room-1') return _roomJson('room-1');
        if (path.startsWith('/v1/join-requests')) {
          return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
        }
        if (path.contains('/active-sessions') || path.contains('/messages')) {
          return {'items': <Map<String, dynamic>>[], 'nextCursor': null};
        }
        if (path.contains('/join-requests') && method == 'GET') {
          return {
            'items': [_requestJson()],
            'nextCursor': null,
          };
        }
        return null;
      };
      final connectionStates = <StudyRoomConnectionState>[];
      final connectionSubscription = sdk.connectionStates.listen(
        connectionStates.add,
      );
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        sdk.setAway('room-1', true),
        throwsA(isA<StudyRoomException>()),
      );
      await sdk.start();
      await sdk.start();
      expect(connectionStates, [
        StudyRoomConnectionState.stopped,
        StudyRoomConnectionState.connecting,
        StudyRoomConnectionState.synchronizing,
        StudyRoomConnectionState.connected,
      ]);
      await sdk.rooms.subscribe('room-1');
      await sdk.setAway('room-1', false);
      await expectLater(
        sdk.chat.send('room-1', ' '),
        throwsA(isA<StudyRoomException>()),
      );
      await expectLater(
        sdk.chat.send('room-1', List.filled(2001, 'x').join()),
        throwsA(isA<StudyRoomException>()),
      );
      await expectLater(
        sdk.sessions.update('session-1', StudySessionStatus.idle),
        throwsA(isA<StudyRoomException>()),
      );
      await expectLater(
        sdk.joinRequests.decide(
          'room-1',
          'request-1',
          JoinRequestStatus.pending,
        ),
        throwsA(isA<StudyRoomException>()),
      );
      expect((await sdk.joinRequests.forRoom('room-1')).items, hasLength(1));

      final events = <StudyRoomRealtimeEvent>[];
      final errors = <Object>[];
      final roomStates = <StudyRoom>[];
      final messages = <ChatMessage>[];
      final sessions = <StudySessionState>[];
      final subscription = sdk.events.listen(events.add, onError: errors.add);
      final roomSubscription = sdk.roomStates.listen(
        roomStates.add,
        onError: (_) {},
      );
      final messageSubscription = sdk.messages.listen(
        messages.add,
        onError: (_) {},
      );
      final sessionSubscription = sdk.sessionUpdates.listen(
        sessions.add,
        onError: (_) {},
      );
      realtime.connection.eventController.add(
        _event('room.state', _roomJson('room-1')),
      );
      realtime.connection.eventController.add(
        _event('chat.message.created', _messageJson()),
      );
      realtime.connection.eventController.add(
        _event('session.updated', _sessionJson()),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sdk.roomSnapshot('room-1')?.version, 3);
      expect(events, hasLength(3));
      expect(roomStates, hasLength(1));
      expect(messages, hasLength(1));
      expect(sessions, hasLength(1));
      realtime.connection.eventController.add(
        _event('room.state', {
          ..._roomJson('room-1'),
          'version': 2,
        }, roomVersion: 2),
      );
      realtime.connection.eventController.add({
        ..._event('room.state', _roomJson('room-1')),
        'schemaVersion': 9,
      });
      await Future<void>.delayed(Duration.zero);
      expect(sdk.roomSnapshot('room-1')?.version, 3);
      expect(errors, hasLength(1));
      realtime.connection.eventController.add(
        _event('membership.updated', {'roomId': 'room-1', 'active': false}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(sdk.roomSnapshot('room-1'), isNull);
      await expectLater(
        sdk.setAway('room-1', true),
        throwsA(isA<StudyRoomException>()),
      );
      await sdk.rooms.subscribe('room-1');
      await sdk.rooms.unsubscribe('room-1');
      await sdk.joinRequests.cancel('room-1');
      await sdk.members.remove('room-1', 'user-2');
      await sdk.members.leave('room-1');
      await sdk.rooms.delete('room-1');
      await subscription.cancel();
      await roomSubscription.cancel();
      await messageSubscription.cancel();
      await sessionSubscription.cancel();
      await connectionSubscription.cancel();
      await sdk.close();
      await sdk.close();
      await expectLater(sdk.start(), throwsA(isA<StudyRoomException>()));
      await expectLater(sdk.rooms.list(), throwsA(isA<StudyRoomException>()));
    },
  );

  test('SDK rejects an expiring token from the provider', () async {
    final sdk = StudyRoomSdk(
      StudyRoomSdkConfig(
        apiBaseUri: Uri.parse('https://example.com'),
        realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
        tokenProvider: (_) async =>
            StudyRoomAccessToken(token: '', expiresAt: DateTime.now()),
        transport: FakeTransport(),
        realtimeConnector: FakeRealtimeConnector(),
      ),
    );
    await expectLater(sdk.start(), throwsA(isA<StudyRoomException>()));
    await sdk.close();
  });

  test('StudyStore emits changes and persists tasks and settings', () async {
    final store = MemoryStudyStore();
    final changes = <StudyStoreChange>[];
    final subscription = store.changes.listen(changes.add);
    final date = DateTime(2026, 6, 19, 12);
    const task = StudyTaskRecord(
      id: 'task-1',
      title: 'Write tests',
      completed: false,
    );

    await store.saveTodayGoal(date, const TodayGoal(text: 'Ship'));
    await store.addFocusSession(date, const Duration(minutes: 25));
    await store.saveTaskRecord(date, task);
    await store.deleteTaskRecord(date, task.id);
    await store.saveSettings(
      StudyFocusSettings(
        soundTrackId: 'rain',
        soundVolume: 2,
        backgroundMaskOpacity: -1,
        desktopSection: 'history',
      ),
    );

    expect(changes.map((change) => change.kind), [
      StudyStoreChangeKind.goal,
      StudyStoreChangeKind.dayRecord,
      StudyStoreChangeKind.tasks,
      StudyStoreChangeKind.tasks,
      StudyStoreChangeKind.settings,
    ]);
    expect(changes.first.date, DateTime(2026, 6, 19));
    expect(await store.loadTaskRecords(date), isEmpty);
    final settings = await store.loadSettings();
    expect(settings.soundVolume, 1);
    expect(settings.backgroundMaskOpacity, 0);
    expect(settings.desktopSection, 'history');
    await subscription.cancel();
  });

  group('PomodoroController', () {
    test('supports default, 50/10, and custom duration configs', () {
      expect(PomodoroConfig().focusDuration, const Duration(minutes: 25));
      expect(
        PomodoroConfig.fiftyTen().breakDuration,
        const Duration(minutes: 10),
      );
      expect(
        PomodoroConfig.custom(
          focusDuration: const Duration(minutes: 45),
          breakDuration: Duration.zero,
        ).preset,
        PomodoroPreset.custom,
      );
      expect(
        () => PomodoroConfig.custom(
          focusDuration: Duration.zero,
          breakDuration: const Duration(minutes: 5),
        ),
        throwsA(isA<StudyRoomError>()),
      );
    });

    test('start pause resume and end update state without recording', () async {
      final store = MemoryStudyStore();
      final controller = PomodoroController(
        store: store,
        config: PomodoroConfig.custom(
          focusDuration: const Duration(seconds: 1),
          breakDuration: Duration.zero,
        ),
        now: () => DateTime(2026, 6, 19),
      );

      controller.start();
      expect(controller.state.status, PomodoroStatus.focusing);

      controller.pause();
      expect(controller.state.status, PomodoroStatus.paused);

      controller.resume();
      expect(controller.state.status, PomodoroStatus.focusing);

      controller.end();
      expect(controller.state.status, PomodoroStatus.finished);
      expect(
        (await store.loadDayRecord(DateTime(2026, 6, 19))).pomodoroCount,
        0,
      );
      controller.dispose();
    });

    test('completed focus stage records a pomodoro automatically', () async {
      final store = MemoryStudyStore();
      final controller = PomodoroController(
        store: store,
        config: PomodoroConfig.custom(
          focusDuration: const Duration(milliseconds: 20),
          breakDuration: Duration.zero,
        ),
        now: () => DateTime(2026, 6, 19),
      );

      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 35));

      final record = await store.loadDayRecord(DateTime(2026, 6, 19));
      expect(record.focusDuration, const Duration(milliseconds: 20));
      expect(record.pomodoroCount, 1);
      expect(controller.state.status, PomodoroStatus.idle);
      controller.dispose();
    });

    test('ticks remaining time from an absolute deadline', () async {
      final controller = PomodoroController(
        store: MemoryStudyStore(),
        config: PomodoroConfig.custom(
          focusDuration: const Duration(seconds: 3),
          breakDuration: Duration.zero,
        ),
      );

      controller.start();
      await Future<void>.delayed(const Duration(milliseconds: 1100));

      expect(controller.state.remaining, lessThan(const Duration(seconds: 3)));
      expect(controller.state.remaining, greaterThan(Duration.zero));
      controller.end();
      controller.dispose();
    });

    test('pause recalculates elapsed time and resume preserves it', () {
      var now = DateTime(2026, 6, 19, 10);
      final controller = PomodoroController(
        store: MemoryStudyStore(),
        config: PomodoroConfig.custom(
          focusDuration: const Duration(minutes: 25),
          breakDuration: const Duration(minutes: 5),
        ),
        now: () => now,
      );

      controller.start();
      now = now.add(const Duration(minutes: 7));
      controller.pause();
      expect(controller.state.remaining, const Duration(minutes: 18));
      controller.resume();
      expect(controller.state.remaining, const Duration(minutes: 18));
      controller.end();
      controller.dispose();
    });

    test('skip moves stages without recording a pomodoro', () async {
      final store = MemoryStudyStore();
      final controller = PomodoroController(
        store: store,
        config: PomodoroConfig.custom(
          focusDuration: const Duration(minutes: 25),
          breakDuration: const Duration(minutes: 5),
        ),
      );

      controller.start();
      controller.skip();
      expect(controller.state.status, PomodoroStatus.breaking);
      controller.skip();
      expect(controller.state.status, PomodoroStatus.idle);
      expect((await store.loadDayRecord(DateTime.now())).pomodoroCount, 0);
      controller.dispose();
    });

    test('config can only change outside an active stage', () {
      final controller = PomodoroController(store: MemoryStudyStore());
      controller.setConfig(PomodoroConfig.fiftyTen());
      expect(controller.config.preset, PomodoroPreset.fiftyTen);

      controller.start();
      expect(
        () => controller.setConfig(PomodoroConfig()),
        throwsA(
          isA<StudyRoomError>().having(
            (error) => error.code,
            'code',
            'pomodoro_active',
          ),
        ),
      );
      controller.end();
      controller.dispose();
    });

    test(
      'persistence failures finish the stage and surface a stream error',
      () async {
        final controller = PomodoroController(
          store: FailingStudyStore(),
          config: PomodoroConfig.custom(
            focusDuration: const Duration(milliseconds: 20),
            breakDuration: Duration.zero,
          ),
        );
        final errors = <Object>[];
        final subscription = controller.states.listen(
          (_) {},
          onError: (Object error) => errors.add(error),
        );

        controller.start();
        await Future<void>.delayed(const Duration(milliseconds: 40));

        expect(controller.state.status, PomodoroStatus.finished);
        expect(errors, hasLength(1));
        await subscription.cancel();
        controller.dispose();
      },
    );
  });

  group('local study store and analytics', () {
    test(
      'today goals are saved, completed, and isolated by local date',
      () async {
        final store = MemoryStudyStore();
        final day = DateTime(2026, 6, 19, 22);
        final nextDay = DateTime(2026, 6, 20, 8);

        await store.saveTodayGoal(
          day,
          const TodayGoal(text: 'Read chapter 3', targetPomodoros: 4),
        );
        await store.saveTodayGoal(
          day,
          (await store.loadTodayGoal(day)).copyWith(completed: true),
        );

        expect((await store.loadTodayGoal(day)).completed, isTrue);
        expect((await store.loadTodayGoal(nextDay)).text, isEmpty);
      },
    );

    test(
      'stats include today totals, streak, and zero-filled last seven days',
      () async {
        final store = MemoryStudyStore();
        await store.addFocusSession(
          DateTime(2026, 6, 17),
          const Duration(minutes: 25),
        );
        await store.addFocusSession(
          DateTime(2026, 6, 18),
          const Duration(minutes: 50),
          pomodoros: 2,
        );
        await store.addFocusSession(
          DateTime(2026, 6, 19),
          const Duration(minutes: 25),
        );

        final stats = await StudyAnalytics(
          store,
        ).statsFor(DateTime(2026, 6, 19));

        expect(stats.todayFocusDuration, const Duration(minutes: 25));
        expect(stats.todayPomodoroCount, 1);
        expect(stats.streakDays, 3);
        expect(stats.lastSevenDays, hasLength(7));
        expect(stats.lastSevenDays.first.date, DateTime(2026, 6, 13));
        expect(stats.lastSevenDays.first.focusDuration, Duration.zero);
      },
    );

    test('streak breaks across empty dates', () async {
      final store = MemoryStudyStore();
      await store.addFocusSession(
        DateTime(2026, 6, 16),
        const Duration(minutes: 25),
      );
      await store.addFocusSession(
        DateTime(2026, 6, 18),
        const Duration(minutes: 25),
      );
      await store.addFocusSession(
        DateTime(2026, 6, 19),
        const Duration(minutes: 25),
      );

      final stats = await StudyAnalytics(store).statsFor(DateTime(2026, 6, 19));

      expect(stats.streakDays, 2);
    });

    test('task completion rate handles no, partial, and all tasks', () async {
      final analytics = StudyAnalytics(MemoryStudyStore());

      expect(analytics.taskCompletionRate(const []), isNull);
      expect(
        analytics.taskCompletionRate(const [
          StudyTaskRecord(id: '1', title: 'A', completed: true),
          StudyTaskRecord(id: '2', title: 'B', completed: false),
        ]),
        0.5,
      );
      expect(
        analytics.taskCompletionRate(const [
          StudyTaskRecord(id: '1', title: 'A', completed: true),
          StudyTaskRecord(id: '2', title: 'B', completed: true),
        ]),
        1.0,
      );
    });

    test(
      'day week and month reports aggregate and fill missing dates',
      () async {
        final store = MemoryStudyStore();
        await store.addFocusSession(
          DateTime(2026, 6, 1),
          const Duration(minutes: 25),
        );
        await store.addFocusSession(
          DateTime(2026, 6, 19),
          const Duration(minutes: 50),
          pomodoros: 2,
        );
        await store.saveTaskRecord(
          DateTime(2026, 6, 19),
          const StudyTaskRecord(id: 'task-1', title: 'Essay', completed: true),
        );
        await store.saveTaskRecord(
          DateTime(2026, 6, 19),
          const StudyTaskRecord(
            id: 'task-2',
            title: 'Review',
            completed: false,
          ),
        );

        final analytics = StudyAnalytics(store);
        final day = await analytics.report(
          StudyReportRange.day,
          DateTime(2026, 6, 19),
        );
        final week = await analytics.report(
          StudyReportRange.week,
          DateTime(2026, 6, 19),
        );
        final month = await analytics.report(
          StudyReportRange.month,
          DateTime(2026, 6, 19),
        );

        expect(day.days, hasLength(1));
        expect(day.totalPomodoroCount, 2);
        expect(day.taskCompletionRate, 0.5);
        expect(week.days, hasLength(7));
        expect(week.days.first.date, DateTime(2026, 6, 15));
        expect(month.days, hasLength(30));
        expect(month.totalFocusDuration, const Duration(minutes: 75));
      },
    );
  });
}

Future<
  ({StudyRoomSdk sdk, FakeTransport transport, FakeRealtimeConnector realtime})
>
_subscribedSdkFixture() async {
  final transport = FakeTransport();
  final realtime = FakeRealtimeConnector();
  final sdk = StudyRoomSdk(
    StudyRoomSdkConfig(
      apiBaseUri: Uri.parse('https://example.com'),
      realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
      tokenProvider: _token,
      transport: transport,
      realtimeConnector: realtime,
    ),
  );
  transport.handler = (method, path, body) async {
    if (path.contains('/active-sessions')) {
      return {
        'items': [_sessionJson()],
        'nextCursor': null,
      };
    }
    if (path.contains('/messages')) {
      return {
        'items': [_messageJson()],
        'nextCursor': null,
      };
    }
    if (path.contains('/join-requests') ||
        path.startsWith('/v1/join-requests')) {
      return {'items': <Object>[], 'nextCursor': null};
    }
    return _roomJson('room-1');
  };

  await sdk.start();
  await sdk.rooms.subscribe('room-1');
  return (sdk: sdk, transport: transport, realtime: realtime);
}

void _expectRoomCachePresent(StudyRoomSdk sdk) {
  expect(sdk.syncState.rooms, contains('room-1'));
  expect(sdk.syncState.activeSessionsByRoom['room-1'], isNotEmpty);
  expect(sdk.syncState.recentMessagesByRoom['room-1'], isNotEmpty);
}

void _expectRoomCacheEvicted(StudyRoomSdk sdk) {
  expect(sdk.syncState.rooms, isNot(contains('room-1')));
  expect(sdk.syncState.activeSessionsByRoom, isNot(contains('room-1')));
  expect(sdk.syncState.recentMessagesByRoom, isNot(contains('room-1')));
  expect(sdk.syncState.ownerInboxByRoom, isNot(contains('room-1')));
  expect(sdk.syncState.staleRoomIds, isNot(contains('room-1')));
}

Future<StudyRoomAccessToken> _token(StudyRoomTokenRequest request) async =>
    StudyRoomAccessToken(
      token: 'jwt',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    );

Map<String, dynamic> _roomJson(String id) => {
  'id': id,
  'appId': 'app-1',
  'title': 'Focus Room',
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

Map<String, dynamic> _requestJson() => {
  'id': 'request-1',
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

Map<String, dynamic> _messageJson({String text = 'hello'}) => {
  'id': 'message-1',
  'roomId': 'room-1',
  'senderId': 'user-1',
  'senderName': 'Lin',
  'text': text,
  'sentAt': '2026-08-09T00:00:00Z',
};

Map<String, dynamic> _event(
  String type,
  Map<String, dynamic> payload, {
  int roomVersion = 3,
}) => {
  'schemaVersion': 1,
  'eventId': 'event-$type',
  'type': type,
  'roomId': 'room-1',
  'roomVersion': roomVersion,
  'occurredAt': '2026-08-09T00:00:00Z',
  'payload': payload,
};

class _Request {
  const _Request(this.method, this.path, this.body);
  final String method;
  final String path;
  final Map<String, dynamic>? body;
}

class FakeTransport implements StudyRoomTransport {
  Future<Map<String, dynamic>?> Function(String, String, Map<String, dynamic>?)?
  handler;
  final requests = <_Request>[];
  bool closed = false;

  @override
  Future<Map<String, dynamic>?> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    requests.add(_Request(method, path, body));
    return handler?.call(method, path, body);
  }

  @override
  Future<void> close() async => closed = true;
}

class FakeRealtimeConnector implements StudyRoomRealtimeConnector {
  final connection = FakeRealtimeConnection();
  StudyRoomAccessToken? token;

  @override
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    this.token = token;
    return connection;
  }
}

class FakeRealtimeConnection implements StudyRoomRealtimeConnection {
  final eventController = StreamController<Map<String, dynamic>>.broadcast();
  final stateController =
      StreamController<StudyRoomConnectionState>.broadcast();
  final acks = <(String, Map<String, dynamic>)>[];
  bool closed = false;
  String? failEvent;

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
    acks.add((event, data));
    if (event == failEvent) throw StateError('$event failed');
    return {'ok': true};
  }

  @override
  Future<void> close() async {
    closed = true;
    await eventController.close();
    await stateController.close();
  }
}

class FailingStudyStore extends MemoryStudyStore {
  @override
  Future<void> addFocusSession(
    DateTime date,
    Duration duration, {
    int pomodoros = 1,
  }) async {
    throw StateError('storage failed');
  }
}
