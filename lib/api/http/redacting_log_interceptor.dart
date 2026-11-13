/// Dio-перехватчик логирования без секретов и материалов (SPEC 3.4, A8.6).
library;

import 'package:dio/dio.dart';

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

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    throw UnimplementedError('RedactingLogInterceptor.onRequest');
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    throw UnimplementedError('RedactingLogInterceptor.onResponse');
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    throw UnimplementedError('RedactingLogInterceptor.onError');
  }
}
