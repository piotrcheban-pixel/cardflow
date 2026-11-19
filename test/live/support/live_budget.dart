/// Бюджет запросов, стоимости и счётчики live-прогона (TASK 04–05).
///
/// Границы разделены явно (TASK 05, требование 4.2):
/// - **логические запросы генерации** — вызовы `GenerationCaller.generate`
///   (фрагмент плана, включая запросы восстановления) — [LiveRequestBudget]
///   в [LiveRecordingCaller];
/// - **HTTP-обмены** — вызовы `GenerationTransport.postJson` (включая
///   fallback-лестницу strict → tolerant) — [LiveRequestBudget] в
///   [LiveProbeTransport];
/// - **физические HTTP-попытки** — повторы Dio после 429/5xx/таймаута —
///   [LiveAttemptLimiter];
/// - **стоимость** — [LiveCostGuard]: предварительная оценка каждого
///   HTTP-обмена до отправки и накопленный факт из `usage` после ответа.
///
/// Стоимость не может превысить [LiveCostGuard.maxCostUsd]: запрос, оценка
/// которого выводит накопленный расход за лимит, отклоняется **до** отправки.
/// Неизвестная цена не превращается в ноль — [LiveCostGuard] создаётся только
/// при подтверждённом тарифе (`live_pricing.dart`).
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_budget.dart'
    show kBudgetBytesPerTokenBound;
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

import 'live_pricing.dart';

/// Бюджет запросов исчерпан: следующий запрос не отправляется.
class LiveBudgetExceeded implements Exception {
  /// Создаёт исключение с безопасным сообщением (без ключей/тел).
  LiveBudgetExceeded(this.message);

  /// Причина (только числа/имена сценария).
  final String message;

  @override
  String toString() => 'LiveBudgetExceeded: $message';
}

/// Счётчик запросов с жёстким лимитом.
///
/// Значения по умолчанию не допускают ни одного запроса: `maxRequests = 0`.
/// Один экземпляр может быть общим для всего файла тестов: тогда лимит
/// действует на прогон A–C целиком, а не на каждый сценарий отдельно.
class LiveRequestBudget {
  /// Создаёт бюджет.
  LiveRequestBudget({required this.maxRequests, this.label = 'live'})
    : assert(maxRequests >= 0);

  /// Максимум запросов.
  final int maxRequests;

  /// Метка бюджета (для отчёта).
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
  String toString() => 'LiveRequestBudget($label $used/$maxRequests)';
}

/// Один логический вызов генерации (фрагмент плана или восстановление).
///
/// Тексты не сохраняются: только длины и структурные числа, чтобы отчёт не
/// содержал пользовательских материалов.
class LiveCallRecord {
  /// Создаёт запись.
  const LiveCallRecord({
    required this.index,
    required this.limit,
    required this.materialsChars,
    required this.wishesChars,
    required this.continuationChars,
    required this.images,
    required this.documentImages,
  });

  /// Номер вызова в рамках сценария (с 1).
  final int index;

  /// Заказ карточек на фрагмент.
  final int limit;

  /// Длина текста материалов в символах (не сам текст).
  final int materialsChars;

  /// Длина пожеланий в символах.
  final int wishesChars;

  /// Длина блока продолжения в символах (0 — блока не было).
  final int continuationChars;

  /// Число пользовательских вложений.
  final int images;

  /// Число изображений документов.
  final int documentImages;

  /// true, если запрос содержал continuity-блок.
  bool get hasContinuation => continuationChars > 0;

  /// JSON для отчёта (без текстов).
  Map<String, Object?> toJson() => <String, Object?>{
    'index': index,
    'limit': limit,
    'materialsChars': materialsChars,
    'wishesChars': wishesChars,
    'continuationChars': continuationChars,
    'images': images,
    'documentImages': documentImages,
  };
}

/// Обёртка `GenerationCaller`: считает **логические** запросы и их структуру.
///
/// Ставится между `GenerationPipeline` и production-`CardGenerationService`,
/// поэтому видит каждый фрагмент (включая восстановление) и не подменяет
/// production-путь.
class LiveRecordingCaller implements GenerationCaller {
  /// Создаёт обёртку.
  LiveRecordingCaller({
    required this.inner,
    required this.budget,
    List<LiveCallRecord>? records,
  }) : records = records ?? <LiveCallRecord>[];

  /// Настоящий вызов (production-сервис).
  final GenerationCaller inner;

