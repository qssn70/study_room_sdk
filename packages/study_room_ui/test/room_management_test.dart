import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:study_room_sdk/study_room_sdk.dart';
import 'package:study_room_ui/study_room_ui.dart';

void main() {
  testWidgets('lobby renders localized rooms and request actions', (
    tester,
  ) async {
    final transport = _ManagementTransport();
    final sdk = _sdk(transport);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
        supportedLocales: StudyRoomLocalizations.supportedLocales,
        home: StudyRoomLobbyView(sdk: sdk, currentUserId: 'owner-1'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('自习房间'), findsOneWidget);
    expect(find.text('Focus Room'), findsOneWidget);
    expect(find.byTooltip('申请加入'), findsOneWidget);
    await sdk.close();
  });

  testWidgets('owner inbox approves a pending request', (tester) async {
    final transport = _ManagementTransport();
    final sdk = _sdk(transport);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
        supportedLocales: StudyRoomLocalizations.supportedLocales,
        home: Scaffold(
          body: JoinRequestInboxView(sdk: sdk, roomId: 'room-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Ada'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();
    expect(
      transport.requests.any(
        (request) =>
            request.$1 == 'PATCH' &&
            request.$2.endsWith('/join-requests/request-1'),
      ),
      isTrue,
    );
    await sdk.close();
  });

  testWidgets('member management exposes owner-only actions', (tester) async {
    final sdk = _sdk(_ManagementTransport());
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: StudyRoomLocalizations.localizationsDelegates,
        supportedLocales: StudyRoomLocalizations.supportedLocales,
        home: Scaffold(
          body: RoomMemberManagementView(
            sdk: sdk,
            currentUserId: 'owner-1',
            room: StudyRoom.fromJson(_roomJson()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Owner'), findsNWidgets(2));
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);
    await sdk.close();
  });
}

StudyRoomSdk _sdk(StudyRoomTransport transport) => StudyRoomSdk(
  StudyRoomSdkConfig(
    apiBaseUri: Uri.parse('https://example.com'),
    realtimeUri: Uri.parse('wss://example.com/v1/realtime'),
    tokenProvider: (_) async => StudyRoomAccessToken(
      token: 'token',
      expiresAt: DateTime.now().add(const Duration(hours: 1)),
    ),
    transport: transport,
    realtimeConnector: _UnusedConnector(),
  ),
);

Map<String, dynamic> _roomJson() => {
  'id': 'room-1',
  'appId': 'app-1',
  'title': 'Focus Room',
  'version': 2,
  'members': [
    {
      'id': 'owner-1',
      'displayName': 'Owner',
      'avatarUrl': '',
      'role': 'owner',
      'status': 'online',
    },
    {
      'id': 'member-1',
      'displayName': 'Member',
      'avatarUrl': '',
      'role': 'member',
      'status': 'idle',
    },
  ],
};

Map<String, dynamic> _requestJson() => {
  'id': 'request-1',
  'roomId': 'room-1',
  'userId': 'member-2',
  'displayName': 'Ada',
  'status': 'pending',
  'createdAt': '2026-08-09T00:00:00Z',
  'updatedAt': '2026-08-09T00:00:00Z',
};

class _ManagementTransport implements StudyRoomTransport {
  final requests = <(String, String)>[];
  var approved = false;

  @override
  Future<Map<String, dynamic>?> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    requests.add((method, path));
    if (path.startsWith('/v1/rooms?')) {
      return {
        'items': [_roomJson()],
        'nextCursor': null,
      };
    }
    if (path == '/v1/join-requests' || path.startsWith('/v1/join-requests?')) {
      return {'items': <dynamic>[], 'nextCursor': null};
    }
    if ((path == '/v1/rooms/room-1/join-requests' ||
            path.startsWith('/v1/rooms/room-1/join-requests?')) &&
        method == 'GET') {
      return {
        'items': approved ? <dynamic>[] : [_requestJson()],
        'nextCursor': null,
      };
    }
    if (path.endsWith('/join-requests/request-1') && method == 'PATCH') {
      approved = true;
      return {..._requestJson(), 'status': body!['decision']};
    }
    if (path == '/v1/rooms/room-1') return _roomJson();
    throw StateError('Unexpected request: $method $path');
  }

  @override
  Future<void> close() async {}
}

class _UnusedConnector implements StudyRoomRealtimeConnector {
  @override
  Future<StudyRoomRealtimeConnection> connect(
    Uri url, {
    required StudyRoomAccessToken token,
    StudyRoomCancellationToken? cancellationToken,
  }) => throw UnimplementedError();
}
