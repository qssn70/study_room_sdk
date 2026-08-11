import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  test(
    'documented focus and room API remains available from package barrel',
    () {
      const copy = StudyRoomCopy(connected: 'Online now');
      const theme = StudyRoomTheme();
      const view = StudyFocusKitView();
      final background = studyFocusDefaultBackground;
      final soundTrack = StudySoundTrack.builtIns.first;

      expect(copy.connected, 'Online now');
      expect(copy.emptyMembers, isNull);
      expect(theme.activeColor, const Color(0xFF2563EB));
      expect(view.visualStyle, StudyFocusVisualStyle.immersiveDock);
      expect(view.initialDesktopSection, StudyFocusDesktopSection.focus);
      expect(background.type, StudyBackgroundType.gradient);
      expect(soundTrack.id, isNotEmpty);
    },
  );

  test('documented builder typedefs remain source-compatible', () {
    final StudyFocusDesktopPageBuilder pageBuilder =
        (context, section, defaultPage) => defaultPage;
    final StudyTaskEditor taskEditor = (context, date, existing) async =>
        existing;
    const task = StudyTaskRecord(id: 'task-1', title: 'Read', completed: false);

    expect(pageBuilder, isA<StudyFocusDesktopPageBuilder>());
    expect(taskEditor, isA<StudyTaskEditor>());
    expect(task.title, 'Read');
  });

  test('documented localization integration points remain available', () {
    final direct = StudyRoomLocalizations(const Locale('zh'));
    final LocalizationsDelegate<StudyRoomLocalizations> delegate =
        StudyRoomLocalizations.delegate;
    expect(direct.locale, const Locale('zh'));
    expect(direct.rooms, '自习房间');
    expect(delegate, isNotNull);
    expect(StudyRoomLocalizations.localizationsDelegates, isNotEmpty);
    expect(
      StudyRoomLocalizations.supportedLocales,
      contains(const Locale('en')),
    );
  });

  testWidgets('localization lookup keeps its documented public type', (
    tester,
  ) async {
    late StudyRoomLocalizations localization;
    StudyRoomLocalizations? maybeLocalization;

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
        supportedLocales: StudyRoomLocalizations.supportedLocales,
        home: Builder(
          builder: (context) {
            localization = StudyRoomLocalizations.of(context);
            maybeLocalization = StudyRoomLocalizations.maybeOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(maybeLocalization, same(localization));
    expect(localization.rooms, 'Study rooms');
  });
}
