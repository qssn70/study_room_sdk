import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:study_room_sdk/study_room_sdk.dart';

Future<void> main() async {
  final startedAt = DateTime.now().toUtc();
  final apiBase = Uri.parse(
    Platform.environment['SDK_E2E_API'] ?? 'http://127.0.0.1:3000',
  );
  final jwksBase = Uri.parse(
    Platform.environment['SDK_E2E_JWKS'] ?? 'http://127.0.0.1:4000',
  );
  final runId =
      Platform.environment['SDK_E2E_RUN_ID'] ??
      'dart-${startedAt.microsecondsSinceEpoch}';
  final resultPath = Platform.environment['SDK_E2E_RESULT_PATH'];
  final ownerStates = <String>[];
  final memberStates = <String>[];
  final assertions = <String, bool>{};
  StudyRoomSdk? owner;
  StudyRoomSdk? member;

  try {
    owner = _sdk(
      apiBase,
      jwksBase,
      userId: 'sdk-owner-$runId',
      displayName: 'Dart SDK Owner',
    );
    member = _sdk(
      apiBase,
      jwksBase,
      userId: 'sdk-member-$runId',
      displayName: 'Dart SDK Member',
    );
    final ownerStateSubscription = owner.connectionStates.listen(
      (state) => ownerStates.add(state.name),
    );
    final memberStateSubscription = member.connectionStates.listen(
      (state) => memberStates.add(state.name),
    );

    await Future.wait([owner.start(), member.start()]);
    assertions['clientsConnected'] =
        ownerStates.contains(StudyRoomConnectionState.connected.name) &&
        memberStates.contains(StudyRoomConnectionState.connected.name);

    final roomKey = 'room.$runId';
    final concurrentRooms = await Future.wait([
      owner.rooms.create('Real SDK $runId', idempotencyKey: roomKey),
      owner.rooms.create('Real SDK $runId', idempotencyKey: roomKey),
    ]);
    final room = concurrentRooms.first;
    final replayedRoom = concurrentRooms.last;
    assertions['roomReplayed'] = replayedRoom.id == room.id;
    assertions['roomConcurrentReplay'] =
        concurrentRooms.map((item) => item.id).toSet().length == 1;

    final request = await member.joinRequests.request(room.id);
    final inbox = await owner.joinRequests.forRoom(room.id);
    final pending = inbox.items.singleWhere(
      (candidate) => candidate.id == request.id,
    );
    await owner.joinRequests.decide(
      room.id,
      pending.id,
      JoinRequestStatus.approved,
    );
    await Future.wait([
      owner.rooms.subscribe(room.id),
      member.rooms.subscribe(room.id),
    ]);
    assertions['memberApproved'] =
        member
            .roomSnapshot(room.id)
            ?.members
            .any((candidate) => candidate.id == 'sdk-member-$runId') ??
        false;

    var replayedRoomEvents = 0;
    final roomEvents = owner.events
        .where((event) => event.type == 'room.state' && event.roomId == room.id)
        .listen((_) => replayedRoomEvents += 1);
    await owner.rooms.create('Real SDK $runId', idempotencyKey: roomKey);
    await Future<void>.delayed(const Duration(milliseconds: 500));
    assertions['roomReplayPublishedNoEvent'] = replayedRoomEvents == 0;

    final chatText = 'hello-from-real-sdk-$runId';
    var chatEvents = 0;
    final chatEventSeen = Completer<void>();
    final chatEventsSubscription = member.events
        .where(
          (event) =>
              event.type == 'chat.message.created' &&
              event.payload['text'] == chatText,
        )
        .listen((_) {
          chatEvents += 1;
          if (!chatEventSeen.isCompleted) chatEventSeen.complete();
        });
    final messageKey = 'message.$runId';
    final concurrentMessages = await Future.wait([
      owner.chat.send(room.id, chatText, idempotencyKey: messageKey),
      owner.chat.send(room.id, chatText, idempotencyKey: messageKey),
    ]);
    final message = concurrentMessages.first;
    await chatEventSeen.future.timeout(const Duration(seconds: 10));
    final replayedMessage = concurrentMessages.last;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    assertions['messageReplayed'] = replayedMessage.id == message.id;
    assertions['messageConcurrentReplay'] =
        concurrentMessages.map((item) => item.id).toSet().length == 1;
    assertions['singleChatEvent'] = chatEvents == 1;

    var sessionEvents = 0;
    final sessionEventSeen = Completer<void>();
    final sessionEventsSubscription = owner.events
        .where(
          (event) =>
              event.type == 'session.updated' &&
              event.payload['userId'] == 'sdk-member-$runId' &&
              event.payload['status'] == 'running',
        )
        .listen((_) {
          sessionEvents += 1;
          if (!sessionEventSeen.isCompleted) sessionEventSeen.complete();
        });
    final sessionKey = 'session.$runId';
    final concurrentSessions = await Future.wait([
      member.sessions.start(room.id, idempotencyKey: sessionKey),
      member.sessions.start(room.id, idempotencyKey: sessionKey),
    ]);
    final session = concurrentSessions.first;
    await sessionEventSeen.future.timeout(const Duration(seconds: 10));
    final replayedSession = concurrentSessions.last;
    await Future<void>.delayed(const Duration(milliseconds: 500));
    assertions['sessionReplayed'] = replayedSession.id == session.id;
    assertions['sessionConcurrentReplay'] =
        concurrentSessions.map((item) => item.id).toSet().length == 1;
    assertions['singleSessionEvent'] = sessionEvents == 1;

    final thirdSession = await member.sessions.start(
      room.id,
      idempotencyKey: sessionKey,
    );
    assertions['sameSessionRequestStillReplays'] =
        thirdSession.id == session.id;
    try {
      await owner.chat.send(
        room.id,
        '$chatText-conflict',
        idempotencyKey: messageKey,
      );
      assertions['requestConflictRejected'] = false;
    } on StudyRoomException catch (error) {
      assertions['requestConflictRejected'] =
          error.statusCode == 409 && error.code == 'idempotency_conflict';
    }

    await member.sessions.update(session.id, StudySessionStatus.finished);
    await owner.rooms.delete(room.id);
    assertions['roomClosed'] = owner.roomSnapshot(room.id) == null;
    try {
      await owner.rooms.create('Real SDK $runId', idempotencyKey: roomKey);
      assertions['unavailableReplayRejected'] = false;
    } on StudyRoomException catch (error) {
      assertions['unavailableReplayRejected'] =
          error.statusCode == 409 &&
          error.code == 'idempotency_result_unavailable';
    }

    final legacyRoom = await owner.rooms.create('Legacy no-key $runId');
    await owner.rooms.subscribe(legacyRoom.id);
    final legacyMessage = await owner.chat.send(
      legacyRoom.id,
      'legacy-no-key-message',
    );
    final legacySession = await owner.sessions.start(legacyRoom.id);
    await owner.sessions.update(legacySession.id, StudySessionStatus.finished);
    await owner.rooms.delete(legacyRoom.id);
    assertions['legacyNoKeyFlow'] =
        legacyMessage.roomId == legacyRoom.id &&
        legacySession.roomId == legacyRoom.id;

    await Future.wait([
      roomEvents.cancel(),
      chatEventsSubscription.cancel(),
      sessionEventsSubscription.cancel(),
      ownerStateSubscription.cancel(),
      memberStateSubscription.cancel(),
    ]);
    _requireAll(assertions);
    await _writeResult(resultPath, {
      'schemaVersion': 1,
      'scenario': 'real-dart-sdk-core',
      'runId': runId,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'success': true,
      'assertions': assertions,
      'connectionStates': {'owner': ownerStates, 'member': memberStates},
      'resources': {
        'roomId': room.id,
        'messageId': message.id,
        'sessionId': session.id,
      },
    });
    stdout.writeln('Real Dart SDK E2E passed: ${jsonEncode(assertions)}');
  } catch (error, stackTrace) {
    await _writeResult(resultPath, {
      'schemaVersion': 1,
      'scenario': 'real-dart-sdk-core',
      'runId': runId,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'success': false,
      'assertions': assertions,
      'connectionStates': {'owner': ownerStates, 'member': memberStates},
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    stderr.writeln('Real Dart SDK E2E failed: $error');
    stderr.writeln(stackTrace);
    rethrow;
  } finally {
    await Future.wait([
      if (owner != null) owner.close(),
      if (member != null) member.close(),
    ]);
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
      realtimeUri: apiBase.replace(
        scheme: apiBase.scheme == 'https' ? 'wss' : 'ws',
        path: '/v1/realtime',
      ),
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

Future<void> _writeResult(String? path, Map<String, Object?> result) async {
  if (path == null || path.isEmpty) return;
  final file = File(path);
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${const JsonEncoder.withIndent('  ').convert(result)}\n',
  );
}
