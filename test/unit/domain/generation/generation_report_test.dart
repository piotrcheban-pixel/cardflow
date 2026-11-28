import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/card_reason_code.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Отчёт прогона (TASK «Срез 7», п. 4): заказ, принятое, причины, покрытие
/// единиц, расход токенов по этапам, версии промптов и длительность — из
/// журнала и итога добора, без выдуманных чисел.
void main() {
  group('GenerationReport', () {
    test('недобор: причины, покрытие единиц, расход по этапам, время', () {
      final AllocationPlan plan = _plan(<int>[6, 6, 6, 6, 6, 6, 4]);
      final ReplenishOutcome outcome = _outcome(
        stage: GenerationStage.partial,
        reason: ReplenishStopReason.exhaustedMaterial,
        requested: 40,
        acceptedCards: _cardsOf(plan, <int>[0, 1]),
        requests: 7,
        usage: const TokenUsage(
          promptTokens: 0,
          completionTokens: 0,
          totalTokens: 0,
        ),
        duration: const Duration(seconds: 5),
        unfilledSlots: 28,
      );
      const TokenUsage initialUsage = TokenUsage(
        promptTokens: 4000,
        completionTokens: 2000,
        totalTokens: 6000,
      );

      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: outcome,
        initialUsage: initialUsage,
        initialDuration: const Duration(seconds: 30),
        promptVersions: const <String, String>{
          'generating': 'gen-cards-v3',
          'replenishing': 'gen-cards-v3',
        },
      );

      expect(report.requested, 40);
      expect(report.accepted, 12);
      expect(report.remaining, 28);
      expect(report.stage, GenerationStage.partial);
      expect(report.isComplete, isFalse);
      expect(report.reason, ReplenishStopReason.exhaustedMaterial);
      expect(report.reasons, <String>['exhausted_material']);
      expect(report.materialCapacity, 12);

      expect(report.unitCoverage.length, 7);
      expect(
        report.unitCoverage.fold<int>(
          0,
          (int sum, UnitCoverage coverage) => sum + coverage.planned,
        ),
        40,
      );
      expect(
        report.unitCoverage.fold<int>(
          0,
          (int sum, UnitCoverage coverage) => sum + coverage.accepted,
        ),
        12,
      );
      expect(report.coveredUnits, 2);
      expect(report.uncoveredUnits, 5);
      expect(report.unitCoverage.first.isCovered, isTrue);
      expect(report.unitCoverage[2].isCovered, isFalse);
      expect(report.unitCoverage[2].unitId, 'U2');
      expect(report.unitCoverage[2].planned, 6);
      expect(report.unitCoverage[2].accepted, 0);
      expect(
        report.unitCoverage[2],
        UnitCoverage(
          unitId: 'U2',
          planned: 6,
          accepted: 0,
          salience: _unit('U2').salience,
        ),
      );
      expect(
        report.unitCoverage[2].hashCode,
        UnitCoverage(
          unitId: 'U2',
          planned: 6,
          accepted: 0,
          salience: _unit('U2').salience,
        ).hashCode,
      );
      expect(report.unitCoverage[2].toString(), 'UnitCoverage(U2, 0/6)');
      expect(report.toString(), contains('принято 12/40'));
      expect(report.toString(), contains('exhausted_material'));

      expect(report.tokensByStage[GenerationStage.generating], initialUsage);
      expect(report.tokensByStage[GenerationStage.replenishing], outcome.usage);
      expect(report.promptVersions['generating'], 'gen-cards-v3');
      expect(report.promptVersions['replenishing'], 'gen-cards-v3');
      expect(report.duration, const Duration(seconds: 35));
      expect(report.passes, outcome.passes.length);
      expect(report.requests, 7);
      expect(report.invalid, 0);
      expect(report.duplicates, 0);
    });

    test('полный заказ: причин нет, материал не исчерпан, успех', () {
      final AllocationPlan plan = _plan(<int>[2, 2]);
      final ReplenishOutcome outcome = _outcome(
        stage: GenerationStage.ready,
        reason: ReplenishStopReason.complete,
        requested: 4,
        acceptedCards: _cardsOf(plan, <int>[0, 1]),
        requests: 2,
        usage: const TokenUsage(totalTokens: 300),
        duration: const Duration(seconds: 2),
      );

      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: outcome,
      );

      expect(report.isComplete, isTrue);
      expect(report.reasons, isEmpty);
      expect(report.materialCapacity, isNull);
      expect(report.remaining, 0);
      expect(report.coveredUnits, 2);
      expect(report.uncoveredUnits, 0);
      expect(report.duration, const Duration(seconds: 2));
    });

    test('сбой провайдера — точная причина в отчёте', () {
      final AllocationPlan plan = _plan(<int>[2]);
      final ReplenishOutcome outcome = _outcome(
        stage: GenerationStage.partial,
        reason: ReplenishStopReason.providerError,
        requested: 2,
        requests: 1,
        unfilledSlots: 2,
      );

      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: outcome,
      );

      expect(report.reasons.first, 'provider_error');
      expect(report.isComplete, isFalse);
      expect(report.materialCapacity, isNull);
      expect(report.remaining, 2);
    });

    test('отброшенные карточки видны причиной, но не отменяют итог', () {
      final AllocationPlan plan = _plan(<int>[2]);
      final ReplenishOutcome outcome = _outcome(
        stage: GenerationStage.partial,
        reason: ReplenishStopReason.exhaustedMaterial,
        requested: 2,
        requests: 1,
        invalid: 1,
        unfilledSlots: 2,
      );

      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: outcome,
      );

      expect(report.reasons, <String>[
        'exhausted_material',
        'validation_rejects',
      ]);
      expect(report.invalid, 1);
    });
  });

  group('срез 10 — причины недобора с числами и предохранители', () {
    test('долг только из-за дублей — причина duplicates, а не validation', () {
      final AllocationPlan plan = _plan(<int>[4, 6]);
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          stage: GenerationStage.partial,
          reason: ReplenishStopReason.exhaustedMaterial,
          requested: 10,
          acceptedCards: _cardsOf(plan, <int>[0, 1]).take(8).toList(),
          duplicates: 2,
          unfilledSlots: 2,
        ),
      );

      expect(report.shortfallReasons, <ShortfallKind, int>{
        ShortfallKind.duplicates: 2,
      });
    });

    test('валидация и дубли считаются отдельно, каждая своим числом', () {
      final AllocationPlan plan = _plan(<int>[4, 6]);
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          stage: GenerationStage.partial,
          reason: ReplenishStopReason.exhaustedMaterial,
          requested: 10,
          acceptedCards: _cardsOf(plan, <int>[0, 1]).take(8).toList(),
          invalid: 1,
          duplicates: 1,
          unfilledSlots: 2,
        ),
      );

      expect(report.shortfallReasons, <ShortfallKind, int>{
        ShortfallKind.duplicates: 1,
        ShortfallKind.validationRejects: 1,
      });
    });

    test('исчерпанный материал — число недобора', () {
      final AllocationPlan plan = _plan(<int>[6, 6, 6, 6, 6, 6, 4]);
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          stage: GenerationStage.partial,
          reason: ReplenishStopReason.exhaustedMaterial,
          requested: 40,
          acceptedCards: _cardsOf(plan, <int>[0, 1]),
          unfilledSlots: 28,
        ),
      );

      expect(report.shortfallReasons, <ShortfallKind, int>{
        ShortfallKind.exhaustedMaterial: 28,
      });
    });

    test('предохранители операции попадают в отчёт', () {
      final AllocationPlan plan = _plan(<int>[4, 6]);
      const ReplenishGuards guards = ReplenishGuards(
        maxPasses: 3,
        maxRequests: 10,
        tokenBudget: 5000,
        wallClock: Duration(minutes: 10),
      );
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: ReplenishOutcome(
          stage: GenerationStage.partial,
          reason: ReplenishStopReason.maxPasses,
          requested: 10,
          acceptedCards: _cardsOf(plan, <int>[0]),
          unfilledSlots: 6,
          guards: guards.withHit(ReplenishStopReason.maxPasses),
        ),
      );

      expect(report.guards, isNotNull);
      expect(report.guards!.maxPasses, 3);
      expect(report.guards!.maxRequests, 10);
      expect(report.guards!.wallClock, const Duration(minutes: 10));
      expect(report.guards!.hit, ReplenishStopReason.maxPasses);
      expect(report.guards!.hitsGuard, isTrue);
    });

    test('успех не имеет причин недобора', () {
      final AllocationPlan plan = _plan(<int>[10]);
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          stage: GenerationStage.ready,
          reason: ReplenishStopReason.complete,
          requested: 10,
          acceptedCards: _cardsOf(plan, <int>[0]),
        ),
      );

      expect(report.shortfallReasons, isEmpty);
    });
  });

  group('срез 12 — cleanRate, коды принятых и время батчей', () {
    test('пометка принятой карточки видна кодом, cleanRate из отчёта', () {
      final AllocationPlan plan = _plan(<int>[2]);
      final List<GeneratedCard> cards = _cardsOf(plan, <int>[0]);
      final List<GeneratedCard> accepted = <GeneratedCard>[
        cards.first,
        cards[1].copyWith(
          gateReasons: <CardReasonCode>[CardReasonCode.notAtomic],
        ),
      ];
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          stage: GenerationStage.ready,
          reason: ReplenishStopReason.complete,
          requested: 2,
          acceptedCards: accepted,
          requests: 3,
          usage: const TokenUsage(promptTokens: 400, completionTokens: 100),
        ),
        understandingUsage: const TokenUsage(
          promptTokens: 100,
          completionTokens: 20,
        ),
        batchDurations: const <Duration>[
          Duration(milliseconds: 800),
          Duration(milliseconds: 1200),
        ],
      );

      expect(report.accepted, 2);
      expect(report.acceptedWithWarnings, 1);
      expect(report.cleanAccepted, 1);
      expect(report.cleanRate, 0.5);
      expect(report.warningCodes, <String, int>{'not_atomic': 1});
      expect(report.generated, 2);
      expect(report.batchDurations, hasLength(2));
      expect(
        report.unitCoverage.single.salience,
        plan.units.single.unit.salience,
      );
    });

    test('cleanRate без принятых — null, а не ноль', () {
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: _plan(<int>[2]),
        outcome: _outcome(
          stage: GenerationStage.partial,
          reason: ReplenishStopReason.providerError,
          requested: 2,
          unfilledSlots: 2,
        ),
      );

      expect(report.accepted, 0);
      expect(report.cleanRate, isNull);
    });
  });
}

