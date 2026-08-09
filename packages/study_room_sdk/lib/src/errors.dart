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

class StudyRoomError extends StudyRoomException {
  const StudyRoomError(String message, {String? code, Object? cause})
    : super(
        message,
        kind: StudyRoomExceptionKind.validation,
        code: code,
        cause: cause,
      );
}
