part of 'sdk.dart';

/// Chat history and message creation operations.
class StudyChatApi {
  StudyChatApi._(this._sdk);
  final StudyRoomSdk _sdk;

  /// Lists a chronological page from the room's message history.
  Future<StudyRoomPage<ChatMessage>> history(
    String roomId, {
    String? cursor,
    int limit = 50,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final value = await _sdk._request(
      'GET',
      _withQuery('/v1/rooms/${_segment(roomId)}/messages', {
        'cursor': cursor,
        'limit': '$limit',
      }),
      cancellationToken: cancellationToken,
    );
    return StudyRoomPage.messagesFromJson(value!);
  }

  /// Sends a normalized chat message.
  ///
  /// Reuse [idempotencyKey] only for retries of the same room and text.
  Future<ChatMessage> send(
    String roomId,
    String text, {
    String? idempotencyKey,
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    final normalized = text.trim();
    if (normalized.isEmpty || normalized.length > 2000) {
      throw const StudyRoomException(
        'Message must contain 1 to 2000 characters',
        kind: StudyRoomExceptionKind.validation,
        code: 'invalid_message',
      );
    }
    final value = await _sdk._request(
      'POST',
      '/v1/rooms/${_segment(roomId)}/messages',
      body: {'text': normalized},
      headers: _idempotencyHeaders(idempotencyKey),
      cancellationToken: cancellationToken,
    );
    final message = ChatMessage.fromJson(value!);
    _sdk._publishMessage(message);
    return message;
  }
}
