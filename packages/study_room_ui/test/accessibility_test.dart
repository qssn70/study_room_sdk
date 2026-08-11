import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart' show SemanticsFlag;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  testWidgets(
    'member and companion states expose one localized semantic node',
    (tester) async {
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _localizedApp(
          locale: const Locale('zh'),
          home: const Column(
            children: [
              Expanded(
                child: MemberGrid(
                  members: [
                    StudyMember(
                      id: 'member-1',
                      displayName: 'Lin',
                      avatarUrl: '',
                      status: PresenceStatus.focusing,
                    ),
                  ],
                ),
              ),
              SilentCompanionList(
                currentUserId: 'owner',
                members: [
                  StudyMember(
                    id: 'member-1',
                    displayName: 'Lin',
                    avatarUrl: '',
                    status: PresenceStatus.focusing,
                  ),
                ],
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.bySemanticsLabel('Lin, 专注中'), findsNWidgets(2));

      await tester.pumpWidget(
        _localizedApp(
          home: const MemberGrid(
            members: [
              StudyMember(
                id: 'member-1',
                displayName: 'Lin',
                avatarUrl: '',
                status: PresenceStatus.focusing,
              ),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Lin, Focusing'), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('connection state is announced as a live region', (tester) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _localizedApp(
        home: const RoomHeader(
          title: 'Focus Room',
          memberCount: 2,
          connected: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    final reconnecting = find.bySemanticsLabel('Reconnecting');
    expect(reconnecting, findsOneWidget);
    expect(
      tester.getSemantics(reconnecting),
      isSemantics(label: 'Reconnecting', isLiveRegion: true),
    );
    semantics.dispose();
  });

  testWidgets('primary icon controls keep 48 by 48 touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        home: FocusTimer(
          elapsed: const Duration(minutes: 25),
          status: StudySessionStatus.running,
          onStart: () {},
          onPause: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    for (final tooltip in const ['Pause', 'Finish']) {
      final size = tester.getSize(find.byTooltip(tooltip));
      expect(size.width, greaterThanOrEqualTo(48));
      expect(size.height, greaterThanOrEqualTo(48));
    }
  });

  testWidgets('timer controls keep tab order and Enter or Space activation', (
    tester,
  ) async {
    var started = false;
    var finished = false;
    await tester.pumpWidget(
      _localizedApp(
        home: FocusTimer(
          elapsed: const Duration(minutes: 25),
          status: StudySessionStatus.idle,
          onStart: () => started = true,
          onPause: () {},
          onFinish: () => finished = true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(started, isTrue);
    expect(finished, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    expect(finished, isTrue);
  });

  testWidgets('room header and members fit a narrow phone viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _localizedApp(
        home: const Column(
          children: [
            RoomHeader(
              title: 'A long room title that must truncate',
              memberCount: 12,
              connected: true,
            ),
            Expanded(
              child: MemberGrid(
                members: [
                  StudyMember(
                    id: 'member-1',
                    displayName: 'A long display name',
                    avatarUrl: '',
                    status: PresenceStatus.online,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('room primitives render at 200 percent text scaling', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      _localizedApp(
        textScaler: const TextScaler.linear(2),
        home: StudyRoomView(
          room: StudyRoom(
            id: 'room-1',
            appId: 'app-1',
            title: 'Accessible Focus Room',
            version: 1,
            members: [
              StudyMember(
                id: 'member-1',
                displayName: 'Lin',
                avatarUrl: '',
                status: PresenceStatus.online,
              ),
            ],
          ),
          elapsed: const Duration(minutes: 25),
          sessionStatus: StudySessionStatus.idle,
          messages: const [],
          onStart: () {},
          onPause: () {},
          onSendMessage: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
  });

  testWidgets('decorative backgrounds stay out of the semantics tree', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();

    await tester.pumpWidget(
      _localizedApp(
        home: StudyBackgroundLayer(
          background: StudyBackground.image(
            image: MemoryImage(
              base64Decode(
                'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII=',
              ),
            ),
          ),
          child: Semantics(
            label: 'Focus content',
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final backgroundImage = tester.widget<Image>(find.byType(Image));
    expect(backgroundImage.excludeFromSemantics, isFalse);
    expect(find.semantics.byFlag(SemanticsFlag.isImage), findsNothing);
    expect(find.semantics.byLabel('Focus content'), findsOne);
    semantics.dispose();
  });

  test('default status and accent colors meet non-text AA contrast', () {
    const theme = StudyRoomTheme();
    expect(
      _contrastRatio(theme.activeColor, theme.surfaceColor),
      greaterThan(3),
    );
    expect(_contrastRatio(Colors.green.shade700, Colors.white), greaterThan(3));
    expect(
      _contrastRatio(Colors.orange.shade800, Colors.white),
      greaterThan(3),
    );
  });
}

double _contrastRatio(Color first, Color second) {
  final firstLuminance = first.computeLuminance();
  final secondLuminance = second.computeLuminance();
  final lighter = firstLuminance > secondLuminance
      ? firstLuminance
      : secondLuminance;
  final darker = firstLuminance > secondLuminance
      ? secondLuminance
      : firstLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

Widget _localizedApp({
  Locale locale = const Locale('en'),
  TextScaler textScaler = TextScaler.noScaling,
  required Widget home,
}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
    supportedLocales: StudyRoomLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: textScaler),
      child: child!,
    ),
    home: Scaffold(body: home),
  );
}
