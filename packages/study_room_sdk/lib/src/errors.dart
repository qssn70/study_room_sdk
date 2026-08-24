/// High-level categories used to classify SDK failures.
enum StudyRoomExceptionKind {
  configuration,
  authentication,
  authorization,
  validation,
  conflict,
  notFound,
  rateLimited,
  timeout,
  cancelled,
  network,
  protocol,
  server,
}

/// Structured SDK exception with retry, HTTP, and request-correlation details.
class StudyRoomException implements Exception {
  const StudyRoomException(
    this.message, {
    required this.kind,
    this.code,
    this.statusCode,
    this.requestId,
    this.details,
    this.cause,
  });

  final String message;
  final StudyRoomExceptionKind kind;
  final String? code;
  final int? statusCode;
  final String? requestId;
  final Object? details;
  final Object? cause;

  bool get retryable =>
      kind == StudyRoomExceptionKind.timeout ||
      kind == StudyRoomExceptionKind.network ||
      kind == StudyRoomExceptionKind.server ||
      kind == StudyRoomExceptionKind.rateLimited ||
      (statusCode != null && statusCode! >= 500);

  @override
  String toString() => 'StudyRoomException($kind, $code, $message)';
}

/// Backward-compatible named subtype of [StudyRoomException].
class StudyRoomError extends StudyRoomException {
  const StudyRoomError(super.message, {super.code, super.cause})
    : super(kind: StudyRoomExceptionKind.validation);
}
