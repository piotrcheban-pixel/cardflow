/// Измерительный стенд генерации (TASK «Срез 12», часть 1).
///
/// Единственный вход — [GenerationReport]: collector **не** читает ни UI, ни
/// счётчики экрана, ни внутренние поля конвейера. Так «было → стало» на
/// legacy- и v3-путях считается по одному контракту, а не по разным числам.
///
/// Все величины — отношения и машинные коды; текстов материалов, промптов и
/// цитат здесь нет (протокол §10). `null` означает «данных нет», а не ноль:
/// yield без входных токенов не бывает, cleanRate без принятых карточек —
/// тоже.
library;

import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';

/// Снимок метрик одного прогона, собранный только из [GenerationReport].
class CollectedMetrics {
  /// Создаёт снимок; списки/карты копируются и становятся неизменяемыми.
  CollectedMetrics({
    required this.requested,
    required this.accepted,
    required this.generated,
    required this.invalid,
    required this.duplicates,
    required this.cleanAccepted,
    required this.absoluteClean,
    required this.acceptedWithWarnings,
    required Map<String, int> warningCodes,
    required this.requests,
    required this.coveredUnits,
    required this.totalUnits,
    required this.inputTokens,
    required this.outputTokens,
    required Map<GenerationStage, int> inputTokensByStage,
    required Map<GenerationStage, int> outputTokensByStage,
    required Map<DedupLevel, int> duplicatesByLevel,
    this.yieldPer1kInputTokens,
    this.acceptanceRate,
    this.cleanRate,
    this.duplicateRate,
    this.coverage,
    this.meanCoveredSalience,
    this.requestsPer10Cards,
    this.p50BatchDuration,
    this.p95BatchDuration,
  }) : warningCodes = Map<String, int>.unmodifiable(warningCodes),
       inputTokensByStage = Map<GenerationStage, int>.unmodifiable(
         inputTokensByStage,
       ),
       outputTokensByStage = Map<GenerationStage, int>.unmodifiable(
         outputTokensByStage,
       ),
       duplicatesByLevel = Map<DedupLevel, int>.unmodifiable(duplicatesByLevel);

  /// Запрошено карточек (0 — авто-режим).
  final int requested;

  /// Принято карточек.
  final int accepted;

  /// Произведено моделью.
  final int generated;

  /// Отброшено валидацией/схемой.
  final int invalid;

  /// Дублей (по уровням каскада; иначе счётчик отчёта).
  final int duplicates;

  /// Принято без пометок гейта.
  final int cleanAccepted;

  /// Число чистых карточек рядом с [cleanRate] (срез 14): доля без объёма
  /// вводит в заблуждение.
  final int absoluteClean;

  /// Принято с пометками гейта.
  final int acceptedWithWarnings;

  /// Коды пометок принятых карточек с числами.
  final Map<String, int> warningCodes;

  /// Запросов модели (включая повторы и добор).
  final int requests;

  /// Единиц карты/разделов с принятой хотя бы одной карточкой.
  final int coveredUnits;

  /// Всего единиц карты/разделов.
  final int totalUnits;

  /// Входные токены (факт `usage` по этапам).
  final int inputTokens;

  /// Выходные токены (факт `usage` по этапам).
  final int outputTokens;

  /// Расход входных токенов по этапам (understanding/generating/replenishing).
  final Map<GenerationStage, int> inputTokensByStage;

  /// Расход выходных токенов по этапам.
  final Map<GenerationStage, int> outputTokensByStage;

  /// Дубли по уровням каскада.
  final Map<DedupLevel, int> duplicatesByLevel;

  /// Принято карточек на 1000 входных токенов; `null` — входа нет.
  final double? yieldPer1kInputTokens;

  /// Доля принятых от произведённых; `null` — модель ничего не произвела.
  final double? acceptanceRate;

  /// Доля принятых без пометок от принятых; `null` — принятых нет.
  final double? cleanRate;

  /// Доля дублей от произведённых; `null` — нет данных.
  final double? duplicateRate;

  /// Доля единиц с принятой карточкой; `null` — единиц нет.
  final double? coverage;

  /// Средняя значимость покрытых единиц; `null` — карты знаний нет (legacy).
  final double? meanCoveredSalience;

  /// Запросов на 10 принятых карточек; `null` — принятых нет.
  final double? requestsPer10Cards;

  /// Медиана и 95-й процентиль длительности запроса (ближайший ранг).
  final Duration? p50BatchDuration;

  /// 95-й процентиль длительности запроса (ближайший ранг).
  final Duration? p95BatchDuration;

