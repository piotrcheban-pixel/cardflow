/// Отчёт прогона генерации (TASK «Срез 7», п. 4).
///
/// ЗАГЛУШКА красной фазы: поля объявлены, сборка отчёта не реализована.
library;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Покрытие единицы знания: сколько заказано и сколько принято.
class UnitCoverage {
  /// Создаёт запись покрытия.
  const UnitCoverage({
    required this.unitId,
    required this.planned,
    required this.accepted,
  });

  final String unitId;
  final int planned;
  final int accepted;

  bool get isCovered => false;
}

/// Отчёт прогона: заказ, принятое, причины, покрытие, расход, версии, время.
class GenerationReport {
  /// Создаёт отчёт.
  GenerationReport({
    required this.requested,
    required this.accepted,
    required this.stage,
    required this.reason,
    required List<String> reasons,
    required List<UnitCoverage> unitCoverage,
    required Map<GenerationStage, TokenUsage> tokensByStage,
    required Map<String, String> promptVersions,
    required this.duration,
    required this.passes,
    required this.requests,
    this.invalid = 0,
    this.duplicates = 0,
    this.materialCapacity,
  }) : reasons = List<String>.unmodifiable(reasons),
       unitCoverage = List<UnitCoverage>.unmodifiable(unitCoverage),
       tokensByStage = Map<GenerationStage, TokenUsage>.unmodifiable(
         tokensByStage,
       ),
       promptVersions = Map<String, String>.unmodifiable(promptVersions);

  /// Собирает отчёт по итогу добора (заглушка).
  factory GenerationReport.fromReplenish({
    required AllocationPlan plan,
    required ReplenishOutcome outcome,
    TokenUsage initialUsage = const TokenUsage(),
    Duration initialDuration = Duration.zero,
    Map<String, String> promptVersions = const <String, String>{},
  }) => GenerationReport(
    requested: 0,
    accepted: 0,
    stage: GenerationStage.planned,
    reason: ReplenishStopReason.complete,
    reasons: const <String>[],
    unitCoverage: const <UnitCoverage>[],
    tokensByStage: const <GenerationStage, TokenUsage>{},
    promptVersions: const <String, String>{},
    duration: Duration.zero,
    passes: 0,
    requests: 0,
  );

  final int requested;
  final int accepted;
  final GenerationStage stage;
  final ReplenishStopReason reason;
  final List<String> reasons;
  final List<UnitCoverage> unitCoverage;
  final Map<GenerationStage, TokenUsage> tokensByStage;
  final Map<String, String> promptVersions;
  final Duration duration;
  final int passes;
  final int requests;
  final int invalid;
  final int duplicates;
  final int? materialCapacity;

  bool get isComplete => false;
  int get remaining => 0;
  int get coveredUnits => 0;
  int get uncoveredUnits => unitCoverage.length;
}
