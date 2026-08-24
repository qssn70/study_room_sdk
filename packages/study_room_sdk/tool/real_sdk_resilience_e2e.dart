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
      'resilience-${startedAt.microsecondsSinceEpoch}';
  final resultPath = Platform.environment['SDK_E2E_RESULT_PATH'];
  final readyPath = Platform.environment['SDK_E2E_READY_PATH'];
  final fixtureControlToken =
      Platform.environment['E2E_FIXTURE_CONTROL_TOKEN'] ?? '';
  final assertions = <String, bool>{};
  final states = <String>[];
  final forceRefreshRequests = <DateTime>[];
  final reconnectComplete = Completer<void>();
  var reconnectStarted = false;
  StudyRoomAccessToken? initialToken;
  StudyRoomSdk? sdk;
  StreamSubscription<StudyRoomConnectionState>? stateSubscription;
  String? roomId;

  try {
    sdk = StudyRoomSdk(
      StudyRoomSdkConfig(
        apiBaseUri: apiBase,
        realtimeUri: apiBase.replace(scheme: 'ws', path: '/v1/realtime'),
        tokenProvider: (request) async {
          if (request.forceRefresh) {
            forceRefreshRequests.add(DateTime.now().toUtc());
          }
          final token = await _token(
            jwksBase,
            userId: 'sdk-resilience-$runId',
            displayName: 'SDK Resilience',
            lifetimeSeconds: 30,
          );
          initialToken ??= token;
          return token;
        },
        requestTimeout: const Duration(seconds: 10),
        realtimeAckTimeout: const Duration(seconds: 5),
        realtimeConnectTimeout: const Duration(seconds: 10),
        tokenRefreshSkew: const Duration(seconds: 20),
        reconnectBaseDelay: const Duration(milliseconds: 250),
      ),
    );
    stateSubscription = sdk.connectionStates.listen((state) {
      states.add(state.name);
      if (state == StudyRoomConnectionState.reconnecting) {
        reconnectStarted = true;
      }
      if (reconnectStarted &&
          state == StudyRoomConnectionState.connected &&
          !reconnectComplete.isCompleted) {
        reconnectComplete.complete();
      }
    });

    await sdk.start();
    final room = await sdk.rooms.create(
      'SDK resilience $runId',
      idempotencyKey: 'resilience.room.$runId',
    );
    roomId = room.id;
    await sdk.rooms.subscribe(room.id);
    assertions['initialConnection'] =
        sdk.syncState.rooms.containsKey(room.id) &&
        states.contains(StudyRoomConnectionState.connected.name);

    await _fixtureControl(
      jwksBase,
      fixtureControlToken,
      application: 'demo',
      action: 'rotate',
    );
    await _waitUntil(
      () =>
          forceRefreshRequests.isNotEmpty &&
          states.contains(StudyRoomConnectionState.refreshing.name),
      timeout: const Duration(seconds: 20),
      description: 'automatic short-lived token refresh',
    );
    await _waitUntil(
      () => states.last == StudyRoomConnectionState.connected.name,
      timeout: const Duration(seconds: 20),
      description: 'connection after token refresh',
    );
    assertions['shortTokenForceRefresh'] = forceRefreshRequests.isNotEmpty;
    assertions['rotationReconnect'] =
        states.contains(StudyRoomConnectionState.refreshing.name) &&
        sdk.syncState.rooms.containsKey(room.id);

    await _fixtureControl(
      jwksBase,
      fixtureControlToken,
      application: 'demo',
      action: 'retire',
    );
    await Future<void>.delayed(const Duration(milliseconds: 2500));
    assertions['retiredOldTokenRejected'] =
        await _roomListStatus(apiBase, initialToken!.token) == 401;
    assertions['retiredKeyCurrentTokenWorks'] =
        (await sdk.rooms.get(room.id)).id == room.id;

    if (readyPath != null && readyPath.isNotEmpty) {
      final ready = File(readyPath);
      await ready.parent.create(recursive: true);
      await ready.writeAsString('ready\n');
    }
    await reconnectComplete.future.timeout(const Duration(seconds: 40));
    await _waitUntil(
      () => sdk!.syncState.rooms.containsKey(room.id),
      timeout: const Duration(seconds: 15),
      description: 'room cache after single-instance failover',
    );
    assertions['singleInstanceReconnect'] =
        states.contains(StudyRoomConnectionState.reconnecting.name) &&
        states
                .where(
                  (state) =>
                      state == StudyRoomConnectionState.synchronizing.name,
                )
                .length >=
            2;
    assertions['authoritativeResync'] =
        sdk.roomSnapshot(room.id)?.id == room.id &&
        (await sdk.rooms.get(room.id)).id == room.id;

    await sdk.rooms.delete(room.id);
    roomId = null;
    _requireAll(assertions);
    await _writeResult(resultPath, {
      'schemaVersion': 1,
      'scenario': 'real-dart-sdk-resilience',
      'runId': runId,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'success': true,
      'assertions': assertions,
      'connectionStates': states,
      'forceRefreshRequests': forceRefreshRequests
          .map((value) => value.toIso8601String())
          .toList(growable: false),
    });
    stdout.writeln(
      'Real Dart SDK resilience E2E passed: ${jsonEncode(assertions)}',
    );
  } catch (error, stackTrace) {
    await _writeResult(resultPath, {
      'schemaVersion': 1,
      'scenario': 'real-dart-sdk-resilience',
      'runId': runId,
      'startedAt': startedAt.toIso8601String(),
      'endedAt': DateTime.now().toUtc().toIso8601String(),
      'success': false,
      'assertions': assertions,
      'connectionStates': states,
      'forceRefreshRequests': forceRefreshRequests
          .map((value) => value.toIso8601String())
          .toList(growable: false),
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    });
    stderr.writeln('Real Dart SDK resilience E2E failed: $error');
    stderr.writeln(stackTrace);
    rethrow;
  } finally {
    if (roomId != null && sdk != null) {
      await sdk.rooms.delete(roomId).catchError((_) {});
    }
    await stateSubscription?.cancel();
    await sdk?.close();
  }
}

Future<StudyRoomAccessToken> _token(
  Uri jwksBase, {
  required String userId,
  required String displayName,
  required int lifetimeSeconds,
}) async {
  final response = await http.post(
    jwksBase.resolve('/token'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode({
      'sub': userId,
      'displayName': displayName,
      'appId': 'demo',
      'lifetimeSeconds': lifetimeSeconds,
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

Future<void> _fixtureControl(
  Uri jwksBase,
  String fixtureControlToken, {
  required String application,
  required String action,
}) async {
  if (fixtureControlToken.isEmpty) {
    throw StateError('E2E_FIXTURE_CONTROL_TOKEN is required');
  }
  final response = await http.post(
    jwksBase.resolve('/__test/keys/$application/$action'),
    headers: {'authorization': 'Bearer $fixtureControlToken'},
  );
  if (response.statusCode != 200) {
    throw StateError(
      'JWKS fixture control failed: ${response.statusCode} ${response.body}',
    );
  }
}

Future<int> _roomListStatus(Uri apiBase, String token) async {
  final response = await http.get(
    apiBase.resolve('/v1/rooms'),
    headers: {'authorization': 'Bearer $token'},
  );
  return response.statusCode;
}

Future<void> _waitUntil(
  bool Function() condition, {
  required Duration timeout,
  required String description,
}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('Timed out waiting for $description', timeout);
    }
    await Future<void>.delayed(const Duration(milliseconds: 100));
  }
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
