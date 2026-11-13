/// HTTP-транспорт генерации: один POST JSON на провайдера, ретраи и
/// нормализация ошибок (SPEC A8.6, ADR-012).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

/// Контракт отправки запроса провайдера (для тестов и 3c).
abstract interface class GenerationTransport {
  /// Выполняет [request] с ретраями и возвращает декодированный JSON-объект.
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  });
}

/// HTTP-клиент генерации поверх Dio.
///
/// Ответственный за: таймауты (ADR-012 §2), повтор по [RetryPolicy],
/// нормализацию ошибок в `GenerationException`, отсутствие ключей/материалов
/// в логах (через `RedactingLogInterceptor`).
class GenerationHttpClient implements GenerationTransport {
  /// Создаёт клиент.
  ///
  /// [delay] инжектируется для быстрых детерминированных тестов.
  GenerationHttpClient({
    required this.dio,
    required this.retryPolicy,
    Future<void> Function(Duration duration)? delay,
  }) : delay = delay ?? Future<void>.delayed;

  /// Dio с настроенными таймаутами, redaction-перехватчиком и адаптером.
  final Dio dio;

  /// Политика повторов.
  final RetryPolicy retryPolicy;

  /// Пауза перед повтором (инжектируется в тестах).
  final Future<void> Function(Duration duration) delay;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    var attempt = 1;
    while (true) {
      _throwIfCancelled(cancelToken);
      try {
        final response = await dio.postUri<dynamic>(
          request.uri,
          data: jsonEncode(request.body),
          options: _optionsFor(request),
          cancelToken: cancelToken,
        );
        return _decodeJsonObject(response);
      } on DioException catch (error) {
        if (error.type == DioExceptionType.cancel) {
          throw const GenerationException(
            GenerationErrorCode.cancelled,
            details: 'запрос отменён',
          );
        }
        final retryAfter = _retryAfterOf(error);
        final decision = retryPolicy.decide(
          attempt: attempt,
          statusCode: error.response?.statusCode,
          isTimeout: _isTimeout(error.type),
          isConnectionError: error.type == DioExceptionType.connectionError,
          retryAfter: retryAfter,
        );
        if (!decision.shouldRetry) {
          throw _toGenerationException(error, retryAfter: retryAfter);
        }
        await delay(decision.delay);
        attempt++;
      }
    }
  }

  /// Опции POST: JSON-тело и явная проверка 2xx (ADR-012 §2).
  Options _optionsFor(ProviderRequest request) {
    final headers = Map<String, dynamic>.from(request.headers);
    final hasContentType = headers.keys.any(
      (name) => name.toLowerCase() == Headers.contentTypeHeader,
    );
    return Options(
      method: 'POST',
      headers: headers,
      // Нельзя задавать contentType и заголовок Content-Type одновременно.
      contentType: hasContentType ? null : Headers.jsonContentType,
      validateStatus: (status) =>
          status != null && status >= 200 && status < 300,
    );
  }

  /// Декодирует ответ провайдера; обязан быть JSON-объектом.
  Map<String, Object?> _decodeJsonObject(Response<dynamic> response) {
    Object? data = response.data;
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) {
        throw const GenerationException(
          GenerationErrorCode.invalidResponse,
          details: 'пустой ответ провайдера',
        );
      }
      try {
        data = jsonDecode(text);
      } on FormatException {
        throw const GenerationException(
          GenerationErrorCode.invalidResponse,
          details: 'ответ провайдера не является JSON',
        );
      }
    }
    if (data is Map) {
      return data.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    }
    throw const GenerationException(
      GenerationErrorCode.invalidResponse,
      details: 'ответ провайдера не является JSON-объектом',
    );
  }

  /// Заголовок `Retry-After` из неудачного ответа (если был).
  Duration? _retryAfterOf(DioException error) {
    final values = error.response?.headers['retry-after'];
    if (values == null || values.isEmpty) return null;
    return parseRetryAfter(values.first);
  }

  /// Транспортный таймаут (соединение/отправка/приём).
  bool _isTimeout(DioExceptionType type) =>
      type == DioExceptionType.connectionTimeout ||
      type == DioExceptionType.sendTimeout ||
      type == DioExceptionType.receiveTimeout;

  /// Немедленная отмена: повтор не выполняется (SPEC A8.6).
  void _throwIfCancelled(CancelToken? cancelToken) {
    if (cancelToken != null && cancelToken.isCancelled) {
      throw const GenerationException(
        GenerationErrorCode.cancelled,
        details: 'запрос отменён до отправки',
      );
    }
  }

  /// Нормализует финальную ошибку в [GenerationException] без секретов.
  ///
  /// `details` содержит только тип/статус — ни заголовков, ни тела, ни URI.
  GenerationException _toGenerationException(
    DioException error, {
    Duration? retryAfter,
  }) {
    switch (error.type) {
      case DioExceptionType.cancel:
        return const GenerationException(
          GenerationErrorCode.cancelled,
          details: 'запрос отменён',
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
        return const GenerationException(
          GenerationErrorCode.timeout,
          details: 'таймаут запроса',
        );
      case DioExceptionType.connectionError:
        return const GenerationException(
          GenerationErrorCode.network,
          details: 'ошибка соединения',
        );
      case DioExceptionType.badCertificate:
        return const GenerationException(
          GenerationErrorCode.network,
          details: 'недоверенный сертификат провайдера',
        );
      case DioExceptionType.badResponse:
        return _fromStatusCode(
          error.response?.statusCode,
          retryAfter: retryAfter,
        );
      case DioExceptionType.unknown:
        final statusCode = error.response?.statusCode;
        if (statusCode != null) {
          return _fromStatusCode(statusCode, retryAfter: retryAfter);
        }
        return const GenerationException(
          GenerationErrorCode.network,
          details: 'неизвестная ошибка транспорта',
        );
    }
  }

  /// Классификация HTTP-статуса (ADR-012 §2).
  GenerationException _fromStatusCode(int? statusCode, {Duration? retryAfter}) {
    final details = statusCode == null
        ? 'HTTP без статуса'
        : 'HTTP $statusCode';
    if (statusCode == 401 || statusCode == 403) {
      return GenerationException(
        GenerationErrorCode.invalidApiKey,
        details: details,
      );
    }
    if (statusCode == 429) {
      return GenerationException(
        GenerationErrorCode.rateLimited,
        retryAfter: retryAfter,
        details: details,
      );
    }
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return GenerationException(
        GenerationErrorCode.serverUnavailable,
        details: details,
      );
    }
    return GenerationException(
      GenerationErrorCode.badRequest,
      details: details,
    );
  }
}
