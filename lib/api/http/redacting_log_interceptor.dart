/// Dio-перехватчик логирования без секретов и материалов (SPEC 3.4, A8.6).
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/http/log_redaction.dart';

/// Логирует метод, отредактированный URI, статус/тип ошибки и длительность.
///
/// Тела запросов и ответов **не выводятся** (материалы пользователя и ответ
/// модели); заголовки `Authorization`, `x-api-key`, `x-goog-api-key` —
/// редактируются. Sink инжектируется; в production-проводке — `debugPrint`
/// только в debug-режиме.
class RedactingLogInterceptor extends Interceptor {
  /// Создаёт перехватчик с приёмником сообщений [sink].
  RedactingLogInterceptor({required this.sink, DateTime Function()? now})
    : now = now ?? DateTime.now;

  /// Приёмник строк лога (без секретов).
  final void Function(String message) sink;

  /// Источник времени для длительности (инжектируется в тестах).
  final DateTime Function() now;

  /// Ключ `extra`, в котором сохраняется время старта запроса.
  static const String startTimeExtraKey = 'cardflow.log.requestStartTime';

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.extra[startTimeExtraKey] = now();
    sink('HTTP ${options.method} ${redactUriForLog(options.uri)}');
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    sink(
      'HTTP ${response.statusCode} ${_methodAndUri(response.requestOptions)}'
      '${_durationSuffix(response.requestOptions)}',
    );
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final status = err.response?.statusCode;
    sink(
      'HTTP ${status ?? '-'} ${err.type.name} '
      '${_methodAndUri(err.requestOptions)}'
      '${_durationSuffix(err.requestOptions)}',
    );
    handler.next(err);
  }

  /// Метод и URI без секретов.
  String _methodAndUri(RequestOptions options) =>
      '${options.method} ${redactUriForLog(options.uri)}';

  /// Длительность от `onRequest` до ответа/ошибки, если время старта известно.
  String _durationSuffix(RequestOptions options) {
    final start = options.extra[startTimeExtraKey];
    if (start is! DateTime) return '';
    final elapsed = now().difference(start);
    return ' (${elapsed.inMilliseconds} ms)';
  }
}
