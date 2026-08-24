import 'dart:async';

import 'errors.dart';
import 'models.dart';
import 'realtime.dart';
import 'transport.dart';

part 'sdk_chat_api.dart';
part 'sdk_join_requests_api.dart';
part 'sdk_lifecycle.dart';
part 'sdk_sync_cache.dart';
part 'sdk_members_api.dart';
part 'sdk_rooms_api.dart';
part 'sdk_sessions_api.dart';

/// Clock hook used to make token refresh and synchronization deterministic.
typedef StudyRoomClock = DateTime Function();

/// Immutable runtime configuration for [StudyRoomSdk].
class StudyRoomSdkConfig {
  const StudyRoomSdkConfig({
    required this.apiBaseUri,
    required this.realtimeUri,
    required this.tokenProvider,
    this.requestTimeout = const Duration(seconds: 15),
    this.realtimeAckTimeout = const Duration(seconds: 5),
    this.realtimeConnectTimeout = const Duration(seconds: 10),
    this.tokenRefreshSkew = const Duration(seconds: 30),
    this.reconnectBaseDelay = const Duration(seconds: 1),
    this.clock,
    this.transport,
    this.realtimeConnector,
  });

  final Uri apiBaseUri;
  final Uri realtimeUri;
  final StudyRoomTokenProvider tokenProvider;
  final Duration requestTimeout;
  final Duration realtimeAckTimeout;
  final Duration realtimeConnectTimeout;
  final Duration tokenRefreshSkew;
  final Duration reconnectBaseDelay;
  final StudyRoomClock? clock;
  final StudyRoomTransport? transport;
  final StudyRoomRealtimeConnector? realtimeConnector;
}

String _segment(String value) => Uri.encodeComponent(value);

String _withQuery(String path, Map<String, String?> values) {
  final query = values.entries
      .where((entry) => entry.value != null)
      .map(
        (entry) =>
            '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value!)}',
      )
      .join('&');
  return query.isEmpty ? path : '$path?$query';
}

Map<String, String> _idempotencyHeaders(String? key) {
  if (key == null) return const {};
  if (!RegExp(r'^[A-Za-z0-9._:-]{1,128}$').hasMatch(key)) {
    throw const StudyRoomException(
      'Idempotency key must contain 1 to 128 A-Z, a-z, 0-9, dot, underscore, colon, or hyphen characters',
      kind: StudyRoomExceptionKind.validation,
      code: 'invalid_idempotency_key',
    );
  }
  return {'Idempotency-Key': key};
}
