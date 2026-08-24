part of 'sdk.dart';

/// Membership, removal, and ownership-transfer operations.
class StudyMembersApi {
  StudyMembersApi._(this._sdk);
  final StudyRoomSdk _sdk;

  /// Leaves a joined room and evicts its local synchronized state.
  Future<void> leave(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    await _sdk._request(
      'DELETE',
      '/v1/rooms/${_segment(roomId)}/members/me',
      cancellationToken: cancellationToken,
    );
    await _sdk._unsubscribe(
      roomId,
      cancellationToken: cancellationToken,
      ignoreRealtimeError: true,
    );
  }

  /// Removes [userId] from an owned room.
  Future<void> remove(
    String roomId,
    String userId, {
    StudyRoomCancellationToken? cancellationToken,
  }) => _sdk._request(
    'DELETE',
    '/v1/rooms/${_segment(roomId)}/members/${_segment(userId)}',
    cancellationToken: cancellationToken,
  );

  /// Transfers room ownership to an existing member.
  Future<StudyRoom> transferOwnership(
    String roomId,
    String userId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'PUT',
      '/v1/rooms/${_segment(roomId)}/owner',
      body: {'userId': userId},
      cancellationToken: cancellationToken,
    );
    final room = StudyRoom.fromJson(value!);
    _sdk._publishRoom(room);
    return room;
  }
}
