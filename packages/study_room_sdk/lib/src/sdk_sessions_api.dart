part of 'sdk.dart';

/// Study-session listing, creation, and state-transition operations.
class StudySessionsApi {
  StudySessionsApi._(this._sdk);
  final StudyRoomSdk _sdk;

  /// Lists running and paused sessions in a room.
  Future<StudyRoomPage<StudySessionState>> listActive(
    String roomId, {
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms/${_segment(roomId)}/active-sessions', {
        'cursor': cursor,
        'limit': '$limit',
      }),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.sessionsFromJson(value!);
  }

  /// Starts a study session.
  ///
  /// Reuse [idempotencyKey] only for retries of the same room and user.
  Future<StudySessionState> start(
    String roomId, {
    String? idempotencyKey,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'POST',
      '/v1/rooms/${_segment(roomId)}/sessions',
      headers: _idempotencyHeaders(idempotencyKey),
      cancellationToken: cancellationToken,
    );
    final session = StudySessionState.fromJson(value!);
    _sdk._publishSession(session);
    return session;
  }

  /// Pauses, resumes, or finishes a persisted session.
  Future<StudySessionState> update(
    String sessionId,
    StudySessionStatus status, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (status == StudySessionStatus.idle) {
      throw const StudyRoomException(
        'Idle is not a persisted session state',
        kind: StudyRoomExceptionKind.validation,
        code: 'invalid_session_status',
      );
    }
    final value = await _sdk._request(
      'PATCH',
      '/v1/sessions/${_segment(sessionId)}',
      body: {'status': status.name},
      cancellationToken: cancellationToken,
    );
    final session = StudySessionState.fromJson(value!);
    _sdk._publishSession(session);
    return session;
  }
}
