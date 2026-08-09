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
    final realtime = FakeRealtimeConnector();
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
        realtimeConnector: realtime,
      ),
    );

    final room = await sdk.client.joinRoom('room-1');

    expect(room.title, 'Morning focus');
    expect(room.members.single.status, PresenceStatus.focusing);
    expect(transport.lastAuthorization, 'Bearer jwt-token');
    expect(realtime.connection.joinedRoomId, 'room-1');
    await expectLater(sdk.client.roomStateStream, emits(room));

    await sdk.client.leaveRoom('room-1');
    expect(realtime.connection.leftRoomId, 'room-1');
    await sdk.client.dispose();
  });

  test(
    'client tracks multiple rooms, presence, and room-aware events',
    () async {
      final realtime = FakeRealtimeConnector();
      final transport = FakeTransport({
        '/rooms/room-1/join': {
          'id': 'room-1',
          'title': 'One',
          'members': <Object>[],
        },
        '/rooms/room-2/join': {
          'id': 'room-2',
          'title': 'Two',
          'members': <Object>[],
        },
        '/rooms/room-1/leave': <String, dynamic>{},
      });
      final sdk = StudyRoomSdk.initialize(
        StudyRoomConfig(
          apiBaseUrl: Uri.parse('http://localhost:3000'),
          realtimeUrl: Uri.parse('ws://localhost:3000/realtime'),
          tokenProvider: () async => 'jwt-token',
          transport: transport,
          realtimeConnector: realtime,
        ),
      );

      await sdk.client.joinRoom('room-1');
      await sdk.client.joinRoom('room-2');
      expect(realtime.connection.joinedRoomIds, ['room-1', 'room-2']);
      expect(sdk.client.roomSnapshot('room-2')?.title, 'Two');

      sdk.client.updatePresence('room-2', PresenceStatus.focusing);
      expect(realtime.connection.presenceUpdates, [
        ('room-2', PresenceStatus.focusing),
      ]);
      expect(
        () => sdk.client.updatePresence('room-2', PresenceStatus.offline),
        throwsA(isA<StudyRoomError>()),
      );

      final nextMember = sdk.client.roomMemberEventsStream.first;
      realtime.connection.emit({
        'type': 'member.updated',
        'roomId': 'room-2',
        'payload': {
          'id': 'member-2',
          'displayName': 'Mei',
          'avatarUrl': '',
          'status': 'idle',
        },
      });
      final memberEvent = await nextMember;
      expect(memberEvent.roomId, 'room-2');
      expect(memberEvent.member.status, PresenceStatus.idle);

      await sdk.client.leaveRoom('room-1');
      expect(realtime.connection.leftRoomIds, ['room-1']);
      expect(sdk.client.roomSnapshot('room-1'), isNull);
      expect(sdk.client.roomSnapshot('room-2'), isNotNull);
      await sdk.client.dispose();
    },
  );

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

  test('ChatClient loads authenticated history in server order', () async {
    final transport = FakeTransport({
      '/rooms/room-1/chat': {
        'messages': [
          {
            'id': 'message-1',
            'roomId': 'room-1',
            'senderId': 'user-1',
            'senderName': 'Lin',
            'text': 'first',
            'sentAt': '2026-06-18T03:00:00.000Z',
          },
          {
            'id': 'message-2',
            'roomId': 'room-1',
            'senderId': 'user-2',
            'senderName': 'Mei',
            'text': 'second',
            'sentAt': '2026-06-18T03:01:00.000Z',
          },
        ],
      },
    });
    final chat = ChatClient(
      roomId: 'room-1',
      transport: transport,
      tokenProvider: () async => 'jwt-token',
    );

    final history = await chat.loadHistory();

    expect(history.map((message) => message.text), ['first', 'second']);
    expect(transport.lastPath, '/rooms/room-1/chat');
    expect(transport.lastAuthorization, 'Bearer jwt-token');
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

class FakeRealtimeConnector implements StudyRoomRealtimeConnector {
  final connection = FakeRealtimeConnection();

  @override
  StudyRoomRealtimeConnection connect(Uri url, {required String token}) {
    return connection;
  }
}

class FakeRealtimeConnection implements StudyRoomRealtimeConnection {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  String? joinedRoomId;
  String? leftRoomId;
  final joinedRoomIds = <String>[];
  final leftRoomIds = <String>[];
  final presenceUpdates = <(String, PresenceStatus)>[];

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;

  @override
  void joinRoom({required String roomId}) {
    joinedRoomId = roomId;
    joinedRoomIds.add(roomId);
  }

  @override
  void leaveRoom({required String roomId}) {
    leftRoomId = roomId;
    leftRoomIds.add(roomId);
  }

  @override
  void updatePresence({
    required String roomId,
    required PresenceStatus status,
  }) {
    presenceUpdates.add((roomId, status));
  }

  void emit(Map<String, dynamic> event) => _events.add(event);

  @override
  Future<void> close() => _events.close();
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
