/// Запись фактических метрик live-прогона и калибровки токенов
/// (TASK 04, раздел 9).
///
/// Каждое поле — либо факт (из `usage`/замера), либо `null` с объяснением:
/// отсутствие данных не превращается в 0. Оценки (`estimated*`) и факты
/// (`actual*`) не смешиваются. Персональные материалы и ключи в отчёт не
/// попадают: только числа, идентификаторы модели и машинные коды.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

import 'live_budget.dart';

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
    required this.requestSizeBytes,
    required this.imageCount,
    required this.requestDurationMs,
    required this.resultStatus,
    required this.recoveryCount,
    required this.requests,
    required this.httpAttempts,
    this.note,
  });

  /// Имя сценария (`prompt_only_short`, `prompt_only_many`, …).
  final String scenario;

  /// Момент запуска (UTC ISO-8601).
  final String startedAt;

  /// Провайдер (id аккаунта/пресета).
  final String provider;

  /// Модель.
  final String model;

  /// Версия оценщика (`heuristic/1/request-1`); `null` — не сообщена.
  final String? estimatorVersion;

  /// Оценка входа по собранному запросу (сумма по фрагментам).
  final int? estimatedInputTokens;

  /// Факт входа из `usage` (сумма известных значений); `null` — провайдер не
  /// сообщил.
  final int? actualInputTokens;

  /// Резерв вывода, отправленный в запросах.
  final int? estimatedOutputTokens;

  /// Факт выхода из `usage`; `null` — не сообщён.
  final int? actualOutputTokens;

  /// Суммарный размер JSON-тел запросов.
  final int? requestSizeBytes;

  /// Сколько изображений передано модели.
  final int imageCount;

  /// Суммарное время логических запросов, мс.
  final int? requestDurationMs;

  /// Статус задания (`done`, `partial`, `error`, `cancelled`).
  final String resultStatus;

  /// Сколько дополнительных запросов ушло на восстановление.
  final int recoveryCount;

  /// Сколько логических запросов отправлено.
  final int requests;

  /// Сколько физических HTTP-попыток сделано (включая повторы).
  final int? httpAttempts;

  /// Свободное пояснение (например, «изображения не включены»).
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
    'requestSizeBytes': requestSizeBytes,
    'imageCount': imageCount,
    'requestDurationMs': requestDurationMs,
    'resultStatus': resultStatus,
    'recoveryCount': recoveryCount,
    'requests': requests,
    'httpAttempts': httpAttempts,
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
    int? httpAttempts,
    String? note,
  }) {
    final List<TokenCalibrationSample> samples = result.calibration.samples;
    return LiveRunRecord(
      scenario: scenario,
      startedAt: startedAt.toUtc().toIso8601String(),
      provider: provider,
      model: model,
      estimatorVersion: samples.isEmpty ? null : samples.first.estimatorVersion,
      estimatedInputTokens: _sumKnown(
        samples.map((TokenCalibrationSample s) => s.requestInput.tokens),
      ),
      actualInputTokens: _sumKnown(
        samples.map((TokenCalibrationSample s) => s.actualInput.tokens),
      ),
      estimatedOutputTokens: _sumKnown(
        samples.map((TokenCalibrationSample s) => s.reservedOutput.tokens),
      ),
      actualOutputTokens: _sumKnown(
        samples.map((TokenCalibrationSample s) => s.actualOutput.tokens),
      ),
      requestSizeBytes: probe.totalBytes,
      imageCount: imageCount,
      requestDurationMs: probe.totalDuration.inMilliseconds,
      resultStatus: result.status.name,
      recoveryCount: result.recoveryRequestsUsed,
      requests: probe.exchanges.length,
      httpAttempts: httpAttempts,
      note: note,
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

  /// Суммарная стоимость неизвестна по определению: считает `usage`, не деньги.
  int get totalRequests => records.fold<int>(
    0,
    (int sum, LiveRunRecord record) => sum + record.requests,
  );

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
        'requests=${record.requests}, '
        'input=${record.actualInputTokens ?? 'unknown'}, '
        'output=${record.actualOutputTokens ?? 'unknown'}, '
        'images=${record.imageCount}, '
        'recovery=${record.recoveryCount}',
      );
    }
    return buffer.toString();
  }
}
