import 'dedup_report.dart';

/// Метрики прогона генерации (TASK «Срез 9», п. 4).
///
/// Только машинные числа и отношения: текстов материалов, промптов и цитат
/// здесь нет (протокол §10). Метрики пишутся в debug-диагностику и в отчёт
/// прогона; значения с `null` означают «данных нет», а не «ноль».
class GenerationMetrics {
  /// Создаёт метрики; отрицательные значения — [AssertionError].
  const GenerationMetrics({
    this.requested = 0,
    this.accepted = 0,
    this.generated = 0,
    this.invalid = 0,
    this.duplicates = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.requests = 0,
    this.batchDurations = const <Duration>[],
    this.duplicatesByLevel = const <DedupLevel, int>{},
    this.coveredUnits = 0,
    this.totalUnits = 0,
  }) : assert(requested >= 0, 'Запрошено не может быть отрицательным'),
       assert(accepted >= 0, 'Принято не может быть отрицательным'),
       assert(generated >= 0, 'Произведено не может быть отрицательным'),
       assert(requests >= 0, 'Запросов не может быть отрицательным');

  /// Пустые метрики (прогон не начинался).
  static const GenerationMetrics empty = GenerationMetrics();

  /// Запрошено карточек (0 — авто-режим).
  final int requested;

  /// Принято карточек.
  final int accepted;

  /// Произведено моделью.
  final int generated;

  /// Отброшено валидацией.
  final int invalid;

  /// Отсеяно точных дублей.
  final int duplicates;

  /// Входные токены (факт `usage` провайдера; 0 — неизвестно).
  final int inputTokens;

  /// Выходные токены (факт `usage`; 0 — неизвестно).
  final int outputTokens;

  /// Число запросов к модели (включая повторы и добор).
  final int requests;

  /// Длительности успешных батчей (для p50/p95).
  final List<Duration> batchDurations;

  /// Дубли по уровням каскада (срез 6).
  final Map<DedupLevel, int> duplicatesByLevel;

  /// Единиц карты, давших принятую карточку.
  final int coveredUnits;

  /// Всего единиц карты (0 — карты нет).
  final int totalUnits;

  /// Выход карточек на 1000 входных токенов (yield).
  double get yieldPerThousandInputTokens =>
      inputTokens <= 0 ? 0 : accepted * 1000 / inputTokens;

  /// Доля принятых от произведённых; `null` — модель ничего не произвела.
  double? get acceptanceRate =>
      generated <= 0 ? null : accepted / generated;

  /// Доля дублей от произведённых; `null` — данных нет.
  double? get duplicateRate => generated <= 0 ? null : duplicates / generated;

  /// Доля дублей по уровням каскада (уровень без пар не попадает в карту).
  Map<DedupLevel, double> get duplicateRateByLevel {
    if (generated <= 0) return const <DedupLevel, double>{};
    return <DedupLevel, double>{
      for (final MapEntry<DedupLevel, int> entry in duplicatesByLevel.entries)
        if (entry.value > 0) entry.key: entry.value / generated,
    };
  }

  /// Покрытие единиц карты; `null` — карты нет.
  double? get unitCoverage =>
      totalUnits <= 0 ? null : coveredUnits / totalUnits;

  /// Запросов на 10 принятых карточек; `null` — принятых нет.
  double? get requestsPerTenCards =>
      accepted <= 0 ? null : requests * 10 / accepted;

  /// Медиана длительности батча (ближайший ранг).
  Duration? get p50BatchDuration => _percentile(50);

  /// 95-й процентиль длительности батча (ближайший ранг).
  Duration? get p95BatchDuration => _percentile(95);

  Duration? _percentile(double percent) {
    if (batchDurations.isEmpty) return null;
    final List<Duration> sorted = List<Duration>.of(batchDurations)
      ..sort((Duration a, Duration b) => a.compareTo(b));
    final int rank = (percent / 100 * sorted.length).ceil().clamp(
      1,
      sorted.length,
    );
    return sorted[rank - 1];
  }

  /// JSON для диагностики и отчёта (только числа и машинные коды).
  Map<String, Object?> toJson() => <String, Object?>{
    'requested': requested,
    'accepted': accepted,
    'generated': generated,
    'invalid': invalid,
    'duplicates': duplicates,
    'input_tokens': inputTokens,
    'output_tokens': outputTokens,
    'requests': requests,
    'yield_per_1k_input_tokens': yieldPerThousandInputTokens,
    'acceptance_rate': acceptanceRate,
    'duplicate_rate': duplicateRate,
    'duplicate_rate_by_level': <String, Object?>{
      for (final MapEntry<DedupLevel, double> entry
          in duplicateRateByLevel.entries)
        entry.key.wireName: entry.value,
    },
    'unit_coverage': unitCoverage,
    'requests_per_10_cards': requestsPerTenCards,
    'batch_p50_ms': p50BatchDuration?.inMilliseconds,
    'batch_p95_ms': p95BatchDuration?.inMilliseconds,
  };
}
