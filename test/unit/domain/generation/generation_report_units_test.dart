// Срез 15, часть 1 (L230): пер-юнитные данные отчёта — unit_id, section_id,
// salience, produced, clean, warningCodes. Без них `matchedSubset` считается по
// агрегатам покрытия (допущение), а не по фактическим числам.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/card_reason_code.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Единица карты с известным разделом и значимостью (для ожиданий).
class _UnitSpec {
  const _UnitSpec(this.id, this.sectionId, this.salience, this.cards);

  final String id;
  final String sectionId;
  final double salience;
  final int cards;
}

void main() {
  group('GenerationReport: пер-юнитные produced/clean/warningCodes', () {
    test('распределение по единицам — из фактических карточек и гейта', () {
      final AllocationPlan plan = _plan(<_UnitSpec>[
        const _UnitSpec('U0', 'doc:материал.md#0', 0.9, 2),
        const _UnitSpec('U1', 'doc:материал.md#1', 0.5, 2),
        const _UnitSpec('U2', 'doc:материал.md#1', 0.2, 2),
      ]);
      final List<GeneratedCard> accepted = <GeneratedCard>[
        _card(plan, 'U0', null),
        _card(plan, 'U0', 'reverse').copyWith(
          gateReasons: const <CardReasonCode>[CardReasonCode.notAtomic],
        ),
        _card(plan, 'U1', null),
        _card(plan, 'U1', 'reverse'),
      ];
      // U2: карточка произведена, но заблокирована гейтом — в принятое не идёт,
      // в произведённое единицы — идёт (в этом смысл честной базы).
      final List<GeneratedCard> blocked = <GeneratedCard>[
        _card(plan, 'U2', null).copyWith(
          gateReasons: const <CardReasonCode>[CardReasonCode.wrongLanguage],
        ),
      ];
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          requested: 6,
          acceptedCards: accepted,
          blockedCards: blocked,
          invalid: 1,
          unfilledSlots: 2,
        ),
        blockedCards: blocked,
      );

      final Map<String, UnitCoverage> byId = <String, UnitCoverage>{
        for (final UnitCoverage coverage in report.unitCoverage)
          coverage.unitId: coverage,
      };

      expect(byId['U0']!.produced, 2);
      expect(byId['U0']!.clean, 1);
      expect(byId['U0']!.accepted, 2);
      expect(byId['U0']!.warningCodes, <String, int>{'not_atomic': 1});
      expect(byId['U0']!.sectionId, 'doc:материал.md#0');
      expect(byId['U0']!.salience, 0.9);

      expect(byId['U1']!.produced, 2);
      expect(byId['U1']!.clean, 2);
      expect(byId['U1']!.warningCodes, isEmpty);
      expect(byId['U1']!.sectionId, 'doc:материал.md#1');

      // Заблокированная карточка: произведена, но не принята и не чистая.
      expect(byId['U2']!.produced, 1);
      expect(byId['U2']!.clean, 0);
      expect(byId['U2']!.accepted, 0);
      expect(byId['U2']!.isCovered, isFalse);
    });

    test('карточка без unit_id не приписывается единице наугад', () {
      final AllocationPlan plan = _plan(<_UnitSpec>[
        const _UnitSpec('U0', 'doc:материал.md#0', 0.5, 2),
      ]);
      final GenerationReport report = GenerationReport.fromReplenish(
        plan: plan,
        outcome: _outcome(
          requested: 2,
          acceptedCards: <GeneratedCard>[
            const GeneratedCard(
              front: 'Вопрос без единицы',
              back: 'Ответ',
              cardType: CardType.basic,
            ),
          ],
        ),
      );

      expect(report.unitCoverage.single.produced, 0);
      expect(report.unitCoverage.single.clean, 0);
      expect(report.unitCoverage.single.accepted, 0);
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

KnowledgeUnit _unit(_UnitSpec spec) => KnowledgeUnit(
  id: spec.id,
  sectionId: spec.sectionId,
  topic: 'тема ${spec.id}',
  kind: KnowledgeUnitKind.definition,
  statement: 'Утверждение единицы ${spec.id} о моменте силы.',
  salience: spec.salience,
  anchors: <KnowledgeAnchor>[
    KnowledgeAnchor(
      blockId: '${spec.sectionId}#0',
      // Срез 16: составной якорь даёт ёмкость 2 даже у малозначимой единицы.
      quote:
          'Цитата материала ${spec.id}. Второе верное утверждение. '
          'Третье верное утверждение.',
    ),
  ],
);

AllocationPlan _plan(List<_UnitSpec> specs) {
  final List<UnitBudget> units = <UnitBudget>[];
  final List<AllocatedCard> cards = <AllocatedCard>[];
  final List<AllocationBatch> batches = <AllocationBatch>[];
  for (var index = 0; index < specs.length; index++) {
    final _UnitSpec spec = specs[index];
    final List<AllocatedCard> batchCards = <AllocatedCard>[
      for (var card = 0; card < spec.cards; card++)
        AllocatedCard(
          unitId: spec.id,
          angle: card == 0
              ? null
              : AllocationAngle.values[(card - 1) %
                    AllocationAngle.values.length],
        ),
    ];
    units.add(UnitBudget(unit: _unit(spec), cards: batchCards.length));
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

GeneratedCard _card(AllocationPlan plan, String unitId, String? angle) {
  final KnowledgeUnit unit = plan.units
      .firstWhere((UnitBudget budget) => budget.unit.id == unitId)
      .unit;
  return GeneratedCard(
    front: 'Вопрос $unitId/${angle ?? 'primary'}',
    back: unit.statement,
    cardType: CardType.basic,
    unitId: unitId,
    angle: angle,
    quoteRef: unit.anchors.first.quote,
  );
}

ReplenishOutcome _outcome({
  required int requested,
  List<GeneratedCard> acceptedCards = const <GeneratedCard>[],
  List<GeneratedCard> blockedCards = const <GeneratedCard>[],
  int invalid = 0,
  int unfilledSlots = 0,
}) => ReplenishOutcome(
  stage: GenerationStage.partial,
  reason: ReplenishStopReason.exhaustedMaterial,
  requested: requested,
  acceptedCards: acceptedCards,
  blockedCards: blockedCards,
  requests: 1,
  invalid: invalid,
  unfilledSlots: unfilledSlots,
);
