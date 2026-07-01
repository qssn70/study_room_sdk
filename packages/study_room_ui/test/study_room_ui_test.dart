import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

const _testBackground = StudyBackground.color(
  Color(0xFF20162D),
  maskOpacity: 0.25,
);

void main() {
  test('StudyFocusKitView exposes all documented visual styles', () {
    expect(StudyFocusVisualStyle.values, [
      StudyFocusVisualStyle.split,
      StudyFocusVisualStyle.centered,
      StudyFocusVisualStyle.immersiveDock,
    ]);
    expect(
      const StudyFocusKitView().visualStyle,
      StudyFocusVisualStyle.immersiveDock,
    );
  });

  test('StudyFocusKitView defaults to the documented image background', () {
    const view = StudyFocusKitView();

    expect(view.background.type, StudyBackgroundType.image);
    expect(view.background.image, isA<NetworkImage>());
    expect(
      (view.background.image! as NetworkImage).url,
      'https://images.unsplash.com/photo-1419242902214-272b3f66ee7a?q=80&w=2000&auto=format&fit=crop',
    );

    const customBackground = StudyBackground.color(Colors.teal);
    const customView = StudyFocusKitView(background: customBackground);
    expect(customView.background, same(customBackground));
  });

  testWidgets('StudyFocusKitView renders the selected portrait visual style', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final style in StudyFocusVisualStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: StudyFocusKitView(
            store: MemoryStudyStore(),
            visualStyle: style,
            background: _testBackground,
            soundPlayer: FakeSoundPlayer(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(Key('study_focus_style_${style.name}_portrait')),
        findsOneWidget,
      );
      expect(find.text('25:00'), findsOneWidget);
      expect(find.text('自定义'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.text('跳过'), findsOneWidget);
      expect(find.text('统计'), findsOneWidget);
      expect(find.text('成员'), findsOneWidget);
      expect(find.text('雨声'), findsWidgets);
      expect(find.byIcon(Icons.bar_chart), findsOneWidget);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
      expect(find.byIcon(Icons.group), findsOneWidget);
    }
  });

  testWidgets('StudyFocusKitView renders selected styles in landscape panels', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    for (final style in StudyFocusVisualStyle.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: StudyFocusKitView(
            store: MemoryStudyStore(),
            visualStyle: style,
            background: _testBackground,
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

      expect(
        find.byKey(Key('study_focus_style_${style.name}_landscape')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('study_focus_landscape_side_panel')),
        findsOneWidget,
      );
      expect(find.text('Kai'), findsOneWidget);
      expect(find.text('陪伴中'), findsOneWidget);
      expect(find.text('今日目标'), findsOneWidget);
      expect(find.text('背景音'), findsOneWidget);
      expect(find.text('个人统计（私密）'), findsOneWidget);
    }
  });

  testWidgets('StudyFocusKitView renders the desktop landscape workspace', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final store = MemoryStudyStore();
    await store.saveTodayGoal(
      DateTime(2026, 6, 19),
      const TodayGoal(text: '完成 SDK 文档编写', targetPomodoros: 4),
    );
    await store.addFocusSession(
      DateTime(2026, 6, 19),
      const Duration(minutes: 50),
      pomodoros: 2,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: store,
          currentUserId: 'u1',
          date: DateTime(2026, 6, 19),
          background: _testBackground,
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
                displayName: 'Alex',
                avatarUrl: '',
                status: PresenceStatus.focusing,
              ),
              StudyMember(
                id: 'u3',
                displayName: 'Bob',
                avatarUrl: '',
                status: PresenceStatus.idle,
              ),
              StudyMember(
                id: 'u4',
                displayName: 'Cathy',
                avatarUrl: '',
                status: PresenceStatus.away,
              ),
            ],
          ),
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study_focus_desktop_shell')), findsOneWidget);
    expect(
      find.byKey(const Key('study_focus_style_immersiveDock_landscape')),
      findsOneWidget,
    );
    expect(find.text('极简自习室'), findsOneWidget);
    expect(find.text('专注'), findsOneWidget);
    expect(find.text('数据统计'), findsOneWidget);
    expect(find.text('历史记录'), findsOneWidget);
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('新建任务'), findsOneWidget);
    expect(find.text('25 / 5 分钟'), findsOneWidget);
    expect(find.text('50 / 10 分钟'), findsOneWidget);
    expect(find.text('自定义时长'), findsOneWidget);
    expect(find.text('结束当前轮次'), findsOneWidget);
    expect(find.text('跳至休息'), findsOneWidget);
    expect(find.text('静默陪伴'), findsOneWidget);
    expect(find.text('在线 3 人'), findsOneWidget);
    expect(find.text('白噪音'), findsOneWidget);
    expect(find.text('今日数据 (私密)'), findsOneWidget);
    expect(find.text('完成 SDK 文档编写'), findsOneWidget);
    expect(find.textContaining('预计还需'), findsOneWidget);

    final sidebarSize = tester.getSize(
      find.byKey(const Key('study_focus_desktop_sidebar')),
    );
    expect(sidebarSize.width, inInclusiveRange(340, 420));
  });

  testWidgets('StudyFocusKitView reserves desktop shell for wide landscape', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('study_focus_desktop_shell')), findsNothing);
    expect(find.byKey(const Key('study_focus_desktop_sidebar')), findsNothing);
    expect(
      find.byKey(const Key('study_focus_style_immersiveDock_landscape')),
      findsOneWidget,
    );
  });

  testWidgets('StudyFocusKitView scales focus controls to the viewport', (
    tester,
  ) async {
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Future<Size> timerSizeFor(Size viewport) async {
      tester.view.physicalSize = viewport;
      tester.view.devicePixelRatio = 1;

      await tester.pumpWidget(
        MaterialApp(
          home: StudyFocusKitView(
            store: MemoryStudyStore(),
            background: _testBackground,
            soundPlayer: FakeSoundPlayer(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      return tester.getSize(find.byKey(const Key('study_focus_timer')));
    }

    final phoneTimer = await timerSizeFor(const Size(390, 844));
    final desktopTimer = await timerSizeFor(const Size(1440, 900));

    expect(phoneTimer.width, lessThanOrEqualTo(260));
    expect(desktopTimer.width, greaterThan(phoneTimer.width + 80));
    expect(desktopTimer.height, desktopTimer.width);
  });

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

  testWidgets('StudyFocusKitView opens the documented dock modules', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          currentUserId: 'u1',
          background: _testBackground,
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

    expect(
      find.byKey(const Key('study_focus_style_immersiveDock_portrait')),
      findsOneWidget,
    );
    expect(find.byKey(const Key('study_focus_goal_card')), findsOneWidget);
    expect(find.text('25:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.bar_chart));
    await tester.pumpAndSettle();
    expect(find.text('个人统计（私密）'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.music_note));
    await tester.pumpAndSettle();
    expect(find.text('背景音'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.group));
    await tester.pumpAndSettle();
    expect(find.text('陪伴中'), findsOneWidget);
    expect(find.text('Kai'), findsOneWidget);
  });

  testWidgets('StudyFocusKitView persists data locally by default', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          date: DateTime(2026, 6, 19),
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('study_focus_goal_text_field')),
      'Write notes',
    );
    await tester.pumpAndSettle();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          date: DateTime(2026, 6, 19),
          background: _testBackground,
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
