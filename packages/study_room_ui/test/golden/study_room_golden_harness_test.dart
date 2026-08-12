import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';
import 'package:study_room_ui/src/focus_clock.dart';

const _runGoldens = bool.fromEnvironment('STUDY_ROOM_RUN_GOLDENS');
const _goldenRootKey = Key('study_room_golden_root');
final _fixedDate = DateTime(2026, 8, 11);

// Ubuntu baseline generation only:
// flutter test test/golden/study_room_golden_harness_test.dart \
//   --dart-define=STUDY_ROOM_RUN_GOLDENS=true --update-goldens

const _scenarios = <_GoldenScenario>[
  _GoldenScenario(
    name: 'focus_portrait_split',
    size: Size(390, 844),
    style: StudyFocusVisualStyle.split,
  ),
  _GoldenScenario(
    name: 'focus_portrait_centered',
    size: Size(390, 844),
    style: StudyFocusVisualStyle.centered,
  ),
  _GoldenScenario(
    name: 'focus_portrait_immersive',
    size: Size(390, 844),
    style: StudyFocusVisualStyle.immersiveDock,
  ),
  _GoldenScenario(
    name: 'focus_compact_landscape',
    size: Size(844, 390),
    style: StudyFocusVisualStyle.immersiveDock,
  ),
  _GoldenScenario(
    name: 'focus_desktop',
    size: Size(1440, 900),
    section: StudyFocusDesktopSection.focus,
  ),
  _GoldenScenario(
    name: 'analytics_desktop',
    size: Size(1440, 900),
    section: StudyFocusDesktopSection.analytics,
  ),
  _GoldenScenario(
    name: 'history_desktop',
    size: Size(1440, 900),
    section: StudyFocusDesktopSection.history,
  ),
  _GoldenScenario(
    name: 'room_management',
    size: Size(1024, 768),
    roomManagement: true,
  ),
];

void main() {
  test('golden scenario matrix remains exactly eight cases', () {
    expect(_scenarios, hasLength(8));
    expect(_scenarios.map((scenario) => scenario.name).toSet(), hasLength(8));
  });

  testWidgets('room management fixture renders loaded content without errors', (
    tester,
  ) async {
    final scenario = _scenarios.singleWhere(
      (candidate) => candidate.roomManagement,
    );

    await _pumpScenario(tester, scenario);

    expect(tester.takeException(), isNull);
    expect(find.byType(ErrorWidget), findsNothing);
    expect(find.text('Focus Room'), findsOneWidget);
    expect(find.text('No requests'), findsOneWidget);
    expect(tester.widget<Text>(find.text('No requests')).style, isNotNull);
    expect(
      tester.binding.renderViews.single.toStringDeep(),
      isNot(contains('OVERFLOWING')),
    );
  });

  for (final scenario in _scenarios) {
    testWidgets('Ubuntu golden: ${scenario.name}', (tester) async {
      expect(
        Platform.isLinux,
        isTrue,
        reason:
            'Golden comparison and updates are supported only on Ubuntu. '
            'Generate baselines with: '
            'flutter test test/golden/study_room_golden_harness_test.dart '
            '--dart-define=STUDY_ROOM_RUN_GOLDENS=true --update-goldens',
      );
      await _pumpScenario(tester, scenario);
      await expectLater(
        find.byKey(_goldenRootKey),
        matchesGoldenFile('baselines/${scenario.name}.png'),
      );
    }, skip: !_runGoldens);
  }
}