// --- Помощники -------------------------------------------------------------

const ModelProfile _profile = ModelProfile(
  id: 'deepseek-chat',
  provider: 'deepseek',
  contextWindow: 128000,
  maxOutputTokens: 8192,
  supportsJsonSchema: true,
  supportsVision: false,
  concurrency: 1,
);

/// Ручной план: каждый батч — своя единица, карточки — основная и углы.
AllocationPlan _plan(List<int> batchSizes) {
  final List<UnitBudget> units = <UnitBudget>[];
  final List<AllocatedCard> cards = <AllocatedCard>[];
  final List<AllocationBatch> batches = <AllocationBatch>[];
  for (var index = 0; index < batchSizes.length; index++) {
    final String id = 'U$index';
    final KnowledgeUnit unit = _unit(id);
    final List<AllocatedCard> batchCards = <AllocatedCard>[
      for (var card = 0; card < batchSizes[index]; card++)
        AllocatedCard(
          unitId: id,
          angle: card == 0
              ? null
              : AllocationAngle.values[(card - 1) %
                    AllocationAngle.values.length],
        ),
    ];
    units.add(UnitBudget(unit: unit, cards: batchCards.length));
    cards.addAll(batchCards);
    batches.add(
      AllocationBatch(
        index: index,
        profile: _profile,
        cards: batchCards,
        inputTokens: 900,
        outputTokens: batchCards.length * kDefaultOutputTokensPerCard,
      ),
    );
  }
  return AllocationPlan(
    requested: cards.length,
    profile: _profile,
    units: units,
    cards: cards,
    batches: batches,
  );
}

