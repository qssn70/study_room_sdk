import 'package:flutter/material.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  runApp(const StudyRoomExampleApp());
}

class StudyRoomExampleApp extends StatefulWidget {
  const StudyRoomExampleApp({super.key});

  @override
  State<StudyRoomExampleApp> createState() => _StudyRoomExampleAppState();
}

class _StudyRoomExampleAppState extends State<StudyRoomExampleApp> {
  late final StudyRoomSdk sdk;
  late StudyRoom room;
  var elapsed = Duration.zero;
  var sessionStatus = StudySessionStatus.idle;
  final messages = <ChatMessage>[];

  @override
  void initState() {
    super.initState();
    sdk = StudyRoomSdk.initialize(
      StudyRoomConfig(
        apiBaseUrl: Uri.parse('http://localhost:3000'),
        realtimeUrl: Uri.parse('ws://localhost:3000/realtime'),
        tokenProvider: () async => 'replace-with-app-server-jwt',
      ),
    );
    room = const StudyRoom(
      id: 'demo-room',
      title: 'Demo Focus Room',
      members: [
        StudyMember(
          id: 'demo-user',
          displayName: 'You',
          avatarUrl: '',
          status: PresenceStatus.focusing,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF2563EB)),
      home: StudyRoomView(
        room: room,
        elapsed: elapsed,
        sessionStatus: sessionStatus,
        messages: messages,
        onStart: () {
          setState(() {
            sessionStatus = StudySessionStatus.running;
            elapsed = const Duration(minutes: 25);
          });
        },
        onPause: () {
          setState(() => sessionStatus = StudySessionStatus.paused);
        },
        onSendMessage: (text) async {
          setState(() {
            messages.add(
              ChatMessage(
                id: DateTime.now().microsecondsSinceEpoch.toString(),
                roomId: room.id,
                senderId: 'demo-user',
                senderName: 'You',
                text: text,
                sentAt: DateTime.now(),
              ),
            );
          });
        },
      ),
    );
  }
}

