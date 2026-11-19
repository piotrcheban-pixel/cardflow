/// Запись фактических метрик live-прогона и калибровки токенов
/// (TASK 04–05, требование 4.3).
///
/// Каждое поле — либо факт (из `usage`/замера), либо `null` с объяснением:
/// отсутствие данных не превращается в 0. Оценки (`estimated*`) и факты
/// (`actual*`) не смешиваются. Персональные материалы и ключи в отчёт не
/// попадают: только числа, идентификаторы модели и машинные коды. Свободное
/// поле [LiveRunRecord.note] проходит через `redactSecretsInText`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cardflow/api/http/log_redaction.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

import 'live_budget.dart';
import 'live_pricing.dart';

/// Стоимость одного логического запроса (фрагмента/восстановления).
///
/// Строится из [TokenCalibrationSample]: оценка входа, резерв вывода и факт
/// `usage`. Тексты карточек/материалов здесь отсутствуют.
class LiveRequestCost {
  /// Создаёт запись.
  const LiveRequestCost({
    required this.chunkIndex,
    required this.attempt,
    required this.recovered,
    required this.estimatedInputTokens,
    required this.actualInputTokens,
    required this.estimatedOutputTokens,
    required this.actualOutputTokens,
    required this.estimatedCostUsd,
    required this.actualCostUsd,
  });

  /// Номер фрагмента плана (с 1).
  final int chunkIndex;

  /// Попытка фрагмента (1 — первичный запрос).
  final int attempt;

  /// Запрос отправлен в рамках восстановления.
  final bool recovered;

  /// Оценка входа по собранному запросу; `null` — не сообщена.
  final int? estimatedInputTokens;

  /// Факт входа из `usage`; `null` — провайдер не сообщил.
  final int? actualInputTokens;

  /// Резерв вывода (`max_tokens`), а не ожидаемый текст.
  final int? estimatedOutputTokens;

  /// Факт выхода из `usage`; `null` — не сообщён.
  final int? actualOutputTokens;

  /// Предварительная стоимость по оценке; `null` — нет тарифа/токенов.
  final double? estimatedCostUsd;

  /// Фактическая стоимость по `usage`; `null` — нет тарифа/факта.
  final double? actualCostUsd;

  /// Строит запись из сэмпла калибровки и тарифа.
  static LiveRequestCost fromSample(
    TokenCalibrationSample sample,
    LivePrice? price,
  ) {
    final int? estimatedInput = sample.requestInput.tokens;
    final int? estimatedOutput = sample.reservedOutput.tokens;
    final int? actualInput = sample.actualInput.tokens;
    final int? actualOutput = sample.actualOutput.tokens;
    return LiveRequestCost(
      chunkIndex: sample.chunkIndex,
      attempt: sample.attempt,
      recovered: sample.recovered,
      estimatedInputTokens: estimatedInput,
      actualInputTokens: actualInput,
      estimatedOutputTokens: estimatedOutput,
      actualOutputTokens: actualOutput,
      estimatedCostUsd: _cost(price, estimatedInput, estimatedOutput),
      actualCostUsd: _cost(price, actualInput, actualOutput),
    );
  }

  static double? _cost(LivePrice? price, int? input, int? output) {
    if (price == null || input == null || output == null) return null;
    return price.costFor(inputTokens: input, outputTokens: output);
  }

  /// JSON для отчёта; отсутствующие значения — `null`.
  Map<String, Object?> toJson() => <String, Object?>{
    'chunkIndex': chunkIndex,
    'attempt': attempt,
    'recovered': recovered,
    'estimatedInputTokens': estimatedInputTokens,
    'actualInputTokens': actualInputTokens,
    'estimatedOutputTokens': estimatedOutputTokens,
    'actualOutputTokens': actualOutputTokens,
    'estimatedCostUsd': estimatedCostUsd,
    'actualCostUsd': actualCostUsd,
  };
}