  /// Бюджет логических запросов.
  final LiveRequestBudget budget;

  /// Журнал вызовов.
  final List<LiveCallRecord> records;

  @override
  Future<GenerationResult> generate(
    GenerationRequest request, {
    CancelToken? cancelToken,
  }) {
    budget.reserve();
    records.add(
      LiveCallRecord(
        index: records.length + 1,
        limit: request.limit,
        materialsChars: request.materialsText.length,
        wishesChars: request.wishes?.length ?? 0,
        continuationChars: request.continuation?.length ?? 0,
        images: request.images.length,
        documentImages: request.documentImages.length,
      ),
    );
    return inner.generate(request, cancelToken: cancelToken);
  }
}

/// Один HTTP-обмен: размер тела, время и исход.
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

  /// Длительность одного `postJson` (включая повторы транспорта).
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

/// Предварительная оценка стоимости и накопленный факт.
///
/// Один экземпляр может быть общим для файла тестов: тогда `maxCostUsd`
/// ограничивает весь прогон A–C, а не каждый сценарий.
class LiveCostGuard {
  /// Создаёт guard с подтверждённым тарифом.
  LiveCostGuard({
    required this.price,
    required this.maxCostUsd,
    this.label = 'live',
    this.outputTokensPerRequest = 3000,
  }) : assert(maxCostUsd > 0, 'Лимит стоимости должен быть > 0'),
       assert(outputTokensPerRequest >= 0);

  /// Тариф (только подтверждённый официальной страницей).
  final LivePrice price;

  /// Максимальная суммарная стоимость прогона, USD.
  final double maxCostUsd;

  /// Метка прогона.
  final String label;

  /// Ожидаемый выход на один запрос (из плана сценария).
  int outputTokensPerRequest;

  double _spentUsd = 0;
  double _reservedUsd = 0;
  int _blocked = 0;

  /// Накопленный факт (или консервативная оценка при отсутствии `usage`).
  double get spentUsd => _spentUsd;

  /// Зарезервировано под ещё не завершённые запросы.
  double get reservedUsd => _reservedUsd;

  /// Сколько запросов отклонено до отправки.
  int get blocked => _blocked;

  /// true, если накопленная стоимость исчерпала лимит.
  bool get isExhausted => _spentUsd >= maxCostUsd;

  /// Проверяет оценку и резервирует сумму;
  /// бросает [LiveBudgetExceeded] до отправки запроса.
  LiveCostReservation reserve({
    required int inputTokens,
    required int outputTokens,
  }) {
    final double amount = price.costFor(
      inputTokens: math.max(0, inputTokens),
      outputTokens: math.max(0, outputTokens),
    );
    if (_spentUsd + _reservedUsd + amount > maxCostUsd + 1e-9) {
      _blocked++;
      throw LiveBudgetExceeded(
        'стоимость $label: оценка ${amount.toStringAsFixed(5)} USD '
        'превышает лимит ${maxCostUsd.toStringAsFixed(4)} USD '
        '(факт ${_spentUsd.toStringAsFixed(5)}, '
        'резерв ${_reservedUsd.toStringAsFixed(5)})',
      );
    }
    _reservedUsd += amount;
    return LiveCostReservation._(this, amount);
  }

  /// JSON для отчёта.
  Map<String, Object?> toJson() => <String, Object?>{
    'label': label,
    'maxCostUsd': maxCostUsd,
    'spentUsd': _spentUsd,
    'reservedUsd': _reservedUsd,
    'blocked': _blocked,
    'inputPerMillion': price.inputPerMillion,
    'outputPerMillion': price.outputPerMillion,
    'currency': price.currency,
    'pricingSource': price.sourceUrl,
    'pricingDate': price.verifiedOn,
  };

  /// Безопасная сводка (без тел/ключей).
  @override
  String toString() =>
      'LiveCostGuard($label: ${_spentUsd.toStringAsFixed(5)}/'
      '${maxCostUsd.toStringAsFixed(4)} USD, reserved: '
      '${_reservedUsd.toStringAsFixed(5)}, blocked: $_blocked)';
}

/// Резерв стоимости одного HTTP-обмена.
class LiveCostReservation {
  LiveCostReservation._(this._guard, this.estimatedUsd);

  final LiveCostGuard _guard;

  /// Предварительная оценка (USD).
  final double estimatedUsd;

  bool _closed = false;
  double? _actualUsd;

