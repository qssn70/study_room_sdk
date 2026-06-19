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