List<GeneratedCard> _cardsOf(AllocationPlan plan, List<int> batchIndexes) {
  final Set<int> indexes = batchIndexes.toSet();
  return <GeneratedCard>[
    for (final AllocationBatch batch in plan.batches)
      if (indexes.contains(batch.index))
        for (final AllocatedCard card in batch.cards) _cardFor(plan, card),
  ];
}

GeneratedCard _cardFor(AllocationPlan plan, AllocatedCard planned) {
  final KnowledgeUnit unit = plan.units
      .firstWhere((UnitBudget budget) => budget.unit.id == planned.unitId)
      .unit;
  return GeneratedCard(
    front: 'Вопрос ${unit.id}/${planned.angle?.wireName ?? 'primary'}',
    back: unit.statement,
    cardType: CardType.basic,
    unitId: unit.id,
    angle: planned.angle?.wireName,
    quoteRef: unit.anchors.first.quote,
  );
}

KnowledgeUnit _unit(String id) => KnowledgeUnit(
  id: id,
  sectionId: 'doc:материал.md#0',
  topic: 'тема $id',
  kind: KnowledgeUnitKind.definition,
  statement: 'Утверждение единицы $id о моменте силы.',
  anchors: <KnowledgeAnchor>[
    KnowledgeAnchor(
      blockId: 'doc:материал.md#0#0',
      quote: 'Цитата материала $id.',
    ),
  ],
);

ReplenishOutcome _outcome({
  required GenerationStage stage,
  required ReplenishStopReason reason,
  required int requested,
  List<GeneratedCard> acceptedCards = const <GeneratedCard>[],
  List<ReplenishPass> passes = const <ReplenishPass>[],
  int requests = 0,
  int invalid = 0,
  int duplicates = 0,
  TokenUsage usage = const TokenUsage(),
  Duration duration = Duration.zero,
  int unfilledSlots = 0,
}) => ReplenishOutcome(
  stage: stage,
  reason: reason,
  requested: requested,
  acceptedCards: acceptedCards,
  passes: passes,
  requests: requests,
  invalid: invalid,
  duplicates: duplicates,
  usage: usage,
  duration: duration,
  unfilledSlots: unfilledSlots,
);