/// Запись одного прогона сценария.
class LiveRunRecord {
  /// Создаёт запись.
  const LiveRunRecord({
    required this.scenario,
    required this.startedAt,
    required this.provider,
    required this.model,
    required this.estimatorVersion,
    required this.estimatedInputTokens,
    required this.actualInputTokens,
    required this.estimatedOutputTokens,
    required this.actualOutputTokens,
    required this.inputPricePerMillion,
    required this.outputPricePerMillion,
    required this.currency,
    required this.pricingSource,
    required this.pricingDate,
    required this.estimatedCostUsd,
    required this.actualCostUsd,
    required this.guardSpentUsd,
    required this.guardTotalSpentUsd,
    required this.guardMaxCostUsd,
    required this.costBlocked,
    required this.requestSizeBytes,
    required this.imageCount,
    required this.requestDurationMs,
    required this.wallClockMs,
    required this.resultStatus,
    required this.logicalRequests,
    required this.httpRequests,
    required this.httpAttempts,
    required this.retries,
    required this.recoveryRequests,
    required this.httpBudgetMax,
    required this.httpBudgetUsed,
    required this.requestCosts,
    this.note,
  });

  /// Имя сценария (`prompt_only_short`, `prompt_only_many_40`, …).
  final String scenario;

  /// Момент запуска (UTC ISO-8601).
  final String startedAt;

  /// Провайдер (id аккаунта/пресета).
  final String provider;

  /// Модель.
  final String model;

  /// Версия оценщика (`heuristic/1/request-1`); `null` — не сообщена.
  final String? estimatorVersion;

  /// Оценка входа по собранным запросам (сумма по фрагментам).
  final int? estimatedInputTokens;

  /// Факт входа из `usage` (сумма известных значений); `null` — не сообщён.
  final int? actualInputTokens;

  /// Резерв вывода, отправленный в запросах (`max_tokens`).
  final int? estimatedOutputTokens;

  /// Факт выхода из `usage`; `null` — не сообщён.
  final int? actualOutputTokens;

  /// Цена входа за 1M токенов; `null` — тариф неизвестен.
  final double? inputPricePerMillion;

  /// Цена выхода за 1M токенов; `null` — тариф неизвестен.
  final double? outputPricePerMillion;

  /// Валюта тарифа; `null` — неизвестна.
  final String? currency;

  /// Официальная страница тарифа.
  final String? pricingSource;

  /// Дата проверки тарифа (`YYYY-MM-DD`).
  final String? pricingDate;

  /// Предварительная стоимость по оценке; `null` — нет тарифа/токенов.
  final double? estimatedCostUsd;

  /// Фактическая стоимость по `usage`; `null` — нет тарифа/факта.
  final double? actualCostUsd;

  /// Прирост накопленной стоимости guard за сценарий; `null` — guard не было.
  final double? guardSpentUsd;

  /// Накопленная стоимость guard на конец сценария.
  final double? guardTotalSpentUsd;

  /// Лимит стоимости guard.
  final double? guardMaxCostUsd;

  /// Сколько HTTP-обменов отклонено cost guard до отправки.
  final int? costBlocked;

  /// Суммарный размер JSON-тел запросов.
  final int? requestSizeBytes;

  /// Сколько изображений передано модели.
  final int imageCount;

  /// Суммарное время HTTP-обменов, мс (не включает ожидание между ними).
  final int? requestDurationMs;

  /// Длительность сценария по стенным часам, мс.
  final int? wallClockMs;

  /// Статус задания (`done`, `partial`, `error`, `cancelled`).
  final String resultStatus;

  /// Сколько логических запросов генерации сделано (фрагменты + recovery).
  final int logicalRequests;

  /// Сколько HTTP-обменов (`postJson`, включая strict/tolerant) сделано.
  final int httpRequests;

  /// Сколько физических HTTP-попыток (включая повторы 429/5xx).
  final int? httpAttempts;

  /// Повторы внутри HTTP-обменов: `httpAttempts - httpRequests`.
  final int? retries;

  /// Сколько дополнительных запросов ушло на восстановление.
  final int recoveryRequests;

  /// Лимит HTTP-обменов на прогон.
  final int httpBudgetMax;

  /// Сколько HTTP-обменов израсходовано в общем бюджете.
  final int httpBudgetUsed;

  /// Детализация по логическим запросам (без текстов).
  final List<LiveRequestCost> requestCosts;

  /// Свободное пояснение (редактируется перед записью).
  final String? note;

  /// Дата актуальности записи (UTC).
  String get recordedOn => startedAt;

