part of 'sdk.dart';

/// Room access request operations for applicants and room owners.
class StudyJoinRequestsApi {
  StudyJoinRequestsApi._(this._sdk);
  final StudyRoomSdk _sdk;

  /// Requests access to a room.
  Future<RoomJoinRequest> request(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'POST',
      '/v1/rooms/${_segment(roomId)}/join-requests',
      cancellationToken: cancellationToken,
    );
    final request = RoomJoinRequest.fromJson(value!);
    _sdk._publishMyRequest(request);
    return request;
  }

  /// Lists the current user's access requests.
  Future<StudyRoomPage<RoomJoinRequest>> mine({
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/join-requests', {'cursor': cursor, 'limit': '$limit'}),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.joinRequestsFromJson(value!);
  }

  /// Lists pending requests for an owned room.
  Future<StudyRoomPage<RoomJoinRequest>> forRoom(
    String roomId, {
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms/${_segment(roomId)}/join-requests', {
        'cursor': cursor,
        'limit': '$limit',
      }),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.joinRequestsFromJson(value!);
  }

  /// Cancels the current user's pending request for [roomId].
  Future<void> cancel(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    await _sdk._request(
      'DELETE',
      '/v1/rooms/${_segment(roomId)}/join-requests',
      cancellationToken: cancellationToken,
    );
    final requests = _sdk._syncState.myJoinRequests
        .where((request) => request.roomId != roomId)
        .toList(growable: false);
    _sdk._publishSyncState(_sdk._copySyncState(myJoinRequests: requests));
  }

  /// Approves or rejects a pending room access request.
  Future<RoomJoinRequest> decide(
    String roomId,
    String requestId,
    JoinRequestStatus decision, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (decision != JoinRequestStatus.approved &&
        decision != JoinRequestStatus.rejected) {
      throw const StudyRoomException(
        'Decision must be approved or rejected',
        kind: StudyRoomExceptionKind.validation,
        code: 'invalid_decision',
      );
    }
    final value = await _sdk._request(
      'PATCH',
      '/v1/rooms/${_segment(roomId)}/join-requests/${_segment(requestId)}',
      body: {'decision': decision.name},
      cancellationToken: cancellationToken,
    );
    final request = RoomJoinRequest.fromJson(value!);
    _sdk._removeOwnerRequest(roomId, requestId);
    return request;
  }
}