  /// Оценка стоимости обмена.
  double get amount => estimatedUsd;

  /// Факт стоимости после [commit]; `null` — не засчитан.
  double? get actualUsd => _actualUsd;

  /// Засчитывает факт из `usage`; без usage — консервативную оценку.
  void commit({int? actualInputTokens, int? actualOutputTokens}) {
    if (_closed) return;
    _closed = true;
    _guard._reservedUsd -= estimatedUsd;
    final double actual;
    if (actualInputTokens != null && actualOutputTokens != null) {
      actual = _guard.price.costFor(
        inputTokens: math.max(0, actualInputTokens),
        outputTokens: math.max(0, actualOutputTokens),
      );
    } else {
      actual = estimatedUsd;
    }
    _actualUsd = actual;
    _guard._spentUsd += actual;
  }

  /// Отменяет резерв (например, strict-схема отклонена без генерации).
  void release() {
    if (_closed) return;
    _closed = true;
    _guard._reservedUsd -= estimatedUsd;
  }
}

/// Расход токенов из ответа провайдера (OpenAI/Anthropic/Gemini).
class LiveTokenUsage {
  /// Создаёт пару значений; недостающее — `null`.
  const LiveTokenUsage({this.inputTokens, this.outputTokens});

  /// Входные токены.
  final int? inputTokens;

  /// Выходные токены.
  final int? outputTokens;

  /// true, если провайдер сообщил хотя бы одно значение.
  bool get isKnown => inputTokens != null || outputTokens != null;
}

/// Извлекает `usage` из JSON-ответа провайдера без домыслов.
LiveTokenUsage extractProviderUsage(Map<String, Object?> response) {
  final Object? usage = response['usage'];
  if (usage is Map) {
    final int? prompt = _positiveInt(usage['prompt_tokens']);
    final int? completion = _positiveInt(usage['completion_tokens']);
    if (prompt != null || completion != null) {
      return LiveTokenUsage(inputTokens: prompt, outputTokens: completion);
    }
    final int? input = _positiveInt(usage['input_tokens']);
    final int? output = _positiveInt(usage['output_tokens']);
    if (input != null || output != null) {
      return LiveTokenUsage(inputTokens: input, outputTokens: output);
    }
  }
  final Object? metadata = response['usageMetadata'];
  if (metadata is Map) {
    final int? prompt = _positiveInt(metadata['promptTokenCount']);
    final int? candidates = _positiveInt(metadata['candidatesTokenCount']);
    if (prompt != null || candidates != null) {
      return LiveTokenUsage(inputTokens: prompt, outputTokens: candidates);
    }
  }
  return const LiveTokenUsage();
}

int? _positiveInt(Object? value) {
  if (value is num && value.isFinite && value >= 0) return value.toInt();
  return null;
}

/// Транспорт-обёртка: считает HTTP-обмены и их размер, соблюдает бюджет и
/// предварительную оценку стоимости.
///
/// Ставится между `CardGenerationService` и `GenerationHttpClient`, поэтому
/// видит каждый HTTP-обмен (включая лестницу strict → tolerant). Внутренние
/// повторы по 429/5xx видны только в [LiveAttemptLimiter] на уровне Dio.
class LiveProbeTransport implements GenerationTransport {
  /// Создаёт обёртку.
  LiveProbeTransport({
    required this.inner,
    required this.budget,
    this.onRequest,
  });

  /// Настоящий транспорт (Dio).
  final GenerationTransport inner;

  /// Бюджет HTTP-обменов (не логических запросов).
  final LiveRequestBudget budget;

  /// Колбэк перед отправкой (номер HTTP-обмена).
  final void Function(int requestNumber)? onRequest;

  /// Журнал обменов.
  final List<LiveHttpExchange> exchanges = <LiveHttpExchange>[];

  /// Суммарный размер тел запросов.
  int get totalBytes => exchanges.fold<int>(
    0,
    (int sum, LiveHttpExchange item) => sum + item.bodyBytes,
  );