  /// JSON для отчёта стенда (числа и машинные коды, без текстов).
  Map<String, Object?> toJson() => <String, Object?>{
    'requested': requested,
    'accepted': accepted,
    'generated': generated,
    'invalid': invalid,
    'duplicates': duplicates,
    'clean_accepted': cleanAccepted,
    'absolute_clean': absoluteClean,
    'accepted_with_warnings': acceptedWithWarnings,
    'warning_codes': warningCodes,
    'requests': requests,
    'covered_units': coveredUnits,
    'total_units': totalUnits,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'input_tokens_by_stage': <String, int>{
      for (final MapEntry<GenerationStage, int> entry
          in inputTokensByStage.entries)
        entry.key.name: entry.value,
    },
    'output_tokens_by_stage': <String, int>{
      for (final MapEntry<GenerationStage, int> entry
          in outputTokensByStage.entries)
        entry.key.name: entry.value,
    },
    'duplicates_by_level': <String, int>{
      for (final MapEntry<DedupLevel, int> entry in duplicatesByLevel.entries)
        entry.key.wireName: entry.value,
    },
    'yield_per_1k_input_tokens': yieldPer1kInputTokens,
    'acceptance_rate': acceptanceRate,
    'clean_rate': cleanRate,
    'duplicate_rate': duplicateRate,
    'coverage': coverage,
    'mean_covered_salience': meanCoveredSalience,
    'requests_per_10_cards': requestsPer10Cards,
    'batch_p50_ms': p50BatchDuration?.inMilliseconds,
    'batch_p95_ms': p95BatchDuration?.inMilliseconds,
  };
}

/// Считает метрики прогона **только** из [GenerationReport].
class MetricsCollector {
  /// Создаёт collector (без состояния: один экземпляр безопасен).
  const MetricsCollector();

  /// Собирает снимок метрик по [report].
  CollectedMetrics collect(GenerationReport report) {
    int inputTokens = 0;
    int outputTokens = 0;
    final Map<GenerationStage, int> inputByStage = <GenerationStage, int>{};
    final Map<GenerationStage, int> outputByStage = <GenerationStage, int>{};
    for (final MapEntry<GenerationStage, TokenUsage> entry
        in report.tokensByStage.entries) {
      final int input = entry.value.promptTokens ?? 0;
      final int output = entry.value.completionTokens ?? 0;
      inputTokens += input;
      outputTokens += output;
      if (input > 0) inputByStage[entry.key] = input;
      if (output > 0) outputByStage[entry.key] = output;
    }

    final Map<DedupLevel, int> duplicatesByLevel =
        report.duplicatesByLevel.isNotEmpty
        ? report.duplicatesByLevel
        : <DedupLevel, int>{
            if (report.duplicates > 0) DedupLevel.exact: report.duplicates,
          };

    final int coveredUnits = report.coveredUnits;
    final double? meanSalience = _meanCoveredSalience(report);
    final List<Duration> sorted = List<Duration>.of(report.batchDurations)
      ..sort((Duration a, Duration b) => a.compareTo(b));

    return CollectedMetrics(
      requested: report.requested,
      accepted: report.accepted,
      generated: report.generated,
      invalid: report.invalid,
      duplicates: report.duplicates,
      cleanAccepted: report.cleanAccepted,
      absoluteClean: report.absoluteClean,
      acceptedWithWarnings: report.acceptedWithWarnings,
      warningCodes: report.warningCodes,
      requests: report.requests,
      coveredUnits: coveredUnits,
      totalUnits: report.unitCoverage.length,
      inputTokens: inputTokens,
      outputTokens: outputTokens,
      inputTokensByStage: inputByStage,
      outputTokensByStage: outputByStage,
      duplicatesByLevel: duplicatesByLevel,
      yieldPer1kInputTokens: inputTokens <= 0
          ? null
          : report.accepted * 1000 / inputTokens,
      acceptanceRate: report.generated <= 0
          ? null
          : report.accepted / report.generated,
      cleanRate: report.cleanRate,
      duplicateRate: report.duplicateRate,
      coverage: report.unitCoverage.isEmpty
          ? null
          : coveredUnits / report.unitCoverage.length,
      meanCoveredSalience: meanSalience,
      requestsPer10Cards: report.accepted <= 0
          ? null
          : report.requests * 10 / report.accepted,
      p50BatchDuration: _percentile(sorted, 50),
      p95BatchDuration: _percentile(sorted, 95),
    );
  }

  /// Средняя значимость **покрытых** единиц; непокрытые не учитываются.
  static double? _meanCoveredSalience(GenerationReport report) {
    var sum = 0.0;
    var count = 0;
    for (final UnitCoverage coverage in report.unitCoverage) {
      if (!coverage.isCovered) continue;
      final double? salience = coverage.salience;
      if (salience == null) continue;
      sum += salience;
      count++;
    }
    return count == 0 ? null : sum / count;
  }

  /// Процентиль методом ближайшего ранга (как в `GenerationMetrics`).
  static Duration? _percentile(List<Duration> sorted, double percent) {
    if (sorted.isEmpty) return null;
    final int rank = (percent / 100 * sorted.length).ceil().clamp(
      1,
      sorted.length,
    );
    return sorted[rank - 1];
  }
}