Future<void> _pumpScenario(
  WidgetTester tester,
  _GoldenScenario scenario,
) async {
  tester.view.physicalSize = scenario.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final store = MemoryStudyStore();
  await store.saveTodayGoal(
    _fixedDate,
    const TodayGoal(text: 'Review study notes', targetPomodoros: 4),
  );
  await store.addFocusSession(
    _fixedDate,
    const Duration(minutes: 50),
    pomodoros: 2,
  );
  await store.saveTaskRecord(
    _fixedDate,
    const StudyTaskRecord(
      id: 'task-1',
      title: 'Prepare chapter summary',
      completed: false,
    ),
  );

  StudyRoomSdk? sdk;
  final Widget home;
  if (scenario.roomManagement) {
    sdk = _goldenSdk();
    home = StudyRoomLobbyView(
      sdk: sdk,
      currentUserId: 'owner-1',
      onRoomSelected: (_) {},
    );
  } else {
    home = StudyFocusKitView(
      store: store,
      date: _fixedDate,
      currentUserId: 'owner-1',
      visualStyle: scenario.style ?? StudyFocusVisualStyle.immersiveDock,
      initialDesktopSection: scenario.section ?? StudyFocusDesktopSection.focus,
      background: const StudyBackground.color(
        Color(0xFF20162D),
        maskOpacity: 0.25,
      ),
      soundPlayer: _GoldenSoundPlayer(),
      room: StudyRoom(
        id: 'room-1',
        appId: 'app-1',
        title: 'Focus Room',
        version: 1,
        members: [
          StudyMember(
            id: 'owner-1',
            displayName: 'You',
            avatarUrl: '',
            status: PresenceStatus.focusing,
          ),
          StudyMember(
            id: 'member-1',
            displayName: 'Lin',
            avatarUrl: '',
            status: PresenceStatus.focusing,
          ),
          StudyMember(
            id: 'member-2',
            displayName: 'Kai',
            avatarUrl: '',
            status: PresenceStatus.away,
          ),
        ],
      ),
    );
  }

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
      supportedLocales: StudyRoomLocalizations.supportedLocales,
      theme: ThemeData(useMaterial3: true, fontFamily: 'Ahem'),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(disableAnimations: true, textScaler: TextScaler.noScaling),
        child: child!,
      ),
      home: StudyFocusClockScope(
        now: () => DateTime(2026, 8, 11, 9, 30),
        child: RepaintBoundary(key: _goldenRootKey, child: home),
      ),
    ),
  );
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pump(const Duration(milliseconds: 500));
  if (sdk != null) addTearDown(sdk.close);
}

StudyRoomSdk _goldenSdk() => StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('https://example.com'),
    realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
    tokenProvider: (_) async => StudyRoomAccessToken(
      token: 'golden-token',
      expiresAt: DateTime.utc(2100),
    ),
    transport: _GoldenTransport(),
    realtimeConnector: _UnusedRealtimeConnector(),
  ),
);

class _GoldenScenario {
  const _GoldenScenario({
    required this.name,
    required this.size,
    this.style,
    this.section,
    this.roomManagement = false,
  });

  final String name;
  final Size size;
  final StudyFocusVisualStyle? style;
  final StudyFocusDesktopSection? section;
  final bool roomManagement;
}

class _GoldenSoundPlayer implements StudySoundPlayer {
  @override
  Future<void> dispose() async {}

  @override
  Future<void> pause() async {}

  @override
  Future<void> play(StudySoundTrack track, {double volume = 0.5}) async {}

  @override
  Future<void> setVolume(double volume) async {}
}

class _GoldenTransport implements StudyRoomTransport {
  @override
  Future<void> close() async {}

  @override
  Future<Map<String, dynamic>?> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (path.startsWith('/v1/rooms?')) {
      return {
        'items': [_roomJson()],
        'nextCursor': null,
      };
    }
    if (path == '/v1/join-requests' || path.startsWith('/v1/join-requests?')) {
      return {'items': <dynamic>[], 'nextCursor': null};
    }
    throw StateError('Unexpected golden request: $method $path');
  }
}

class _UnusedRealtimeConnector implements StudyRoomRealtimeConnector {
  @override
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}

Map<String, dynamic> _roomJson() => {
  'id': 'room-1',
  'appId': 'app-1',
  'title': 'Focus Room',
  'version': 1,
  'members': [
    {
      'id': 'owner-1',
      'displayName': 'You',
      'avatarUrl': '',
      'role': 'owner',
      'status': 'focusing',
    },
    {
      'id': 'member-1',
      'displayName': 'Lin',
      'avatarUrl': '',
      'role': 'member',
      'status': 'online',
    },
  ],
};
