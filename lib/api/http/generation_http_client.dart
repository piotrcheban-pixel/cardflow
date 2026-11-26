/// HTTP-транспорт генерации: один POST JSON на провайдера, ретраи и
/// нормализация ошибок (SPEC A8.6, ADR-012).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/http/log_redaction.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';

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
  /// [delay] инжектируется для быстрых детерминированных тестов;
  /// [diagnostics] — debug-диагностика ответов (ADR-024).
  GenerationHttpClient({
    required this.dio,
    required this.retryPolicy,
    GenerationDiagnostics? diagnostics,
    Future<void> Function(Duration duration)? delay,
  }) : diagnostics = diagnostics ?? const GenerationDiagnostics(),
       delay = delay ?? Future<void>.delayed;

  /// Dio с настроенными таймаутами, redaction-перехватчиком и адаптером.
  final Dio dio;

  /// Политика повторов.
  final RetryPolicy retryPolicy;

  /// Debug-диагностика тел ответов при ошибках (ADR-024).
  final GenerationDiagnostics diagnostics;

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
          throw _cancelled();
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
        await _waitBeforeRetry(decision.delay, cancelToken);
        attempt++;
      }
    }
  }

  /// Выдерживает паузу перед повтором, прерывая её при отмене (SPEC A6.8).
  ///
  /// Без гонки с `cancelToken.whenCancel` кнопка «Отмена» ждала бы конца
  /// backoff/`Retry-After` (до 30–60 с) — недопустимо для A6.8/A8.5 шага 6.
  Future<void> _waitBeforeRetry(
    Duration duration,
    CancelToken? cancelToken,
  ) async {
    final pause = delay(duration);
    if (cancelToken == null) {
      await pause;
      return;
    }
    if (cancelToken.isCancelled) throw _cancelled();
    final pauseFinished = pause.then<GenerationException?>((_) => null);
    final cancelled = cancelToken.whenCancel.then<GenerationException>(
      (_) => _cancelled(),
      onError: (Object _) => _cancelled(),
    );
    final first = await Future.any<GenerationException?>(
      <Future<GenerationException?>>[pauseFinished, cancelled],
    );
    if (first != null) throw first;
  }

  /// Ошибка отмены пользователем (SPEC A8.6).
  static GenerationException _cancelled() => const GenerationException(
    GenerationErrorCode.cancelled,
    details: 'запрос отменён',
  );

  /// Опции POST: JSON-тело, строка ответа и явная проверка 2xx (ADR-012 §2).
  ///
  /// `responseType: plain` — Dio не разбирает тело сам: разбор делает
  /// [_decodeJsonObject], поэтому битый JSON провайдера становится
  /// `invalidResponse` (а не `network` из упавшего трансформера Dio).
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
      responseType: ResponseType.plain,
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
        diagnostics.apiError(statusCode: response.statusCode, body: data);
        throw const GenerationException(
          GenerationErrorCode.invalidResponse,
          details: 'пустой ответ провайдера',
        );
      }
      try {
        data = jsonDecode(text);
      } on FormatException {
        diagnostics.apiError(statusCode: response.statusCode, body: text);
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
    diagnostics.apiError(statusCode: response.statusCode, body: data);
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
      throw _cancelled();
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
        return _cancelled();
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
        final Response<dynamic>? response = error.response;
        final int? statusCode = response?.statusCode;
        diagnostics.apiError(statusCode: statusCode, body: response?.data);
        return _fromStatusCode(
          statusCode,
          retryAfter: retryAfter,
          providerReason: _providerReasonOf(response?.data),
        );
      case DioExceptionType.unknown:
        final Response<dynamic>? response = error.response;
        final statusCode = response?.statusCode;
        if (statusCode != null) {
          diagnostics.apiError(statusCode: statusCode, body: response?.data);
          return _fromStatusCode(
            statusCode,
            retryAfter: retryAfter,
            providerReason: _providerReasonOf(response?.data),
          );
        }
        return const GenerationException(
          GenerationErrorCode.network,
          details: 'неизвестная ошибка транспорта',
        );
    }
  }

  /// Классификация HTTP-статуса (ADR-012 §2, TASK 02B-FINAL).
  GenerationException _fromStatusCode(
    int? statusCode, {
    Duration? retryAfter,
    String? providerReason,
  }) {
    final details = statusCode == null
        ? 'HTTP без статуса'
        : 'HTTP $statusCode';
    if (statusCode == 401 || statusCode == 403) {
      return GenerationException(
        GenerationErrorCode.invalidApiKey,
        details: details,
        failureReason: GenerationFailureReason.httpClientError,
      );
    }
    if (statusCode == 402) {
      // DeepSeek: «Insufficient Balance». Ключ верный, но платить нечем —
      // отдаём отдельный код, а не общий 4xx: сообщение говорит о балансе.
      return GenerationException(
        GenerationErrorCode.insufficientBalance,
        details: details,
        providerReason: providerReason,
        failureReason: GenerationFailureReason.httpClientError,
      );
    }
    if (statusCode == 429) {
      return GenerationException(
        GenerationErrorCode.rateLimited,
        retryAfter: retryAfter,
        details: details,
        failureReason: GenerationFailureReason.httpClientError,
      );
    }
    if (statusCode != null && statusCode >= 500 && statusCode < 600) {
      return GenerationException(
        GenerationErrorCode.serverUnavailable,
        details: details,
        failureReason: GenerationFailureReason.httpServerError,
      );
    }
    if (statusCode == 413) {
      return GenerationException(
        GenerationErrorCode.payloadTooLarge,
        details: details,
        providerReason: providerReason,
        failureReason: GenerationFailureReason.payloadTooLarge,
      );
    }
    // HTTP 400 с причиной «контекст/токены» — это переполнение окна, а не
    // несовместимый запрос: пайплайн дробит только проблемную часть плана.
    if (providerReason != null &&
        _contextOverflowPattern.hasMatch(providerReason)) {
      return GenerationException(
        GenerationErrorCode.contextOverflow,
        details: details,
        providerReason: providerReason,
        failureReason: GenerationFailureReason.contextOverflow,
      );
    }
    return GenerationException(
      GenerationErrorCode.badRequest,
      details: details,
      // Причина показывается пользователю только для 4xx запроса (400/404/422),
      // а не для ошибок авторизации/лимитов: там своё сообщение.
      providerReason: providerReason,
      failureReason: GenerationFailureReason.httpClientError,
    );
  }

  /// Признаки переполнения контекста в тексте ошибки провайдера.
  ///
  /// Русские и английские формулировки основных провайдеров; сюда не попадают
  /// общие 400 (например, «invalid characters»), чтобы не дробить материалы
  /// без причины.
  static final RegExp _contextOverflowPattern = RegExp(
    r'context (?:length|window)|context_length_exceeded|maximum context|'
    r'too many tokens|prompt is too long|input is too long|'
    r'request (?:is )?too large|exceeds the maximum|'
    r'превышает.{0,40}(?:контекст|токен)|слишком длинн',
    caseSensitive: false,
    unicode: true,
  );

  /// Короткая безопасная причина отказа из тела ответа провайдера.
  ///
  /// Поддерживает OpenAI (`error.message`), Gemini (`error.message`),
  /// Anthropic (`error.message`) и плоские `message`/`detail`. Управляющие
  /// символы заменяются, секретоподобные значения редактируются, длина
  /// ограничена — тело ответа целиком не показывается и не логируется.
  String? _providerReasonOf(Object? data) {
    Object? decoded = data;
    if (data is String) {
      final text = data.trim();
      if (text.isEmpty) return null;
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        // HTML/текстовая страница ошибки: безопасной причины нет.
        return null;
      }
    }
    if (decoded is! Map) return null;

    final Object? error = decoded['error'];
    Object? message;
    if (error is Map) {
      message = error['message'] ?? error['type'];
    } else if (error is String) {
      message = error;
    } else {
      message = decoded['message'] ?? decoded['detail'];
    }
    if (message is! String) return null;

    var reason = message
        .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    reason = _redactSecrets(reason);
    if (reason.isEmpty) return null;
    return reason.length <= 200 ? reason : '${reason.substring(0, 200)}…';
  }

  /// Редактирует похожие на ключи фрагменты в причине отказа.
  ///
  /// Единый санитайзер с диагностикой (`redactSecretsInText`): заголовки
  /// `Authorization`/`x-api-key`, `Bearer`-значения, токены известных форматов
  /// и секретные query-параметры (`?key=`, `&api_key=`).
  String _redactSecrets(String text) => redactSecretsInText(text);
}