  /// JSON: отсутствующие значения остаются `null`.
  Map<String, Object?> toJson() => <String, Object?>{
    'scenario': scenario,
    'startedAt': startedAt,
    'provider': provider,
    'model': model,
    'estimatorVersion': estimatorVersion,
    'estimatedInputTokens': estimatedInputTokens,
    'actualInputTokens': actualInputTokens,
    'estimatedOutputTokens': estimatedOutputTokens,
    'actualOutputTokens': actualOutputTokens,
    'inputPricePerMillion': inputPricePerMillion,
    'outputPricePerMillion': outputPricePerMillion,
    'currency': currency,
    'pricingSource': pricingSource,
    'pricingDate': pricingDate,
    'estimatedCostUsd': estimatedCostUsd,
    'actualCostUsd': actualCostUsd,
    'guardSpentUsd': guardSpentUsd,
    'guardTotalSpentUsd': guardTotalSpentUsd,
    'guardMaxCostUsd': guardMaxCostUsd,
    'costBlocked': costBlocked,
    'requestSizeBytes': requestSizeBytes,
    'imageCount': imageCount,
    'requestDurationMs': requestDurationMs,
    'wallClockMs': wallClockMs,
    'resultStatus': resultStatus,
    'logicalRequests': logicalRequests,
    'httpRequests': httpRequests,
    'httpAttempts': httpAttempts,
    'retries': retries,
    'recoveryRequests': recoveryRequests,
    'httpBudgetMax': httpBudgetMax,
    'httpBudgetUsed': httpBudgetUsed,
    'requestCosts': requestCosts
        .map((LiveRequestCost cost) => cost.toJson())
        .toList(growable: false),
    'note': note,
  };

  /// Собирает запись из результата пайплайна и счётчиков транспорта.
  ///
  /// [imageCount] передаёт сценарий: сколько изображений он приложил
  /// (`GenerationRunResult.sentDocumentImageIds` учитывает только документные
  /// части, пользовательские вложения в него не входят).
  static LiveRunRecord fromRun({
    required String scenario,
    required DateTime startedAt,
    required String provider,
    required String model,
    required GenerationRunResult result,
    required LiveProbeTransport probe,
    required int imageCount,
    required int logicalRequests,
    required LiveRequestBudget httpBudget,
    required int? httpAttempts,
    LiveCostGuard? costGuard,
    double? guardSpentUsd,
    Duration? elapsed,
    String? note,
  }) {
    final List<TokenCalibrationSample> samples = result.calibration.samples;
    final int? estimatedInput = _sumKnown(
      samples.map((TokenCalibrationSample s) => s.requestInput.tokens),
    );
    final int? actualInput = _sumKnown(
      samples.map((TokenCalibrationSample s) => s.actualInput.tokens),
    );
    final int? estimatedOutput = _sumKnown(
      samples.map((TokenCalibrationSample s) => s.reservedOutput.tokens),
    );
    final int? actualOutput = _sumKnown(
      samples.map((TokenCalibrationSample s) => s.actualOutput.tokens),
    );
    final LivePrice? price = costGuard?.price ?? livePriceFor(provider, model);
    final double? estimatedCost =
        price != null && estimatedInput != null && estimatedOutput != null
        ? price.costFor(
            inputTokens: estimatedInput,
            outputTokens: estimatedOutput,
          )
        : null;
    final double? actualCost =
        price != null && actualInput != null && actualOutput != null
        ? price.costFor(inputTokens: actualInput, outputTokens: actualOutput)
        : null;
    final int httpRequests = probe.exchanges.length;
    final int? retries = httpAttempts == null
        ? null
        : math.max(0, httpAttempts - httpRequests);
    final String? safeNote = note == null ? null : redactSecretsInText(note);
    return LiveRunRecord(
      scenario: scenario,
      startedAt: startedAt.toUtc().toIso8601String(),
      provider: provider,
      model: model,
      estimatorVersion: samples.isEmpty ? null : samples.first.estimatorVersion,
      estimatedInputTokens: estimatedInput,
      actualInputTokens: actualInput,
      estimatedOutputTokens: estimatedOutput,
      actualOutputTokens: actualOutput,
      inputPricePerMillion: price?.inputPerMillion,
      outputPricePerMillion: price?.outputPerMillion,
      currency: price?.currency,
      pricingSource: price?.sourceUrl,
      pricingDate: price?.verifiedOn,
      estimatedCostUsd: estimatedCost,
      actualCostUsd: actualCost,
      guardSpentUsd: guardSpentUsd,
      guardTotalSpentUsd: costGuard?.spentUsd,
      guardMaxCostUsd: costGuard?.maxCostUsd,
      costBlocked: costGuard?.blocked,
      requestSizeBytes: probe.totalBytes,
      imageCount: imageCount,
      requestDurationMs: probe.totalDuration.inMilliseconds,
      wallClockMs: elapsed?.inMilliseconds,
      resultStatus: result.status.name,
      logicalRequests: logicalRequests,
      httpRequests: httpRequests,
      httpAttempts: httpAttempts,
      retries: retries,
      recoveryRequests: result.recoveryRequestsUsed,
      httpBudgetMax: httpBudget.maxRequests,
      httpBudgetUsed: httpBudget.used,
      requestCosts: List<LiveRequestCost>.unmodifiable(
        samples.map(
          (TokenCalibrationSample sample) =>
              LiveRequestCost.fromSample(sample, price),
        ),
      ),
      note: safeNote,
    );
  }

