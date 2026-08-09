import 'package:study_room_sdk/study_room_sdk.dart';

Future<void> main() async {
  final sdk = StudyRoomSdk(
    StudyRoomSdkConfig(
      apiBaseUri: Uri.parse('https://study.example.com'),
      realtimeUri: Uri.parse('wss://study.example.com/v1/realtime'),
      tokenProvider: issueToken,
    ),
  );
  await sdk.start();
  try {
    final rooms = await sdk.rooms.list();
    if (rooms.items.isNotEmpty) await sdk.rooms.subscribe(rooms.items.first.id);
  } finally {
    await sdk.close();
  }
}

Future<StudyRoomAccessToken> issueToken(StudyRoomTokenRequest request) async =>
    StudyRoomAccessToken(
      value: 'replace-with-a-token-from-your-backend',
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
