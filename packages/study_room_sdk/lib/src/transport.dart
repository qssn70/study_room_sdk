import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'errors.dart';

class StudyRoomCancellationToken {
  final _cancelled = Completer<void>();
  StudyRoomCancellationToken([this._parents = const []]);

  final List<StudyRoomCancellationToken> _parents;

  bool get isCancelled =>
      _cancelled.isCompleted || _parents.any((parent) => parent.isCancelled);
  Future<void> get whenCancelled => _parents.isEmpty
      ? _cancelled.future
      : Future.any([
          _cancelled.future,
          ..._parents.map((parent) => parent.whenCancelled),
        ]);

  static StudyRoomCancellationToken linked(
    Iterable<StudyRoomCancellationToken?> tokens,
  ) => StudyRoomCancellationToken(tokens.nonNulls.toList(growable: false));

  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }
}

abstract class StudyRoomTransport {
  Future<Map<String, dynamic>?> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    StudyRoomCancellationToken? cancellationToken,
  });
  Future<void> close();
}

class HttpStudyRoomTransport implements StudyRoomTransport {
  HttpStudyRoomTransport(
    this.baseUrl, {
    required this.timeout,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final Duration timeout;
  final http.Client _client;
  var _closed = false;

  @override
  Future<Map<String, dynamic>?> requestJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String> headers = const {},
    StudyRoomCancellationToken? cancellationToken,
  }) async {
    if (_closed) {
      throw const StudyRoomException(
        'HTTP transport is closed',
        kind: StudyRoomExceptionKind.network,
        code: 'transport_closed',
      );
    }
    final timeoutAbort = Completer<void>();
    final abortTrigger = cancellationToken == null
        ? timeoutAbort.future
        : Future.any([timeoutAbort.future, cancellationToken.whenCancelled]);
    final request = http.AbortableRequest(
      method,
      _resolve(path),
      abortTrigger: abortTrigger,
    );
    request.headers.addAll({'Accept': 'application/json', ...headers});
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final timeoutResult = Completer<http.Response>();
      final timer = Timer(timeout, () {
        if (!timeoutAbort.isCompleted) timeoutAbort.complete();
        timeoutResult.completeError(
          TimeoutException('HTTP request timed out', timeout),
        );
      });
      late final http.Response response;
      try {
        final sent = _client.send(request).then(http.Response.fromStream);
        response = await Future.any<http.Response>([
          sent,
          if (cancellationToken != null)
            cancellationToken.whenCancelled.then((_) {
              throw const StudyRoomException(
                'Request was cancelled',
                kind: StudyRoomExceptionKind.cancelled,
                code: 'cancelled',
              );
            }),
          timeoutResult.future,
        ]);
      } finally {
        timer.cancel();
      }
      return _decode(response);
    } on http.RequestAbortedException catch (error) {
      if (cancellationToken?.isCancelled ?? false) {
        throw StudyRoomException(
          'Request was cancelled',
          kind: StudyRoomExceptionKind.cancelled,
          code: 'cancelled',
          cause: error,
        );
      }
      throw StudyRoomException(
        'Request timed out after ${timeout.inSeconds}s',
        kind: StudyRoomExceptionKind.timeout,
        code: 'timeout',
        cause: error,
      );
    } on TimeoutException catch (error) {
      throw StudyRoomException(
        'Request timed out after ${timeout.inSeconds}s',
        kind: StudyRoomExceptionKind.timeout,
        code: 'timeout',
        cause: error,
      );
    } on StudyRoomException {
      rethrow;
    } catch (error) {
      throw StudyRoomException(
        'Network request failed',
        kind: StudyRoomExceptionKind.network,
        code: 'network_error',
        cause: error,
      );
    }
  }

  Uri _resolve(String path) {
    final normalizedBase = baseUrl.path.endsWith('/')
        ? baseUrl
        : baseUrl.replace(path: '${baseUrl.path}/');
    return normalizedBase.resolve(
      path.startsWith('/') ? path.substring(1) : path,
    );
  }

  Map<String, dynamic>? _decode(http.Response response) {
    Map<String, dynamic>? decoded;
    if (response.bodyBytes.isNotEmpty) {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      if (value is Map) decoded = Map<String, dynamic>.from(value);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final status = response.statusCode;
      throw StudyRoomException(
        decoded?['message'] as String? ?? 'Request failed with status $status',
        kind: status == 401
            ? StudyRoomExceptionKind.authentication
            : status == 403
            ? StudyRoomExceptionKind.authorization
            : status == 404
            ? StudyRoomExceptionKind.notFound
            : status == 409
            ? StudyRoomExceptionKind.conflict
            : status == 429
            ? StudyRoomExceptionKind.rateLimited
            : status >= 500
            ? StudyRoomExceptionKind.server
            : StudyRoomExceptionKind.validation,
        code: decoded?['code'] as String? ?? 'http_error',
        statusCode: status,
        requestId: decoded?['requestId'] as String?,
        details: decoded?['details'],
      );
    }
    if (response.statusCode == 204 || response.bodyBytes.isEmpty) return null;
    if (decoded == null) {
      throw const StudyRoomException(
        'Expected a JSON object response',
        kind: StudyRoomExceptionKind.protocol,
        code: 'invalid_json',
      );
    }
    return decoded;
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _client.close();
  }
}
