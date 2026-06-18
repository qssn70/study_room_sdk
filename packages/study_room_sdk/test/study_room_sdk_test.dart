import 'dart:async';

import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('initialize rejects an API URL without a scheme', () {
    expect(
      () => StudyRoomSdk.initialize(
        StudyRoomConfig(
          apiBaseUrl: Uri.parse('localhost:3000'),
          realtimeUrl: Uri.parse('ws://localhost:3000/realtime'),
          tokenProvider: () async => 'token',
        ),
      ),
      throwsA(isA<StudyRoomError>()),
    );
  });

  test('joinRoom sends bearer auth and publishes room state', () async {
    final transport = FakeTransport({
      '/rooms/room-1/join': {
        'id': 'room-1',
        'title': 'Morning focus',
        'members': [
          {
            'id': 'user-1',
            'displayName': 'Lin',
            'avatarUrl': 'https://example.com/a.png',
            'status': 'focusing',
          },
        ],
      },
    });

    final sdk = StudyRoomSdk.initialize(
      StudyRoomConfig(
        apiBaseUrl: Uri.parse('http://localhost:3000'),
        realtimeUrl: Uri.parse('ws://localhost:3000/realtime'),
        tokenProvider: () async => 'jwt-token',
        transport: transport,
      ),
    );

    final room = await sdk.client.joinRoom('room-1');

    expect(room.title, 'Morning focus');
    expect(room.members.single.status, PresenceStatus.focusing);
    expect(transport.lastAuthorization, 'Bearer jwt-token');
    await expectLater(sdk.client.roomStateStream, emits(room));
  });

  test('StudySession enforces start pause resume finish transitions', () async {
    final transport = FakeTransport({
      '/rooms/room-1/sessions/start': {
        'id': 'session-1',
        'roomId': 'room-1',
        'status': 'running',
        'startedAt': '2026-06-18T03:00:00.000Z',
      },
      '/sessions/session-1/pause': {
        'id': 'session-1',
        'roomId': 'room-1',
        'status': 'paused',
        'startedAt': '2026-06-18T03:00:00.000Z',
      },
      '/sessions/session-1/resume': {
        'id': 'session-1',
        'roomId': 'room-1',
        'status': 'running',
        'startedAt': '2026-06-18T03:00:00.000Z',
      },
      '/sessions/session-1/finish': {
        'id': 'session-1',
        'roomId': 'room-1',
        'status': 'finished',
        'startedAt': '2026-06-18T03:00:00.000Z',
        'finishedAt': '2026-06-18T03:25:00.000Z',
      },
    });
    final session = StudySession(
      roomId: 'room-1',
      transport: transport,
      tokenProvider: () async => 'jwt-token',
    );

    await session.start();
    expect(session.current.status, StudySessionStatus.running);
    await session.pause();
    expect(session.current.status, StudySessionStatus.paused);
    await session.resume();
    expect(session.current.status, StudySessionStatus.running);
    await session.finish();
    expect(session.current.status, StudySessionStatus.finished);
  });

  test(
    'ChatClient rejects empty messages and sends non-empty messages',
    () async {
      final transport = FakeTransport({
        '/rooms/room-1/chat': {
          'id': 'message-1',
          'roomId': 'room-1',
          'senderId': 'user-1',
          'senderName': 'Lin',
          'text': 'hello',
          'sentAt': '2026-06-18T03:00:00.000Z',
        },
      });
      final chat = ChatClient(
        roomId: 'room-1',
        transport: transport,
        tokenProvider: () async => 'jwt-token',
      );

      expect(() => chat.sendMessage('   '), throwsA(isA<StudyRoomError>()));

      final message = await chat.sendMessage(' hello ');

      expect(message.text, 'hello');
      expect(transport.lastPath, '/rooms/room-1/chat');
    },
  );
}

class FakeTransport implements StudyRoomTransport {
  FakeTransport(this.responses);

  final Map<String, Map<String, dynamic>> responses;
  String? lastAuthorization;
  String? lastPath;

  @override
  Future<Map<String, dynamic>> getJson(
    String path, {
    Map<String, String> headers = const {},
  }) async {
    lastAuthorization = headers['Authorization'];
    lastPath = path;
    return responses[path] ?? <String, dynamic>{};
  }

  @override
  Future<Map<String, dynamic>> postJson(
    String path, {
    Map<String, dynamic> body = const {},
    Map<String, String> headers = const {},
  }) async {
    lastAuthorization = headers['Authorization'];
    lastPath = path;
    return responses[path] ?? <String, dynamic>{};
  }
}
