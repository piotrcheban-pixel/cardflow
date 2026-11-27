import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generation_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

GenerationMetrics metrics({
  int requested = 0,
  int accepted = 0,
  int generated = 0,
  int invalid = 0,
  int duplicates = 0,
  int inputTokens = 0,
  int outputTokens = 0,
  int requests = 0,
  List<Duration> batchDurations = const <Duration>[],
  Map<DedupLevel, int> duplicatesByLevel = const <DedupLevel, int>{},
  int coveredUnits = 0,
  int totalUnits = 0,
}) {
  return GenerationMetrics(
    requested: requested,
    accepted: accepted,
    generated: generated,
    invalid: invalid,
    duplicates: duplicates,
    inputTokens: inputTokens,
    outputTokens: outputTokens,
    requests: requests,
    batchDurations: batchDurations,
    duplicatesByLevel: duplicatesByLevel,
    coveredUnits: coveredUnits,
    totalUnits: totalUnits,
  );
}

void main() {
  test('yield на 1000 входных токенов: принятые карточки / вход', () {
    expect(
      metrics(accepted: 50, inputTokens: 10000).yieldPerThousandInputTokens,
      5,
    );
    expect(
      metrics(accepted: 3, inputTokens: 1000).yieldPerThousandInputTokens,
      3,
    );
    // Неизвестный вход — 0, а не деление на ноль.
    expect(metrics(accepted: 5).yieldPerThousandInputTokens, 0);
  });

  test('acceptance rate: принято / произведено; нет произведённого — null', () {
    expect(metrics(generated: 60, accepted: 45).acceptanceRate, 0.75);
    expect(metrics(generated: 0).acceptanceRate, isNull);
    expect(metrics(generated: 10, accepted: 10).acceptanceRate, 1);
  });

  test('duplicate rate по уровням каскада', () {
    final GenerationMetrics value = metrics(
      generated: 20,
      accepted: 14,
      duplicates: 6,
      duplicatesByLevel: const <DedupLevel, int>{
        DedupLevel.exact: 4,
        DedupLevel.normalized: 1,
        DedupLevel.semantic: 1,
      },
    );
    expect(value.duplicateRate, 0.3);
    expect(value.duplicateRateByLevel[DedupLevel.exact], 4 / 20);
    expect(value.duplicateRateByLevel[DedupLevel.normalized], 1 / 20);
    expect(value.duplicateRateByLevel[DedupLevel.semantic], 1 / 20);
    expect(value.duplicateRateByLevel.containsKey(DedupLevel.embeddings), isFalse);
  });

  test('покрытие единиц карты и запросов на 10 карточек', () {
    final GenerationMetrics value = metrics(
      accepted: 40,
      requests: 6,
      coveredUnits: 3,
      totalUnits: 4,
    );
    expect(value.unitCoverage, 0.75);
    expect(value.requestsPerTenCards, 1.5);
    expect(metrics(accepted: 0, requests: 3).requestsPerTenCards, isNull);
    expect(metrics().unitCoverage, isNull);
  });

  test('p50/p95 длительности батчей — методом ближайшего ранга', () {
    final GenerationMetrics value = metrics(
      batchDurations: <Duration>[
        const Duration(milliseconds: 10),
        const Duration(milliseconds: 20),
        const Duration(milliseconds: 30),
        const Duration(milliseconds: 40),
        const Duration(milliseconds: 50),
      ],
    );
    expect(value.p50BatchDuration, const Duration(milliseconds: 30));
    expect(value.p95BatchDuration, const Duration(milliseconds: 50));
    expect(value.batchDurations.length, 5);
  });

  test('p50/p95 на чётном числе батчей и пустом списке', () {
    final GenerationMetrics even = metrics(
      batchDurations: <Duration>[
        const Duration(milliseconds: 100),
        const Duration(milliseconds: 200),
        const Duration(milliseconds: 300),
        const Duration(milliseconds: 400),
      ],
    );
    expect(even.p50BatchDuration, const Duration(milliseconds: 200));
    expect(even.p95BatchDuration, const Duration(milliseconds: 400));
    expect(metrics().p50BatchDuration, isNull);
    expect(metrics().p95BatchDuration, isNull);
  });

  test('пустые метрики не бросают и дают нулевые/неопределённые значения', () {
    const GenerationMetrics empty = GenerationMetrics.empty;
    expect(empty.yieldPerThousandInputTokens, 0);
    expect(empty.acceptanceRate, isNull);
    expect(empty.duplicateRate, isNull);
    expect(empty.requestsPerTenCards, isNull);
    expect(empty.unitCoverage, isNull);
    expect(empty.p50BatchDuration, isNull);
  });

  test('JSON метрик: машинные числа и проценты, без строк текста', () {
    final Map<String, Object?> json = metrics(
      requested: 40,
      accepted: 30,
      generated: 36,
      duplicates: 2,
      inputTokens: 12000,
      outputTokens: 4000,
      requests: 5,
      duplicatesByLevel: const <DedupLevel, int>{DedupLevel.exact: 2},
      coveredUnits: 6,
      totalUnits: 8,
      batchDurations: <Duration>[const Duration(milliseconds: 900)],
    ).toJson();
    expect(json['requested'], 40);
    expect(json['accepted'], 30);
    expect(json['yield_per_1k_input_tokens'], closeTo(2.5, 1e-9));
    expect(json['acceptance_rate'], closeTo(30 / 36, 1e-9));
    expect(json['duplicate_rate'], closeTo(2 / 36, 1e-9));
    expect(json['requests_per_10_cards'], closeTo(5 * 10 / 30, 1e-9));
    expect(json['unit_coverage'], closeTo(0.75, 1e-9));
    expect(json['batch_p50_ms'], 900);
    expect(
      (json['duplicate_rate_by_level'] as Map<String, Object?>).keys,
      contains('exact'),
    );
  });
}