  static int? _sumKnown(Iterable<int?> values) {
    var sum = 0;
    var any = false;
    for (final int? value in values) {
      if (value == null) continue;
      any = true;
      sum += value;
    }
    return any ? sum : null;
  }
}

/// Собирает записи прогонов и пишет отчёт (JSON Lines).
class LiveRunRecorder {
  /// Создаёт рекордер.
  LiveRunRecorder({this.reportPath = 'build/live/live-runs.jsonl'});

  /// Путь по умолчанию (переопределяется `CARDFLOW_LIVE_REPORT`).
  final String reportPath;

  /// Записи в порядке добавления.
  final List<LiveRunRecord> records = <LiveRunRecord>[];

  /// Добавляет запись.
  void add(LiveRunRecord record) => records.add(record);

  /// Суммарное число логических запросов.
  int get totalRequests => records.fold<int>(
    0,
    (int sum, LiveRunRecord record) => sum + record.logicalRequests,
  );

  /// Суммарное число HTTP-обменов.
  int get totalHttpRequests => records.fold<int>(
    0,
    (int sum, LiveRunRecord record) => sum + record.httpRequests,
  );

  /// Суммарное число физических HTTP-попыток; `null` — не измерялось хотя бы
  /// в одной записи (не подставляем 0 вместо неизвестности).
  int? get totalHttpAttempts {
    if (records.isEmpty) return null;
    var sum = 0;
    for (final LiveRunRecord record in records) {
      final int? attempts = record.httpAttempts;
      if (attempts == null) return null;
      sum += attempts;
    }
    return sum;
  }

  /// Суммарная фактическая стоимость; `null`, если хотя бы у одной записи нет
  /// факта (не подставляем 0 вместо неизвестности).
  double? get totalActualCostUsd {
    var sum = 0.0;
    for (final LiveRunRecord record in records) {
      final double? cost = record.actualCostUsd;
      if (cost == null) return null;
      sum += cost;
    }
    return records.isEmpty ? null : sum;
  }

  /// Пишет JSON Lines; возвращает путь файла.
  Future<String> write({String? path}) async {
    final String target = path ?? reportPath;
    final File file = File(target);
    await file.parent.create(recursive: true);
    final String contents = records
        .map((LiveRunRecord record) => jsonEncode(record.toJson()))
        .join('\n');
    await file.writeAsString(
      contents.isEmpty ? '' : '$contents\n',
      flush: true,
    );
    return target;
  }

  /// Краткая таблица для вывода прогона (без материалов и ключей).
  String summary() {
    final StringBuffer buffer = StringBuffer();
    for (final LiveRunRecord record in records) {
      buffer.writeln(
        '${record.scenario}: ${record.resultStatus}, '
        'logical=${record.logicalRequests}, '
        'http=${record.httpRequests}, '
        'attempts=${record.httpAttempts ?? 'unknown'}, '
        'input=${record.actualInputTokens ?? 'unknown'}, '
        'output=${record.actualOutputTokens ?? 'unknown'}, '
        'cost=${record.actualCostUsd?.toStringAsFixed(5) ?? 'unknown'}, '
        'images=${record.imageCount}, '
        'recovery=${record.recoveryRequests}',
      );
    }
    return buffer.toString();
  }
}
