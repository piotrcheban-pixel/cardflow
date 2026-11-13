/// HTTP-транспорт генерации: один POST JSON на провайдера, ретраи и
/// нормализация ошибок (SPEC A8.6, ADR-012).
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';

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
  }) {
    throw UnimplementedError('GenerationHttpClient.postJson');
  }
}
