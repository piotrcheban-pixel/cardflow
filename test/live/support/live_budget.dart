/// Бюджет запросов и счётчики live-прогона (TASK 04, раздел 5).
///
/// Бюджет ограничивает **логические** запросы (через [LiveProbeTransport]);
/// лимитер HTTP-попыток страхует от лишних повторов внутри транспорта, чтобы
/// сбой/`Retry-After` не превратились в неограниченный расход.
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

/// Бюджет запросов исчерпан: следующий запрос не отправляется.
class LiveBudgetExceeded implements Exception {
  /// Создаёт исключение с безопасным сообщением (без ключей/тел).
  LiveBudgetExceeded(this.message);

  /// Причина (только числа/имена сценария).
  final String message;

  @override
  String toString() => 'LiveBudgetExceeded: $message';
}

/// Счётчик логических запросов с жёстким лимитом.
///
/// Значения по умолчанию не допускают ни одного запроса: `maxRequests = 0`.
class LiveRequestBudget {
  /// Создаёт бюджет.
  LiveRequestBudget({required this.maxRequests, this.label = 'live'})
    : assert(maxRequests >= 0);

  /// Максимум логических запросов.
  final int maxRequests;

  /// Метка прогона (для отчёта).
  final String label;

  int _used = 0;

  /// Сколько запросов фактически отправлено.
  int get used => _used;

  /// Сколько осталось.
  int get remaining => maxRequests - _used;

  /// Бюджет исчерпан.
  bool get isExhausted => _used >= maxRequests;

  /// Занимает один запрос или бросает [LiveBudgetExceeded].
  void reserve() {
    if (isExhausted) {
      throw LiveBudgetExceeded('бюджет $label исчерпан: $used из $maxRequests');
    }
    _used++;
  }

  /// JSON для отчёта.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'maxRequests': maxRequests,
    'used': used,
    'remaining': remaining,
  };

  @override
  String toString() => 'LiveRequestBudget($used/$maxRequests)';
}

/// Один логический HTTP-обмен: размер тела, время и исход.
class LiveHttpExchange {
  /// Создаёт запись обмена.
  const LiveHttpExchange({
    required this.bodyBytes,
    required this.duration,
    required this.success,
    this.errorCode,
  });

  /// Размер JSON-тела запроса в байтах (без заголовков).
  final int bodyBytes;

  /// Длительность логического запроса (включая повторы транспорта).
  final Duration duration;

  /// Запрос завершился успешно.
  final bool success;

  /// Код ошибки генерации при неуспехе.
  final String? errorCode;

  /// JSON для отчёта.
  Map<String, Object?> toJson() => <String, Object?>{
    'bodyBytes': bodyBytes,
    'durationMs': duration.inMilliseconds,
    'success': success,
    'errorCode': errorCode,
  };
}

/// Транспорт-обёртка: считает запросы и их размер, соблюдает бюджет.
///
/// Ставится между `CardGenerationService` и `GenerationHttpClient`, поэтому
/// видит **каждый** логический запрос (включая лестницу strict → tolerant и
/// восстановление пайплайна). Внутренние повторы по 429/5xx видны только в
/// [LiveAttemptLimiter] на уровне Dio.
class LiveProbeTransport implements GenerationTransport {
  /// Создаёт обёртку.
  LiveProbeTransport({
    required this.inner,
    required this.budget,
    this.onRequest,
  });

  /// Настоящий транспорт (Dio).
  final GenerationTransport inner;

  /// Бюджет логических запросов.
  final LiveRequestBudget budget;

  /// Колбэк перед отправкой (для прогресса в выводе теста).
  final void Function(int requestNumber)? onRequest;

  /// Журнал обменов.
  final List<LiveHttpExchange> exchanges = <LiveHttpExchange>[];

  /// Суммарный размер тел запросов.
  int get totalBytes => exchanges.fold<int>(
    0,
    (int sum, LiveHttpExchange item) => sum + item.bodyBytes,
  );

  /// Суммарное время логических запросов.
  Duration get totalDuration => exchanges.fold<Duration>(
    Duration.zero,
    (Duration sum, LiveHttpExchange item) => sum + item.duration,
  );

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    budget.reserve();
    onRequest?.call(budget.used);
    final int bodyBytes = utf8.encode(jsonEncode(request.body)).length;
    final Stopwatch stopwatch = Stopwatch()..start();
    var success = false;
    String? errorCode;
    try {
      final Map<String, Object?> response = await inner.postJson(
        request,
        cancelToken: cancelToken,
      );
      success = true;
      return response;
    } on GenerationException catch (error) {
      errorCode = error.code.name;
      rethrow;
    } finally {
      stopwatch.stop();
      exchanges.add(
        LiveHttpExchange(
          bodyBytes: bodyBytes,
          duration: stopwatch.elapsed,
          success: success,
          errorCode: errorCode,
        ),
      );
    }
  }
}

/// Лимит HTTP-попыток на уровне Dio (страховка от повторов).
///
/// Один логический запрос может дать до `RetryPolicy.maxAttempts` попыток;
/// лимит ставится с запасом, но не бесконечный. При превышении запрос
/// отклоняется без отправки — деньги не расходуются.
class LiveAttemptLimiter extends Interceptor {
  /// Создаёт лимитер.
  LiveAttemptLimiter({required this.maxAttempts}) : assert(maxAttempts >= 0);

  /// Максимум физических HTTP-попыток за прогон.
  final int maxAttempts;

  int _attempts = 0;
  int _rejected = 0;

  /// Сколько попыток отправлено.
  int get attempts => _attempts;

  /// Сколько попыток отклонено лимитом.
  int get rejected => _rejected;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (_attempts >= maxAttempts) {
      _rejected++;
      handler.reject(
        DioException(
          requestOptions: options,
          type: DioExceptionType.unknown,
          message: 'live: лимит HTTP-попыток $maxAttempts исчерпан',
        ),
        true,
      );
      return;
    }
    _attempts++;
    handler.next(options);
  }

  /// JSON для отчёта.
  Map<String, Object?> toJson() => <String, Object?>{
    'maxAttempts': maxAttempts,
    'attempts': attempts,
    'rejected': rejected,
  };
}
