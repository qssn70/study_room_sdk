import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  runApp(const StudyRoomExampleApp());
}

class StudyRoomExampleApp extends StatelessWidget {
  const StudyRoomExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF2563EB),
        useMaterial3: true,
      ),
      home: StudyFocusKitView(
        store: MemoryStudyStore(),
        currentUserId: 'demo-user',
        room: const StudyRoom(
          id: 'demo-room',
          title: 'Demo Focus Room',
          members: [
            StudyMember(
              id: 'demo-user',
              displayName: 'You',
              avatarUrl: '',
              status: PresenceStatus.focusing,
            ),
            StudyMember(
              id: 'demo-friend-1',
              displayName: 'Lin',
              avatarUrl: '',
              status: PresenceStatus.focusing,
            ),
            StudyMember(
              id: 'demo-friend-2',
              displayName: 'Kai',
              avatarUrl: '',
              status: PresenceStatus.away,
            ),
          ],
        ),
        background: const StudyBackground.gradient(
          colors: [Color(0xFFE8F5E9), Color(0xFFF8FAFC)],
          maskOpacity: 0.18,
        ),
      ),
    );
  }
}
