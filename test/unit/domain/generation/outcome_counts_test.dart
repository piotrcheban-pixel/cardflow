import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/outcome_counts.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Контракт среза 16, часть 1: attempted / accepted / unique / clean и
/// производные. Один код для обоих путей — отчёт прогона; знаменатель у всех
/// долей один (все попытки), иначе доля растёт от собственной строгости.
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

  test('производные доли — от всех попыток, а не от принятого', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(
        generated: 10,
        accepted: 6,
        acceptedWithWarnings: 2,
        duplicates: 3,
        blocked: 1,
      ),
    );
    expect(outcome.cleanRate, closeTo(0.4, 1e-12));
    expect(outcome.dupRate, closeTo(0.3, 1e-12));
    expect(outcome.blockRate, closeTo(0.1, 1e-12));
  });

  test('unique вычитает принятые с пометкой дубля', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(generated: 8, accepted: 8, acceptedDuplicates: 2, duplicates: 2),
    );
    expect(outcome.unique, 6);
    expect(outcome.accepted, 8);
  });

  test('нет попыток — доли null, а не ноль', () {
    final OutcomeCounts outcome = OutcomeCounts.fromReport(
      reportOf(generated: 0, accepted: 0),
    );
    expect(outcome.cleanRate, isNull);
    expect(outcome.dupRate, isNull);
    expect(outcome.blockRate, isNull);
  });

  test('отчёт прогона отдаёт те же счётчики (единый код путей)', () {
    final GenerationReport report = reportOf(
      generated: 11,
      accepted: 8,
      duplicates: 3,
    );
    expect(report.outcome.attempted, 11);
    expect(report.outcome.cleanRate, closeTo(8 / 11, 1e-12));
    expect(report.outcome.dupRate, closeTo(3 / 11, 1e-12));
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
