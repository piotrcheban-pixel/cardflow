import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/metrics_collector.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// TASK «Срез 12», п. 4: стенд читает **только** `GenerationReport` —
/// единственный источник правды для «было → стало» (legacy и v3).
void main() {
  GenerationReport reportOf({
    int accepted = 10,
    int generated = 14,
    int invalid = 2,
    int duplicates = 2,
    int acceptedWithWarnings = 2,
    int requests = 5,
    Map<DedupLevel, int> duplicatesByLevel = const <DedupLevel, int>{
      DedupLevel.exact: 1,
      DedupLevel.semantic: 1,
    },
    List<UnitCoverage> unitCoverage = const <UnitCoverage>[
      UnitCoverage(unitId: 'U1', planned: 4, accepted: 3, salience: 0.2),
      UnitCoverage(unitId: 'U2', planned: 4, accepted: 2, salience: 0.8),
      UnitCoverage(unitId: 'U3', planned: 2, accepted: 0, salience: 0.5),
    ],
    Map<GenerationStage, TokenUsage> tokensByStage =
        const <GenerationStage, TokenUsage>{
          GenerationStage.understanding: TokenUsage(
            promptTokens: 200,
            completionTokens: 50,
          ),
          GenerationStage.generating: TokenUsage(
            promptTokens: 1000,
            completionTokens: 300,
          ),
          GenerationStage.replenishing: TokenUsage(
            promptTokens: 300,
            completionTokens: 100,
          ),
        },
    List<Duration> batchDurations = const <Duration>[
      Duration(seconds: 10),
      Duration(seconds: 1),
      Duration(seconds: 9),
      Duration(seconds: 2),
      Duration(seconds: 8),
      Duration(seconds: 3),
      Duration(seconds: 7),
      Duration(seconds: 4),
      Duration(seconds: 6),
      Duration(seconds: 5),
    ],
  }) => GenerationReport(
    requested: 12,
    accepted: accepted,
    stage: GenerationStage.ready,
    reason: ReplenishStopReason.complete,
    reasons: const <String>[],
    unitCoverage: unitCoverage,
    tokensByStage: tokensByStage,
    promptVersions: const <String, String>{'generating': 'gen-cards-v3'},
    duration: const Duration(seconds: 20),
    passes: 2,
    requests: requests,
    invalid: invalid,
    duplicates: duplicates,
    generated: generated,
    acceptedWithWarnings: acceptedWithWarnings,
    warningCodes: const <String, int>{'not_atomic': 2},
    duplicatesByLevel: duplicatesByLevel,
    batchDurations: batchDurations,
  );

  test('yield, acceptance, cleanRate, durable rate и запросы на 10', () {
    final CollectedMetrics metrics = const MetricsCollector().collect(
      reportOf(),
    );

    expect(metrics.yieldPer1kInputTokens, closeTo(10 * 1000 / 1500, 1e-9));
    expect(metrics.acceptanceRate, closeTo(10 / 14, 1e-9));
    // Срез 13, п. 8: cleanRate — доля от **произведённых**, не от принятых.
    expect(metrics.cleanRate, closeTo(8 / 14, 1e-9));
    expect(metrics.cleanAccepted, 8);
    // Срез 14, п. 6: рядом с долей — абсолютное число чистых карточек.
    expect(metrics.absoluteClean, 8);
    expect(metrics.acceptedWithWarnings, 2);
    expect(metrics.warningCodes, <String, int>{'not_atomic': 2});
    expect(metrics.duplicateRate, closeTo(2 / 14, 1e-9));
    expect(metrics.requestsPer10Cards, 5);
    expect(metrics.coverage, closeTo(2 / 3, 1e-9));
    expect(metrics.coveredUnits, 2);
    expect(metrics.totalUnits, 3);
  });

  test('meanSalience — только покрытых единиц; непокрытая не тянет вниз', () {
    final CollectedMetrics metrics = const MetricsCollector().collect(
      reportOf(),
    );

    expect(metrics.meanCoveredSalience, closeTo(0.5, 1e-9));
  });

  test('p50/p95 — метод ближайшего ранга из отметок времени', () {
    final CollectedMetrics metrics = const MetricsCollector().collect(
      reportOf(),
    );

    expect(metrics.p50BatchDuration, const Duration(seconds: 5));
    expect(metrics.p95BatchDuration, const Duration(seconds: 10));
  });

  test('расход токенов по этапам — из отчёта, без домыслов', () {
    final CollectedMetrics metrics = const MetricsCollector().collect(
      reportOf(),
    );

    expect(metrics.inputTokens, 1500);
    expect(metrics.outputTokens, 450);
    expect(metrics.inputTokensByStage[GenerationStage.understanding], 200);
    expect(metrics.inputTokensByStage[GenerationStage.generating], 1000);
    expect(metrics.inputTokensByStage[GenerationStage.replenishing], 300);
    expect(metrics.outputTokensByStage[GenerationStage.replenishing], 100);
  });

  test('JSON стенда — числа и машинные коды, без текстов', () {
    final Map<String, Object?> json = const MetricsCollector()
        .collect(reportOf())
        .toJson();

    expect(json['clean_rate'], closeTo(8 / 14, 1e-9));
    expect(json['absolute_clean'], 8);
    expect(json['yield_per_1k_input_tokens'], closeTo(6.6667, 1e-4));
    expect(json['batch_p50_ms'], 5000);
    expect(json['warning_codes'], <String, int>{'not_atomic': 2});
    expect(json['input_tokens_by_stage'], <String, int>{
      'understanding': 200,
      'generating': 1000,
      'replenishing': 300,
    });
    expect(json.containsKey('front'), isFalse);
  });

  test('пер-юнитные данные — в JSON стенда (срез 15, L230)', () {
    final CollectedMetrics metrics = const MetricsCollector().collect(
      reportOf(
        unitCoverage: const <UnitCoverage>[
          UnitCoverage(
            unitId: 'ku:sec1#0',
            sectionId: 'sec1',
            planned: 2,
            accepted: 2,
            produced: 2,
            clean: 1,
            salience: 0.9,
            warningCodes: <String, int>{'not_atomic': 1},
          ),
          UnitCoverage(
            unitId: 'ku:sec1#1',
            sectionId: 'sec1',
            planned: 2,
            accepted: 0,
            produced: 0,
            clean: 0,
            salience: 0.4,
          ),
        ],
      ),
    );
    final List<Object?> units =
        metrics.toJson()['unit_coverage']! as List<Object?>;

    expect(units, hasLength(2));
    expect(units.first, <String, Object?>{
      'unit_id': 'ku:sec1#0',
      'section_id': 'sec1',
      'salience': 0.9,
      'planned': 2,
      'accepted': 2,
      'produced': 2,
      'clean': 1,
      'warning_codes': <String, int>{'not_atomic': 1},
    });
    expect(
      (units.first! as Map<String, Object?>)['front'],
      isNull,
      reason: 'текстов карточек в матрице нет',
    );
  });

  test('пустые данные — null, а не ноль', () {
    final CollectedMetrics metrics = const MetricsCollector().collect(
      reportOf(
        accepted: 0,
        generated: 0,
        invalid: 0,
        duplicates: 0,
        acceptedWithWarnings: 0,
        requests: 0,
        duplicatesByLevel: const <DedupLevel, int>{},
        unitCoverage: const <UnitCoverage>[],
        tokensByStage: const <GenerationStage, TokenUsage>{},
        batchDurations: const <Duration>[],
      ),
    );

    expect(metrics.acceptanceRate, isNull);
    expect(metrics.cleanRate, isNull);
    expect(metrics.duplicateRate, isNull);
    expect(metrics.coverage, isNull);
    expect(metrics.meanCoveredSalience, isNull);
    expect(metrics.requestsPer10Cards, isNull);
    expect(metrics.yieldPer1kInputTokens, isNull);
    expect(metrics.p50BatchDuration, isNull);
    expect(metrics.p95BatchDuration, isNull);
  });
}
