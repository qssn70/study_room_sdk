import 'dart:convert';

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

  testWidgets('desktop navigation exposes four pages and controlled builder', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    StudyFocusDesktopSection? requested;
    Widget pageBuilder(
      BuildContext context,
      StudyFocusDesktopSection section,
      Widget defaultPage,
    ) => KeyedSubtree(
      key: Key('desktop_page_${section.name}'),
      child: defaultPage,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          desktopPageBuilder: pageBuilder,
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop_page_focus')), findsOneWidget);

    for (final section in const [
      (label: '数据统计', value: StudyFocusDesktopSection.analytics),
      (label: '历史记录', value: StudyFocusDesktopSection.history),
      (label: '设置', value: StudyFocusDesktopSection.settings),
      (label: '专注', value: StudyFocusDesktopSection.focus),
    ]) {
      await tester.tap(find.text(section.label).first);
      await tester.pumpAndSettle();
      expect(
        find.byKey(Key('desktop_page_${section.value.name}')),
        findsOneWidget,
      );
    }

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          desktopSection: StudyFocusDesktopSection.analytics,
          onDesktopSectionChanged: (section) => requested = section,
          desktopPageBuilder: pageBuilder,
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop_page_analytics')), findsOneWidget);
    await tester.tap(find.text('历史记录').first);
    await tester.pumpAndSettle();
    expect(requested, StudyFocusDesktopSection.history);
    expect(find.byKey(const Key('desktop_page_analytics')), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          desktopSection: StudyFocusDesktopSection.history,
          desktopPageBuilder: pageBuilder,
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('desktop_page_history')), findsOneWidget);
  });

  testWidgets('desktop history creates edits completes and deletes tasks', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStudyStore();

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: store,
          initialDesktopSection: StudyFocusDesktopSection.history,
          taskEditor: (context, date, existing) async => existing == null
              ? const StudyTaskRecord(
                  id: 'task-1',
                  title: 'Draft docs',
                  completed: false,
                )
              : existing.copyWith(title: 'Ship docs'),
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('新建任务').first);
    await tester.pumpAndSettle();
    expect(find.text('Draft docs'), findsOneWidget);

    final taskTile = find.byKey(const Key('desktop_task_task-1'));
    await tester.tap(
      find.descendant(of: taskTile, matching: find.byType(Checkbox)),
    );
    await tester.pumpAndSettle();
    expect(
      (await store.loadTaskRecords(DateTime.now())).single.completed,
      isTrue,
    );

    await tester.tap(
      find.descendant(of: taskTile, matching: find.byIcon(Icons.edit)),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ship docs'), findsOneWidget);

    await tester.tap(
      find.descendant(of: taskTile, matching: find.byIcon(Icons.delete)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(await store.loadTaskRecords(DateTime.now()), isEmpty);
  });

  testWidgets('default desktop task editor rejects an empty title', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStudyStore();

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: store,
          initialDesktopSection: StudyFocusDesktopSection.history,
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建任务').first);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();
    expect(find.text('任务名称不能为空'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('study_task_title')), 'Read');
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('Read'), findsOneWidget);
    expect((await store.loadTaskRecords(DateTime.now())).single.title, 'Read');
  });

  testWidgets('desktop goals and statistics react to store changes', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStudyStore();
    final date = DateTime(2026, 6, 19);

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: store,
          date: date,
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('番茄进度: 0/4'), findsOneWidget);
    expect(find.text('0个'), findsOneWidget);

    await store.addFocusSession(date, const Duration(minutes: 25));
    await tester.pumpAndSettle();
    expect(find.textContaining('番茄进度: 1/4'), findsOneWidget);
    expect(find.text('1个'), findsOneWidget);
  });

  testWidgets(
    'desktop presets update duration estimates and disable while active',
    (tester) async {
      tester.view.physicalSize = const Size(1600, 900);
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
      expect(find.textContaining('预计还需 100 分钟'), findsOneWidget);

      await tester.tap(find.text('50 / 10 分钟'));
      await tester.pump();
      expect(find.text('50:00'), findsOneWidget);
      expect(find.textContaining('预计还需 200 分钟'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      await tester.tap(find.text('25 / 5 分钟'));
      await tester.pump();
      expect(find.text('50:00'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('desktop sound cards play pause and switch shared playback', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final player = FakeSoundPlayer();

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: MemoryStudyStore(),
          background: _testBackground,
          soundPlayer: player,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('desktop_sound_Rain')));
    await tester.pump();
    expect(player.playedTrackIds, ['rain']);
    await tester.tap(find.byKey(const Key('desktop_sound_Rain')));
    await tester.pump();
    expect(player.pauseCount, 1);
    await tester.tap(find.byKey(const Key('desktop_sound_Cafe')));
    await tester.pump();
    expect(player.playedTrackIds, ['rain', 'cafe']);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(player.disposed, isFalse);
  });

  testWidgets('scoped settings restore without automatically playing audio', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1600, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final scope = StudyStorageScope.user(
      userId: 'user-1',
      namespace: 'tenant-a',
    );
    await SharedPreferencesStudyStore(preferences, scope: scope).saveSettings(
      StudyFocusSettings(
        soundTrackId: 'cafe',
        soundVolume: 0.7,
        backgroundId: 'forest',
        backgroundMaskOpacity: 0.4,
        desktopSection: 'settings',
      ),
    );
    final player = FakeSoundPlayer();

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          currentUserId: 'user-1',
          localStorageNamespace: 'tenant-a',
          background: _testBackground,
          soundPlayer: player,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '森林')).selected,
      isTrue,
    );
    expect(
      tester
          .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'Cafe'))
          .selected,
      isTrue,
    );
    expect(
      tester
          .widget<Slider>(find.byKey(const Key('desktop_background_mask')))
          .value,
      0.4,
    );
    expect(player.playedTrack, isNull);
    expect(player.volume, 0.5);
  });

  testWidgets(
    'presence follows timer and application lifecycle without duplicates',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final updates = <PresenceStatus>[];
      Object? reportedError;

      await tester.pumpWidget(
        MaterialApp(
          home: StudyFocusKitView(
            store: MemoryStudyStore(),
            background: _testBackground,
            soundPlayer: FakeSoundPlayer(),
            onPresenceChanged: (status) async {
              updates.add(status);
              if (status == PresenceStatus.focusing) {
                throw StateError('presence failed');
              }
            },
            onPresenceError: (error, _) => reportedError = error,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(updates, [PresenceStatus.idle]);

      await tester.tap(find.byIcon(Icons.play_arrow).first);
      await tester.pump();
      expect(updates.last, PresenceStatus.focusing);
      expect(reportedError, isA<StateError>());
      await tester.tap(find.byIcon(Icons.pause).first);
      await tester.pump();

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();

      expect(updates, [
        PresenceStatus.idle,
        PresenceStatus.focusing,
        PresenceStatus.idle,
        PresenceStatus.away,
        PresenceStatus.idle,
      ]);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

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

  testWidgets('StudyFocusKitView presets, resume, and skip drive the timer', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = MemoryStudyStore();

    await tester.pumpWidget(
      MaterialApp(
        home: StudyFocusKitView(
          store: store,
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('50/10'));
    await tester.pump();
    expect(find.text('50:00'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.text('专注中'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.pause));
    await tester.pump();
    expect(find.text('已暂停'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.play_arrow));
    await tester.pump();
    expect(find.text('专注中'), findsOneWidget);

    await tester.tap(find.text('跳过'));
    await tester.pump();
    expect(find.text('休息中'), findsOneWidget);
    expect(find.text('10:00'), findsOneWidget);
    expect((await store.loadDayRecord(DateTime.now())).pomodoroCount, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('custom pomodoro preset validates and applies durations', (
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
          background: _testBackground,
          soundPlayer: FakeSoundPlayer(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('自定义'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('pomodoro_custom_focus')),
      '45',
    );
    await tester.enterText(find.byKey(const Key('pomodoro_custom_break')), '0');
    await tester.tap(find.text('应用'));
    await tester.pumpAndSettle();

    expect(find.text('45:00'), findsOneWidget);
  });

  testWidgets('PomodoroTimerView renders deadline-based ticks', (tester) async {
    var now = DateTime(2026, 6, 19, 10);
    final controller = PomodoroController(
      store: MemoryStudyStore(),
      config: PomodoroConfig.custom(
        focusDuration: const Duration(seconds: 3),
        breakDuration: Duration.zero,
      ),
      now: () => now,
    );
    await tester.pumpWidget(
      MaterialApp(home: PomodoroTimerView(controller: controller)),
    );

    await tester.tap(find.byIcon(Icons.play_arrow));
    now = now.add(const Duration(seconds: 1));
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('00:02'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  test(
    'SharedPreferencesStudyStore migrates legacy data to only one user',
    () async {
      final date = DateTime(2026, 6, 19);
      SharedPreferences.setMockInitialValues({
        'study_focus:goal:2026-06-19': jsonEncode(
          const TodayGoal(text: 'Legacy goal').toJson(),
        ),
      });
      final preferences = await SharedPreferences.getInstance();
      final guest = SharedPreferencesStudyStore(
        preferences,
        scope: StudyStorageScope.guest(namespace: 'tenant-a'),
      );
      expect((await guest.loadTodayGoal(date)).text, isEmpty);
      expect(preferences.containsKey('study_focus:goal:2026-06-19'), isTrue);

      final firstScope = StudyStorageScope.user(
        userId: 'user:one',
        namespace: 'tenant-a',
      );
      await SharedPreferencesStudyStore.migrateLegacyData(
        preferences,
        scope: firstScope,
      );
      final first = SharedPreferencesStudyStore(preferences, scope: firstScope);
      expect((await first.loadTodayGoal(date)).text, 'Legacy goal');
      expect(preferences.containsKey('study_focus:goal:2026-06-19'), isFalse);

      final secondScope = StudyStorageScope.user(
        userId: 'user:two',
        namespace: 'tenant-a',
      );
      await SharedPreferencesStudyStore.migrateLegacyData(
        preferences,
        scope: secondScope,
      );
      final second = SharedPreferencesStudyStore(
        preferences,
        scope: secondScope,
      );
      expect((await second.loadTodayGoal(date)).text, isEmpty);

      final otherNamespace = SharedPreferencesStudyStore(
        preferences,
        scope: StudyStorageScope.user(
          userId: 'user:one',
          namespace: 'tenant-b',
        ),
      );
      expect((await otherNamespace.loadTodayGoal(date)).text, isEmpty);
    },
  );

  test(
    'SharedPreferencesStudyStore migration is idempotent and keeps target data',
    () async {
      final date = DateTime(2026, 6, 19);
      final scope = StudyStorageScope.user(
        userId: 'user-1',
        namespace: 'target-priority',
      );
      final targetKey = '${scope.storagePrefix}:goal:2026-06-19';
      SharedPreferences.setMockInitialValues({
        'study_focus:goal:2026-06-19': jsonEncode(
          const TodayGoal(text: 'Legacy goal').toJson(),
        ),
        targetKey: jsonEncode(const TodayGoal(text: 'Target goal').toJson()),
      });
      final preferences = await SharedPreferences.getInstance();

      await SharedPreferencesStudyStore.migrateLegacyData(
        preferences,
        scope: scope,
      );
      await SharedPreferencesStudyStore.migrateLegacyData(
        preferences,
        scope: scope,
      );

      final store = SharedPreferencesStudyStore(preferences, scope: scope);
      expect((await store.loadTodayGoal(date)).text, 'Target goal');
      expect(preferences.containsKey('study_focus:goal:2026-06-19'), isFalse);
      expect(preferences.getBool(scope.migrationMarker), isTrue);
    },
  );

  test(
    'SharedPreferencesStudyStore migration failure can be retried',
    () async {
      final date = DateTime(2026, 6, 19);
      final scope = StudyStorageScope.user(
        userId: 'user-1',
        namespace: 'retry',
      );
      final preferences = _FailingMigrationPreferences({
        'study_focus:goal:2026-06-19': jsonEncode(
          const TodayGoal(text: 'Retry goal').toJson(),
        ),
      });

      await expectLater(
        SharedPreferencesStudyStore.migrateLegacyData(
          preferences,
          scope: scope,
        ),
        throwsStateError,
      );
      expect(preferences.containsKey('study_focus:goal:2026-06-19'), isTrue);
      expect(preferences.getBool(scope.migrationMarker), isNot(true));

      await SharedPreferencesStudyStore.migrateLegacyData(
        preferences,
        scope: scope,
      );
      final store = SharedPreferencesStudyStore(preferences, scope: scope);
      expect((await store.loadTodayGoal(date)).text, 'Retry goal');
      expect(preferences.containsKey('study_focus:goal:2026-06-19'), isFalse);
      expect(preferences.getBool(scope.migrationMarker), isTrue);
    },
  );

  test(
    'SharedPreferencesStudyStore broadcasts only successful writes',
    () async {
      final preferences = _FailingMigrationPreferences({});
      final store = SharedPreferencesStudyStore(
        preferences,
        scope: StudyStorageScope.guest(namespace: 'failed-writes'),
      );
      final changes = <StudyStoreChange>[];
      final subscription = store.changes.listen(changes.add);

      await expectLater(
        store.saveTodayGoal(
          DateTime(2026, 6, 19),
          const TodayGoal(text: 'Nope'),
        ),
        throwsStateError,
      );
      expect(changes, isEmpty);
      await subscription.cancel();
    },
  );

  test('task mutations are serialized across scoped store instances', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final scope = StudyStorageScope.user(
      userId: 'user-1',
      namespace: 'concurrent-tasks',
    );
    final first = SharedPreferencesStudyStore(preferences, scope: scope);
    final second = SharedPreferencesStudyStore(preferences, scope: scope);
    final date = DateTime(2026, 6, 19);

    await Future.wait([
      first.saveTaskRecord(
        date,
        const StudyTaskRecord(id: 'one', title: 'One', completed: false),
      ),
      second.saveTaskRecord(
        date,
        const StudyTaskRecord(id: 'two', title: 'Two', completed: false),
      ),
    ]);

    expect((await first.loadTaskRecords(date)).map((task) => task.id).toSet(), {
      'one',
      'two',
    });
  });

  test('settings stay isolated by identity and namespace', () async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await SharedPreferences.getInstance();
    final userA = SharedPreferencesStudyStore(
      preferences,
      scope: StudyStorageScope.user(userId: 'a', namespace: 'tenant'),
    );
    final userB = SharedPreferencesStudyStore(
      preferences,
      scope: StudyStorageScope.user(userId: 'b', namespace: 'tenant'),
    );
    final guest = SharedPreferencesStudyStore(
      preferences,
      scope: StudyStorageScope.guest(namespace: 'tenant'),
    );
    final otherNamespace = SharedPreferencesStudyStore(
      preferences,
      scope: StudyStorageScope.user(userId: 'a', namespace: 'other'),
    );

    await userA.saveSettings(StudyFocusSettings(desktopSection: 'history'));
    expect((await userA.loadSettings()).desktopSection, 'history');
    expect((await userB.loadSettings()).desktopSection, isNull);
    expect((await guest.loadSettings()).desktopSection, isNull);
    expect((await otherNamespace.loadSettings()).desktopSection, isNull);
  });

  testWidgets('StudyFocusKitView isolates data when the user changes', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final date = DateTime(2026, 6, 19);

    Future<void> pumpFor(String userId) async {
      await tester.pumpWidget(
        MaterialApp(
          home: StudyFocusKitView(
            currentUserId: userId,
            localStorageNamespace: 'tenant-a',
            date: date,
            background: _testBackground,
            soundPlayer: FakeSoundPlayer(),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpFor('user-1');
    await tester.enterText(
      find.byKey(const Key('study_focus_goal_text_field')),
      'Private goal',
    );
    await tester.pumpAndSettle();

    await pumpFor('user-2');
    expect(find.text('Private goal'), findsNothing);
    await pumpFor('user-1');
    expect(find.text('Private goal'), findsOneWidget);
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
  final playedTrackIds = <String>[];
  var volume = 0.5;
  var paused = false;
  var pauseCount = 0;
  var disposed = false;

  @override
  Future<void> pause() async {
    paused = true;
    pauseCount += 1;
  }

  @override
  Future<void> play(StudySoundTrack track, {double volume = 0.5}) async {
    playedTrack = track;
    playedTrackIds.add(track.id);
    this.volume = volume;
    paused = false;
  }

  @override
  Future<void> setVolume(double volume) async {
    this.volume = volume;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

class _FailingMigrationPreferences extends Fake implements SharedPreferences {
  _FailingMigrationPreferences(this.values);

  final Map<String, Object> values;
  var failNextStringWrite = true;

  @override
  Set<String> getKeys() => values.keys.toSet();

  @override
  bool? getBool(String key) => values[key] as bool?;

  @override
  String? getString(String key) => values[key] as String?;

  @override
  bool containsKey(String key) => values.containsKey(key);

  @override
  Future<bool> setString(String key, String value) async {
    if (failNextStringWrite) {
      failNextStringWrite = false;
      return false;
    }
    values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async => values.remove(key) != null;

  @override
  Future<bool> setBool(String key, bool value) async {
    values[key] = value;
    return true;
  }
}
