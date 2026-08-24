part of 'sdk.dart';

/// Room creation, listing, lookup, subscription, and deletion operations.
class StudyRoomsApi {
  StudyRoomsApi._(this._sdk);
  final StudyRoomSdk _sdk;

  /// Creates a room.
  ///
  /// Reuse [idempotencyKey] only when retrying the same normalized title.
  /// Omitting it preserves the 0.4.0 request behavior.
  Future<StudyRoom> create(
    String title, {
    String? idempotencyKey,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'POST',
      '/v1/rooms',
      body: {'title': title.trim()},
      headers: _idempotencyHeaders(idempotencyKey),
      cancellationToken: cancellationToken,
    );
    return StudyRoom.fromJson(value!);
  }

  /// Lists rooms joined by the current user.
  Future<StudyRoomPage<StudyRoom>> list({
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms', {'cursor': cursor, 'limit': '$limit'}),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.roomsFromJson(value!);
  }

  /// Gets the current representation of one joined room.
  Future<StudyRoom> get(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      '/v1/rooms/${_segment(roomId)}',
      cancellationToken: cancellationToken,
    );
    return StudyRoom.fromJson(value!);
  }

  /// Subscribes to realtime events and synchronizes the room snapshot.
  Future<StudyRoom> subscribe(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) => _sdk._subscribe(roomId, cancellationToken: cancellationToken);

  /// Leaves the local realtime subscription without leaving the room.
  Future<void> unsubscribe(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) => _sdk._unsubscribe(roomId, cancellationToken: cancellationToken);

  /// Deletes an owned room and evicts its local synchronized state.
  Future<void> delete(
    String roomId, {
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    await _sdk._request(
      'DELETE',
      '/v1/rooms/${_segment(roomId)}',
      cancellationToken: cancellationToken,
    );
    await _sdk._unsubscribe(
      roomId,
      cancellationToken: cancellationToken,
      ignoreRealtimeError: true,
    );
  }
}
