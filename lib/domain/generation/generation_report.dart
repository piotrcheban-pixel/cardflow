/// Отчёт прогона генерации (TASK «Срез 7», п. 4).
///
/// Отчёт — не «сколько вернулось сейчас», а снимок заказа: `requested` и
/// `accepted`, причины недобора машинными кодами, покрытие единиц знания,
/// расход токенов по этапам, версии промптов и длительность. Собирается из
/// журнала (`GenerationLedger`) и итога добора ([ReplenishOutcome]), поэтому
/// ложный успех невозможен: [isComplete] требует и закрытого заказа, и
/// заполненных слотов. Пользовательский текст — в ARB на слое UI, здесь только
/// коды (`journal/QUESTIONS.md` Q17).
library;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Покрытие единицы знания: сколько карточек заказано и сколько принято.
class UnitCoverage {
  /// Создаёт запись покрытия.
  const UnitCoverage({
    required this.unitId,
    required this.planned,
    required this.accepted,
  }) : assert(planned >= 0, 'Заказ по единице не может быть отрицательным'),
       assert(accepted >= 0, 'Принятое по единице не может быть отрицательным');

  /// id единицы карты знаний.
  final String unitId;

  /// Сколько карточек по единице заказано в плане.
  final int planned;

  /// Сколько карточек по единице принято.
  final int accepted;

  /// true — по единице есть хотя бы одна принятая карточка.
  bool get isCovered => accepted > 0;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnitCoverage &&
          other.unitId == unitId &&
          other.planned == planned &&
          other.accepted == accepted;

  @override
  int get hashCode => Object.hash(unitId, planned, accepted);

  @override
  String toString() => 'UnitCoverage($unitId, $accepted/$planned)';
}

/// Отчёт прогона: заказ, принятое, причины, покрытие, расход, версии, время.
class GenerationReport {
  /// Создаёт отчёт; списки и карты копируются и становятся неизменяемыми.
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
    this.unfilledSlots = 0,
  }) : reasons = List<String>.unmodifiable(reasons),
       unitCoverage = List<UnitCoverage>.unmodifiable(unitCoverage),
       tokensByStage = Map<GenerationStage, TokenUsage>.unmodifiable(
         tokensByStage,
       ),
       promptVersions = Map<String, String>.unmodifiable(promptVersions);

  /// Собирает отчёт по итогу добора и плану заказа.
  ///
  /// [initialUsage] — расход первого прохода (этап `generating`);
  /// [initialDuration] — его длительность (суммируется с [outcome]);
  /// [promptVersions] — версии промптов по этапам («generating»,
  /// «replenishing», …): подставляет вызывающий слой, у домена нет промптов.
  factory GenerationReport.fromReplenish({
    required AllocationPlan plan,
    required ReplenishOutcome outcome,
    TokenUsage initialUsage = const TokenUsage(),
    Duration initialDuration = Duration.zero,
    Map<String, String> promptVersions = const <String, String>{},
  }) {
    final List<String> reasons = <String>[];
    if (!outcome.isComplete) {
      _addReason(reasons, outcome.reason.wireName);
      final ShortfallKind? shortfall = outcome.shortfall;
      if (shortfall != null) _addReason(reasons, shortfall.wireName);
      if (outcome.invalid > 0 || outcome.duplicates > 0) {
        _addReason(reasons, ShortfallKind.validationRejects.wireName);
      }
    }

    final Map<String, int> plannedByUnit = <String, int>{};
    for (final AllocatedCard card in plan.cards) {
      plannedByUnit[card.unitId] = (plannedByUnit[card.unitId] ?? 0) + 1;
    }
    final Map<String, int> acceptedByUnit = <String, int>{};
    for (final GeneratedCard card in outcome.acceptedCards) {
      final String? unitId = card.unitId;
      if (unitId == null) continue;
      acceptedByUnit[unitId] = (acceptedByUnit[unitId] ?? 0) + 1;
    }

    return GenerationReport(
      requested: plan.requested,
      accepted: outcome.accepted,
      stage: outcome.stage,
      reason: outcome.reason,
      reasons: reasons,
      unitCoverage: <UnitCoverage>[
        for (final UnitBudget budget in plan.units)
          UnitCoverage(
            unitId: budget.unit.id,
            planned: plannedByUnit[budget.unit.id] ?? budget.cards,
            accepted: acceptedByUnit[budget.unit.id] ?? 0,
          ),
      ],
      tokensByStage: <GenerationStage, TokenUsage>{
        GenerationStage.generating: initialUsage,
        GenerationStage.replenishing: outcome.usage,
      },
      promptVersions: promptVersions,
      duration: initialDuration + outcome.duration,
      passes: outcome.passes.length,
      requests: outcome.requests,
      invalid: outcome.invalid,
      duplicates: outcome.duplicates,
      materialCapacity: outcome.materialCapacity,
      unfilledSlots: outcome.unfilledSlots,
    );
  }

  /// Запрошено карточек (заказ плана).
  final int requested;

  /// Принято карточек (первый проход и добор).
  final int accepted;

  /// Терминальный этап прогона.
  final GenerationStage stage;

  /// Точная причина остановки добора.
  final ReplenishStopReason reason;

  /// Причины недобора машинными кодами: причина остановки, класс недобора и
  /// `validation_rejects`, если карточки отбрасывались. У успеха причин нет.
  final List<String> reasons;

  /// Покрытие единиц знания: заказ и принятое по каждой.
  final List<UnitCoverage> unitCoverage;

  /// Расход токенов по этапам (первый проход и добор).
  ///
  /// Ключа этапа нет в карте — этап не сообщил расход (например, Understanding
  /// в этом срезе не подключался).
  final Map<GenerationStage, TokenUsage> tokensByStage;

  /// Версии промптов по этапам (например, `generating: gen-cards-v3`).
  final Map<String, String> promptVersions;

  /// Длительность прогона.
  final Duration duration;

  /// Сколько проходов добора выполнено.
  final int passes;

  /// Запросов модели за прогон, включая первый проход и повторы.
  final int requests;

  /// Отброшено валидацией/схемой.
  final int invalid;

  /// Отброшено как дубли.
  final int duplicates;

  /// «Материала достаточно примерно на N качественных карточек»; `null` —
  /// материал не признан исчерпанным.
  final int? materialCapacity;

  /// Слотов заказа без принятой карточки.
  final int unfilledSlots;

  /// true — заказ выполнен: этап [GenerationStage.ready], все слоты заполнены и
  /// принято не меньше запрошенного (недобор успехом не считается).
  bool get isComplete =>
      stage == GenerationStage.ready &&
      unfilledSlots == 0 &&
      accepted >= requested;

  /// Долг: `max(0, requested − accepted)`.
  int get remaining => requested > accepted ? requested - accepted : 0;

  /// Единиц с принятой хотя бы одной карточкой.
  int get coveredUnits =>
      unitCoverage.where((UnitCoverage coverage) => coverage.isCovered).length;

  /// Единиц без единой принятой карточки.
  int get uncoveredUnits => unitCoverage.length - coveredUnits;

  static void _addReason(List<String> reasons, String code) {
    if (!reasons.contains(code)) reasons.add(code);
  }

  @override
  String toString() =>
      'GenerationReport(${stage.name}, принято $accepted/$requested, '
      'причины ${reasons.isEmpty ? 'нет' : reasons.join(', ')}, '
      'проходов $passes, запросов $requests, $duration)';
}