  /// Суммарное время HTTP-обменов.
  Duration get totalDuration => exchanges.fold<Duration>(
    Duration.zero,
    (Duration sum, LiveHttpExchange item) => sum + item.duration,
  );

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    final int bodyBytes = utf8.encode(jsonEncode(request.body)).length;
    budget.reserve();
    onRequest?.call(budget.used);
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

/// Лимит физических HTTP-попыток на уровне Dio.
///
/// Один HTTP-обмен может дать до `RetryPolicy.maxAttempts` попыток; лимит
/// ставится с запасом, но не бесконечный. При превышении запрос отклоняется
/// без отправки — деньги не расходуются.
class LiveAttemptLimiter extends Interceptor {
  /// Создаёт лимитер.
  ///
  /// [costGuard] — необязательный учёт стоимости **каждой физической
  /// попытки**: резерв до отправки, факт из `usage` после ответа. Тогда
  /// автоматические повторы 429/5xx не обходят лимит стоимости. Strict-ответ
  /// 400 (лестница ADR-021) освобождает резерв: генерации не было.
  LiveAttemptLimiter({required this.maxAttempts, this.costGuard})
    : assert(maxAttempts >= 0);

  /// Максимум физических HTTP-попыток за прогон.
  final int maxAttempts;

  /// Учёт стоимости; `null` — не используется.
  final LiveCostGuard? costGuard;

  static const String _costReservationKey = 'liveCostReservation';

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
    final LiveCostGuard? guard = costGuard;
    if (guard != null) {
      final int inputTokens = _estimatedInputTokens(options.data);
      final int outputTokens = _outputReserve(
        options.data,
        guard.outputTokensPerRequest,
      );
      try {
        options.extra[_costReservationKey] = guard.reserve(
          inputTokens: inputTokens,
          outputTokens: outputTokens,
        );
      } on LiveBudgetExceeded catch (error) {
        _rejected++;
        handler.reject(
          DioException(
            requestOptions: options,
            type: DioExceptionType.unknown,
            message: error.message,
          ),
          true,
        );
        return;
      }
    }
    _attempts++;
    handler.next(options);
  }

  @override
  void onResponse(
    Response<dynamic> response,
    ResponseInterceptorHandler handler,
  ) {
    _settleCost(
      response.requestOptions,
      response.data,
      failed: false,
      statusCode: response.statusCode,
    );
    handler.next(response);
  }

  @override
  void onError(DioException error, ErrorInterceptorHandler handler) {
    _settleCost(
      error.requestOptions,
      error.response?.data,
      failed: true,
      statusCode: error.response?.statusCode,
    );
    handler.next(error);
  }

  void _settleCost(
    RequestOptions options,
    Object? data, {
    required bool failed,
    int? statusCode,
  }) {
    final Object? value = options.extra.remove(_costReservationKey);
    if (value is! LiveCostReservation) return;
    if (!failed) {
      final LiveTokenUsage usage = _usageOf(data);
      value.commit(
        actualInputTokens: usage.inputTokens,
        actualOutputTokens: usage.outputTokens,
      );
      return;
    }
    // Strict-схема отклонена (400) до генерации — резерв возвращается.
    // 401/403 и отмена также не тратят токены. Факт тарификации такого 400
    // официально не подтверждён (budget.md).
    if (statusCode == 400 ||
        statusCode == 401 ||
        statusCode == 403 ||
        statusCode == null) {
      value.release();
      return;
    }
    // 429/5xx/сеть/таймаут: консервативно засчитываем оценку, чтобы повторы
    // не обходили лимит стоимости.
    value.commit();
  }

  static LiveTokenUsage _usageOf(Object? data) {
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return const LiveTokenUsage();
      }
    }
    if (decoded is Map) {
      return extractProviderUsage(
        decoded.map<String, Object?>(
          (Object? key, Object? value) => MapEntry(key.toString(), value),
        ),
      );
    }
    return const LiveTokenUsage();
  }

  static int _estimatedInputTokens(Object? data) {
    final String text = data is String ? data : jsonEncode(data);
    return math.max(1, utf8.encode(text).length ~/ kBudgetBytesPerTokenBound);
  }

  static int _outputReserve(Object? data, int fallback) {
    Object? decoded = data;
    if (data is String) {
      try {
        decoded = jsonDecode(data);
      } on FormatException {
        return fallback;
      }
    }
    if (decoded is Map) {
      for (final String key in const <String>[
        'max_tokens',
        'max_completion_tokens',
      ]) {
        final Object? value = decoded[key];
        if (value is int && value > 0) return value;
      }
    }
    return fallback;
  }

  /// JSON для отчёта.
  Map<String, Object?> toJson() => <String, Object?>{
    'maxAttempts': maxAttempts,
    'attempts': attempts,
    'rejected': rejected,
    if (costGuard != null) 'cost': costGuard!.toJson(),
  };
}
