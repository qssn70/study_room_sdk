import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:http/http.dart' as http;
import 'package:study_room_sdk/study_room_sdk.dart';

@JS('globalThis.__studyRoomE2eResult')
external set _browserResult(JSString value);

Future<void> main() async {
  final startedAt = DateTime.now().toUtc();
  final runId = 'chrome-${startedAt.microsecondsSinceEpoch}';
  final apiBase = Uri.parse('http://127.0.0.1:3000');
  final jwksBase = Uri.parse('http://127.0.0.1:4000');
  final assertions = <String, bool>{};
  final ownerStates = <String>[];
  final memberStates = <String>[];
  final resources = <String, String>{};
  StudyRoomSdk? owner;
  StudyRoomSdk? member;
  Map<String, Object?> result;

  try {
    owner = _sdk(
      apiBase,
      jwksBase,
      userId: 'chrome-owner-$runId',
      displayName: 'Chrome Owner',
    );
    member = _sdk(
      apiBase,
      jwksBase,
      userId: 'chrome-member-$runId',
      displayName: 'Chrome Member',
    );
    final ownerStateSubscription = owner.connectionStates.listen(
      (state) => ownerStates.add(state.name),
    );
    final memberStateSubscription = member.connectionStates.listen(
      (state) => memberStates.add(state.name),
    );

    await Future.wait([owner.start(), member.start()]);
    final connectedClients = await Future.wait([
      _waitForConnected(owner),
      _waitForConnected(member),
    ]);
    assertions['socketIoConnected'] = connectedClients.every(
      (connected) => connected,
    );

    final room = await owner.rooms.create(
      'Chrome CORS $runId',
      idempotencyKey: 'chrome.room.$runId',
    );
    resources['roomId'] = room.id;
    assertions['restCorsCreate'] = room.title == 'Chrome CORS $runId';

    final request = await member.joinRequests.request(room.id);
    final inbox = await owner.joinRequests.forRoom(room.id);
    await owner.joinRequests.decide(
      room.id,
      inbox.items.singleWhere((item) => item.id == request.id).id,
      JoinRequestStatus.approved,
    );
    await Future.wait([
      owner.rooms.subscribe(room.id),
      member.rooms.subscribe(room.id),
    ]);
    assertions['twoUserSubscription'] =
        member
            .roomSnapshot(room.id)
            ?.members
            .any((item) => item.id == 'chrome-member-$runId') ??
        false;

    final chatText = 'chrome-message-$runId';
    final chatSeen = Completer<void>();
    final chatSubscription = member.events
        .where(
          (event) =>
              event.type == 'chat.message.created' &&
              event.payload['text'] == chatText,
        )
        .listen((_) {
          if (!chatSeen.isCompleted) chatSeen.complete();
        });
    final message = await owner.chat.send(
      room.id,
      chatText,
      idempotencyKey: 'chrome.message.$runId',
    );
    resources['messageId'] = message.id;
    await chatSeen.future.timeout(const Duration(seconds: 15));
    assertions['socketIoChatEvent'] = true;

    final sessionSeen = Completer<void>();
    final sessionSubscription = owner.events
        .where(
          (event) =>
              event.type == 'session.updated' &&
              event.payload['userId'] == 'chrome-member-$runId' &&
              event.payload['status'] == 'running',
        )
        .listen((_) {
          if (!sessionSeen.isCompleted) sessionSeen.complete();
        });
    final session = await member.sessions.start(
      room.id,
      idempotencyKey: 'chrome.session.$runId',
    );
    resources['sessionId'] = session.id;
    await sessionSeen.future.timeout(const Duration(seconds: 15));
    assertions['socketIoSessionEvent'] = true;

    await member.sessions.update(session.id, StudySessionStatus.finished);
    await owner.rooms.delete(room.id);
    assertions['roomClosed'] = owner.roomSnapshot(room.id) == null;

    await Future.wait([
      chatSubscription.cancel(),
      sessionSubscription.cancel(),
      ownerStateSubscription.cancel(),
      memberStateSubscription.cancel(),
    ]);
    _requireAll(assertions);
    result = {
      'schemaVersion': 1,
      'scenario': 'real-chrome-sdk-cors-socketio',
      'runId': runId,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'success': true,
      'assertions': assertions,
      'connectionStates': {'owner': ownerStates, 'member': memberStates},
      'resources': resources,
    };
  } catch (error, stackTrace) {
    result = {
      'schemaVersion': 1,
      'scenario': 'real-chrome-sdk-cors-socketio',
      'runId': runId,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'success': false,
      'assertions': assertions,
      'connectionStates': {'owner': ownerStates, 'member': memberStates},
      'resources': resources,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    };
  } finally {
    await Future.wait([
      if (owner != null) owner.close(),
      if (member != null) member.close(),
    ]);
  }

  _browserResult = jsonEncode(result).toJS;
}

Future<bool> _waitForConnected(StudyRoomSdk sdk) async {
  try {
    await sdk.connectionStates
        .firstWhere((state) => state == StudyRoomConnectionState.connected)
        .timeout(const Duration(seconds: 5));
    return true;
  } on TimeoutException {
    return false;
  }
}

StudyRoomSdk _sdk(
  Uri apiBase,
  Uri jwksBase, {
  required String userId,
  required String displayName,
}) {
  return StudyRoomSdk(
    StudyRoomSdkConfig(
      apiBaseUri: apiBase,
      realtimeUri: apiBase.replace(scheme: 'ws', path: '/v1/realtime'),
      tokenProvider: (_) =>
          _token(jwksBase, userId: userId, displayName: displayName),
      requestTimeout: const Duration(seconds: 15),
      realtimeConnectTimeout: const Duration(seconds: 15),
      reconnectBaseDelay: const Duration(milliseconds: 250),
    ),
  );
}

Future<StudyRoomAccessToken> _token(
  Uri jwksBase, {
  required String userId,
  required String displayName,
}) async {
  final response = await http.post(
    jwksBase.resolve('/token'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'sub': userId,
      'displayName': displayName,
      'appId': 'demo',
    }),
  );
  if (response.statusCode != 200) {
    throw StateError(
      'Token fixture failed: ${response.statusCode} ${response.body}',
    );
  }
  final body = jsonDecode(response.body) as Map<String, dynamic>;
  return StudyRoomAccessToken(
    token: body['accessToken'] as String,
    expiresAt: DateTime.parse(body['expiresAt'] as String),
  );
}

void _requireAll(Map<String, bool> assertions) {
  final failed = assertions.entries
      .where((entry) => !entry.value)
      .map((entry) => entry.key)
      .toList(growable: false);
  if (failed.isNotEmpty) {
    throw StateError('Failed assertions: ${failed.join(', ')}');
  }
}
