import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/outcome_counts.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Срез 17, часть 0: определения метрики **заморожены** (ADR-054).
///
/// Четыре величины, каждая отвечает на один вопрос и не входит в другую:
/// - `cleanRate = clean / unique` — качество **сохранённой** карточки;
/// - `dupRate = duplicates / unique` — доля сохранённого, оказавшегося повтором;
/// - `blockRate = blocked / attempted` — сколько попыток отсек жёсткий гейт;
/// - `acceptanceRate = accepted / attempted` — сколько попыток дошло до колоды.
///
/// DoD: дубль **не двигает** `cleanRate` — иначе дубли дважды штрафовали бы
/// качество (и в доле чистых, и в собственной доле).
void main() {
  GenerationReport reportOf({
    required int generated,
    required int accepted,
    int acceptedWithWarnings = 0,
    int acceptedDuplicates = 0,
    int duplicates = 0,
    int blocked = 0,
  }) => GenerationReport(
    requested: accepted,
    accepted: accepted,
    stage: GenerationStage.partial,
    reason: ReplenishStopReason.exhaustedMaterial,
    reasons: const <String>[],
    unitCoverage: const <UnitCoverage>[],
    tokensByStage: const <GenerationStage, TokenUsage>{},
    promptVersions: const <String, String>{},
    duration: Duration.zero,
    passes: 0,
    requests: 1,
    generated: generated,
    duplicates: duplicates,
    acceptedWithWarnings: acceptedWithWarnings,
    acceptedDuplicates: acceptedDuplicates,
    blocked: blocked,
  );

  test('определения: attempted / accepted / unique / clean', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(
        generated: 10,
        accepted: 6,
        acceptedWithWarnings: 2,
        duplicates: 3,
        blocked: 1,
      ),
    );
    expect(outcome.attempted, 10);
    expect(outcome.accepted, 6);
    expect(outcome.unique, 6);
    expect(outcome.clean, 4, reason: 'accepted − с пометками');
    expect(outcome.duplicates, 3);
    expect(outcome.blocked, 1);
  });

  test('доли замороженного набора: сохранённое — знаменатель качества', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(
        generated: 10,
        accepted: 6,
        acceptedWithWarnings: 2,
        duplicates: 3,
        blocked: 1,
      ),
    );
    expect(
      outcome.cleanRate,
      closeTo(4 / 6, 1e-12),
      reason: 'cleanRate = чистые / уникальные, а не / все попытки',
    );
    expect(
      outcome.dupRate,
      closeTo(3 / 6, 1e-12),
      reason: 'dupRate = дубли / уникальные',
    );
    expect(
      outcome.blockRate,
      closeTo(1 / 10, 1e-12),
      reason: 'blockRate = блокированные / попытки (единственная от попыток)',
    );
    expect(outcome.acceptanceRate, closeTo(6 / 10, 1e-12));
  });

  test('дубль не двигает cleanRate (DoD части 0, п. 1)', () {
    final OutcomeCounts base = OutcomeCounts.fromReport(
      reportOf(generated: 10, accepted: 6, acceptedWithWarnings: 2),
    );
    final OutcomeCounts withDuplicates = OutcomeCounts.fromReport(
      reportOf(
        generated: 13,
        accepted: 6,
        acceptedWithWarnings: 2,
        duplicates: 3,
      ),
    );
    expect(
      withDuplicates.cleanRate,
      base.cleanRate,
      reason:
          'качество сохранённого не зависит от того, сколько дублей '
          'отложено/удалено',
    );
    expect(base.cleanRate, closeTo(4 / 6, 1e-12));
    expect(base.dupRate, closeTo(0, 1e-12));
    expect(withDuplicates.dupRate, closeTo(3 / 6, 1e-12));
    expect(
      withDuplicates.blockRate,
      base.blockRate,
      reason: 'и blockRate от дублей не зависит',
    );
  });

  test('unique вычитает принятые с пометкой дубля', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(
        generated: 8,
        accepted: 8,
        acceptedWithWarnings: 2,
        acceptedDuplicates: 2,
        duplicates: 2,
      ),
    );
    expect(outcome.unique, 6);
    expect(outcome.accepted, 8);
    expect(outcome.clean, 6);
    expect(outcome.cleanRate, closeTo(1, 1e-12));
  });

  test('нет попыток — доли null, а не ноль', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(generated: 0, accepted: 0),
    );
    expect(outcome.cleanRate, isNull);
    expect(outcome.dupRate, isNull);
    expect(outcome.blockRate, isNull);
    expect(outcome.acceptanceRate, isNull);
  });

  test('отчёт прогона отдаёт те же счётчики (единый код путей)', () {
    final GenerationReport report = reportOf(
      generated: 11,
      accepted: 8,
      duplicates: 3,
    );
    expect(report.outcome.attempted, 11);
    expect(report.outcome.cleanRate, closeTo(8 / 8, 1e-12));
    expect(report.outcome.dupRate, closeTo(3 / 8, 1e-12));
    expect(
      report.cleanRate,
      closeTo(8 / 8, 1e-12),
      reason: 'доля качества в отчёте — замороженное определение, не срез 13',
    );
  });

  test('отрицательные счётчики — ошибка программиста', () {
    expect(
      () => OutcomeCounts(
        attempted: -1,
        accepted: 0,
        unique: 0,
        clean: 0,
        duplicates: 0,
        blocked: 0,
      ),
      throwsA(isA<AssertionError>()),
    );
  });
}
