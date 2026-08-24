import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:test/test.dart';

void main() {
  test('0.4.1 public barrel remains source compatible', () async {
    final config = StudyRoomSdkConfig(
      apiBaseUri: Uri.parse('https://api.example.test'),
      realtimeUri: Uri.parse('wss://api.example.test/v1/realtime'),
      tokenProvider: (_) async => StudyRoomAccessToken(
        token: 'token',
        expiresAt: DateTime.now().add(const Duration(hours: 1)),
      ),
    );
    final sdk = StudyRoomSdk(config);
    final StudyRoomsApi rooms = sdk.rooms;
    final StudyJoinRequestsApi joinRequests = sdk.joinRequests;
    final StudyMembersApi members = sdk.members;
    final StudySessionsApi sessions = sdk.sessions;
    final StudyChatApi chat = sdk.chat;
    final StudyRoomCancellationToken cancellation =
        StudyRoomCancellationToken();
    final StudyStore store = MemoryStudyStore();
    final StudyBackupStore backupStore = store as StudyBackupStore;
    final backup = await backupStore.exportBackup();

    expect(studyRoomContractVersion, '0.4.1');
    expect(rooms, isNotNull);
    expect(joinRequests, isNotNull);
    expect(members, isNotNull);
    expect(sessions, isNotNull);
    expect(chat, isNotNull);
    expect(cancellation.isCancelled, isFalse);
    expect(backup.schemaVersion, StudyDataBackup.currentSchemaVersion);
    expect(StudyBackupImportMode.values, hasLength(2));
    expect(StudyRoomExceptionKind.values, isNotEmpty);
    expect(PomodoroPreset.values, hasLength(3));
    expect(StudyReportRange.values, hasLength(3));
    await sdk.close();
  });

  test(
    'idempotent create signatures remain optional named parameters',
    () async {
      final sdk = StudyRoomSdk(
        StudyRoomSdkConfig(
          apiBaseUri: Uri.parse('https://api.example.test'),
          realtimeUri: Uri.parse('wss://api.example.test/v1/realtime'),
          tokenProvider: (_) async => StudyRoomAccessToken(
            token: 'token',
            expiresAt: DateTime.now().add(const Duration(hours: 1)),
          ),
        ),
      );
      Future<StudyRoom> Function(
        String, {
        String? idempotencyKey,
        StudyRoomCancellationToken? cancellationToken,
      })
      roomCreate = sdk.rooms.create;
      Future<ChatMessage> Function(
        String,
        String, {
        String? idempotencyKey,
        StudyRoomCancellationToken? cancellationToken,
      })
      chatSend = sdk.chat.send;
      Future<StudySessionState> Function(
        String, {
        String? idempotencyKey,
        StudyRoomCancellationToken? cancellationToken,
      })
      sessionStart = sdk.sessions.start;

      expect(roomCreate, isNotNull);
      expect(chatSend, isNotNull);
      expect(sessionStart, isNotNull);
      await sdk.close();
    },
  );
}
