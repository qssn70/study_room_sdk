import 'package:flutter/material.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() => runApp(const StudyRoomUiExample());

class StudyRoomUiExample extends StatelessWidget {
  const StudyRoomUiExample({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
    supportedLocales: StudyRoomLocalizations.supportedLocales,
    home: const Scaffold(
      body: StudyFocusKitView(currentUserId: 'example-user'),
    ),
  );
}
