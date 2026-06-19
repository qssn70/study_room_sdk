import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  testWidgets('MemberGrid renders names and presence labels', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: MemberGrid(
          members: const [
            StudyMember(
              id: 'u1',
              displayName: 'Lin',
              avatarUrl: '',
              status: PresenceStatus.focusing,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Lin'), findsOneWidget);
    expect(find.text('Focusing'), findsOneWidget);
  });

  testWidgets('FocusTimer exposes start and pause actions', (tester) async {
    var started = false;
    var paused = false;

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTimer(
          elapsed: const Duration(minutes: 25),
          status: StudySessionStatus.running,
          onStart: () => started = true,
          onPause: () => paused = true,
        ),
      ),
    );

    expect(find.text('25:00'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    expect(paused, isTrue);

    await tester.pumpWidget(
      MaterialApp(
        home: FocusTimer(
          elapsed: Duration.zero,
          status: StudySessionStatus.idle,
          onStart: () => started = true,
          onPause: () => paused = true,
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.play_arrow));
    expect(started, isTrue);
  });

  testWidgets('ChatPanel sends trimmed non-empty text', (tester) async {
    String? sent;

    await tester.pumpWidget(
      MaterialApp(
        home: ChatPanel(
          messages: const [],
          onSend: (text) async {
            sent = text;
          },
        ),
      ),
    );

    await tester.enterText(find.byType(TextField), ' hello ');
    await tester.tap(find.byIcon(Icons.send));
    await tester.pump();

    expect(sent, 'hello');
  });

  testWidgets('StudyFocusKitView renders all seven study modules', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          currentUserId: 'u1',
          room: const StudyRoom(
            id: 'room',
            title: 'Focus room',
            members: [
              StudyMember(
                id: 'u1',
                displayName: 'You',
                avatarUrl: '',
                status: PresenceStatus.focusing,
              ),
              StudyMember(
                id: 'u2',
                displayName: 'Kai',
                avatarUrl: '',
                status: PresenceStatus.idle,
              ),
            ],
          ),
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Pomodoro'), findsOneWidget);
    expect(find.text('Today goal'), findsWidgets);
    expect(find.text('Study records'), findsOneWidget);
    expect(find.text('Personal analytics'), findsOneWidget);
    expect(find.text('Background sound'), findsOneWidget);
    expect(find.text('Background'), findsOneWidget);
    expect(find.text('Companions'), findsOneWidget);
  });

  testWidgets('StudyFocusKitView persists data locally by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          date: DateTime(2026, 6, 19),
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Today goal'), 'Write notes');
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          date: DateTime(2026, 6, 19),
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Write notes'), findsOneWidget);
  });

  testWidgets('TodayGoalView saves text, target pomodoros, and completion', (
    tester,
  ) async {
    final store = MemoryStudyStore();
    await tester.pumpWidget(
      MaterialApp(
        home: TodayGoalView(store: store, date: DateTime(2026, 6, 19)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.bySemanticsLabel('Today goal'), 'Read papers');
    await tester.enterText(find.bySemanticsLabel('Target pomodoros'), '3');
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    final goal = await store.loadTodayGoal(DateTime(2026, 6, 19));
    expect(goal.text, 'Read papers');
    expect(goal.targetPomodoros, 3);
    expect(goal.completed, isTrue);
  });

  testWidgets(
    'StudyAnalyticsView and StudyReportView show only personal data',
    (tester) async {
      final store = MemoryStudyStore();
      await store.addFocusSession(
        DateTime(2026, 6, 19),
        const Duration(minutes: 50),
        pomodoros: 2,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Column(
            children: [
              StudyAnalyticsView(store: store, date: DateTime(2026, 6, 19)),
              StudyReportView(
                store: store,
                range: StudyReportRange.week,
                date: DateTime(2026, 6, 19),
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('50 min'), findsWidgets);
      expect(find.textContaining('2 pomodoros'), findsWidgets);
      expect(find.text('Mina'), findsNothing);
    },
  );

  testWidgets('SilentCompanionList filters current and offline users', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SilentCompanionList(
          currentUserId: 'u1',
          members: [
            StudyMember(
              id: 'u1',
              displayName: 'You',
              avatarUrl: '',
              status: PresenceStatus.focusing,
            ),
            StudyMember(
              id: 'u2',
              displayName: 'Kai',
              avatarUrl: '',
              status: PresenceStatus.focusing,
            ),
            StudyMember(
              id: 'u3',
              displayName: 'Mina',
              avatarUrl: '',
              status: PresenceStatus.offline,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Kai'), findsOneWidget);
    expect(find.text('You'), findsNothing);
    expect(find.text('Mina'), findsNothing);
    expect(find.textContaining('25'), findsNothing);
    expect(find.textContaining('pomodoro'), findsNothing);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
  });

  testWidgets('SilentCompanionList updates smoothly when members change', (
    tester,
  ) async {
    const kai = StudyMember(
      id: 'u2',
      displayName: 'Kai',
      avatarUrl: '',
      status: PresenceStatus.idle,
    );
    const lin = StudyMember(
      id: 'u3',
      displayName: 'Lin',
      avatarUrl: '',
      status: PresenceStatus.away,
    );

    await tester.pumpWidget(
      const MaterialApp(
        home: SilentCompanionList(currentUserId: 'u1', members: [kai]),
      ),
    );
    expect(find.text('Kai'), findsOneWidget);

    await tester.pumpWidget(
      const MaterialApp(
        home: SilentCompanionList(currentUserId: 'u1', members: [kai, lin]),
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Kai'), findsOneWidget);
    expect(find.text('Lin'), findsOneWidget);
    expect(find.byIcon(Icons.local_cafe), findsOneWidget);
  });

  testWidgets('BackgroundSoundView plays, pauses, and changes volume', (
    tester,
  ) async {
    final player = FakeSoundPlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: BackgroundSoundView(
          tracks: [
            ...StudySoundTrack.builtIns,
            const StudySoundTrack.network(
              id: 'stream',
              label: 'Stream',
              url: 'https://example.com/audio.mp3',
            ),
          ],
          soundPlayer: player,
        ),
      ),
    );

    await tester.tap(find.text('Rain'));
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(player.playedTrack?.id, 'rain');

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pump();
    expect(player.volume, isNot(0.5));

    await tester.tap(find.byIcon(Icons.pause));
    expect(player.paused, isTrue);
    expect(find.text('Stream'), findsOneWidget);
  });

  testWidgets('StudyBackgroundLayer renders color gradient and readable mask', (
    tester,
  ) async {
    final background = StudyBackground.gradient(
      colors: const [Colors.teal, Colors.white],
      maskOpacity: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StudyBackgroundLayer(
          background: background,
          child: const Text('Readable'),
        ),
      ),
    );

    expect(background.maskOpacity, 0.85);
    expect(find.text('Readable'), findsOneWidget);
  });
}

class FakeSoundPlayer implements StudySoundPlayer {
  StudySoundTrack? playedTrack;
  var volume = 0.5;
  var paused = false;

  @override
  Future<void> pause() async {
    paused = true;
  }

  @override
  Future<void> play(StudySoundTrack track, {double volume = 0.5}) async {
    playedTrack = track;
    this.volume = volume;
    paused = false;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> dispose() async {}
}
