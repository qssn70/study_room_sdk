import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  testWidgets('generated localizations expose the documented host API', (
    tester,
  ) async {
    late StudyRoomLocalizations english;
    late StudyRoomLocalizations chinese;

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('en'),
        home: Builder(
          builder: (context) {
            english = StudyRoomLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(english.rooms, 'Study rooms');
    expect(english.memberCount(2), '2 members');

    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('zh'),
        home: Builder(
          builder: (context) {
            chinese = StudyRoomLocalizations.of(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(chinese.rooms, '自习房间');
    expect(chinese.memberCount(2), '2 位成员');
    expect(chinese.focusAppTitle, '极简自习室');
    expect(chinese.soundRain, '雨声');
    expect(chinese.backgroundForest, '森林');
    expect(StudyRoomLocalizations.supportedLocales, const [
      Locale('en'),
      Locale('zh'),
    ]);
    expect(StudyRoomLocalizations.localizationsDelegates, isNotEmpty);
  });

  testWidgets('room primitives use locale defaults and explicit overrides', (
    tester,
  ) async {
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('zh'),
        home: const Column(
          children: [
            Expanded(child: MemberGrid(members: [])),
            Expanded(
              child: MemberGrid(
                members: [],
                copy: StudyRoomCopy(emptyMembers: 'Custom empty state'),
              ),
            ),
          ],
        ),
      ),
    );

    expect(find.text('暂无成员'), findsOneWidget);
    expect(find.text('Custom empty state'), findsOneWidget);
  });

  testWidgets('presence labels follow the host locale', (tester) async {
    await tester.pumpWidget(
      _localizedApp(
        locale: const Locale('zh'),
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

    expect(find.text('专注中'), findsOneWidget);
  });
}

Widget _localizedApp({required Locale locale, required Widget home}) {
  return MaterialApp(
    locale: locale,
    localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
    supportedLocales: StudyRoomLocalizations.supportedLocales,
    home: Scaffold(body: home),
  );
}
