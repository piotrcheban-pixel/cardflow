// Срез 14, часть 1: ёмкость различимых слотов (`unit_id + angle`).
//
// План не может содержать два одинаковых слота: у единицы не больше
// `kMaxCardsPerUnit` различимых слотов (основная карточка и три угла). Заказ
// больше ёмкости не обрезает `requested` и не выдумывает повторы: `planned`
// равен ёмкости, план помечен `materialLimited` с числом `capacity`.
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const ModelProfile profile = ModelProfile(
    id: 'big',
    provider: 'test',
    contextWindow: 1000000,
    maxOutputTokens: 100000,
    supportsJsonSchema: true,
    supportsVision: true,
    concurrency: 4,
  );

  KnowledgeUnit unit(int index) => KnowledgeUnit(
    id: 'ku:$index',
    sectionId: 'doc:test#0',
    topic: 'тема $index',
    kind: KnowledgeUnitKind.fact,
    statement: 'Утверждение материала номер $index',
    anchors: <KnowledgeAnchor>[
      KnowledgeAnchor(blockId: 'doc:test#0#$index', quote: 'цитата $index'),
    ],
    salience: 0.5 + (index % 5) / 10,
  );

  KnowledgeMap mapOf(List<KnowledgeUnit> units) =>
      KnowledgeMap(documentId: 'doc:test', units: units);

  AllocationPlan planFor({
    required List<KnowledgeUnit> units,
    required int requested,
  }) => planAllocation(
    map: mapOf(units),
    requestedCards: requested,
    profile: profile,
  );

  /// Слот карточки плана: единица и угол (`primary` — основная).
  String slotOf(AllocatedCard card) =>
      '${card.unitId}\u0000${card.angle?.wireName ?? 'primary'}';

  test('300 запрошено, 47 единиц → planned == ёмкость по богатству, без '
      'повторов слотов', () {
    final List<KnowledgeUnit> units = <KnowledgeUnit>[
      for (var index = 0; index < 47; index++) unit(index),
    ];
    // Срез 16: ёмкость — Σ unitCapacity, а не 4 × 47 = 188. У короткого факта
    // один-два различимых вопроса, и больше не заказывается.
    final int capacity = units.fold<int>(
      0,
      (int sum, KnowledgeUnit unit) => sum + unitCapacity(unit),
    );
    expect(capacity, lessThan(47 * kMaxCardsPerUnit));

    final AllocationPlan plan = planFor(units: units, requested: 300);

    expect(plan.requested, 300, reason: 'заказ пользователя не меняется');
    expect(plan.plannedCards, capacity);
    expect(plan.capacity, capacity);
    expect(plan.shortfall, 300 - capacity);
    expect(plan.materialLimited, isTrue);
    expect(plan.cards, hasLength(capacity));

    final Set<String> slots = <String>{};
    for (final AllocatedCard card in plan.cards) {
      expect(
        slots.add(slotOf(card)),
        isTrue,
        reason: 'слот ${slotOf(card)} повторён в плане',
      );
    }
    expect(slots, hasLength(capacity), reason: '$capacity различимых слотов');
    for (final UnitBudget budget in plan.units) {
      expect(
        budget.cards,
        lessThanOrEqualTo(unitCapacity(budget.unit)),
        reason: 'у единицы не больше углов, чем различимых вопросов',
      );
    }
  });

  test('заказ в пределах ёмкости не обрезается', () {
    // Богатые единицы: по четыре различимых вопроса — ёмкости хватает.
    final List<KnowledgeUnit> units = <KnowledgeUnit>[
      for (var index = 0; index < 10; index++)
        KnowledgeUnit(
          id: 'ku:$index',
          sectionId: 'doc:test#0',
          topic: 'тема $index',
          kind: KnowledgeUnitKind.procedure,
          statement: 'Утверждение материала номер $index',
          anchors: <KnowledgeAnchor>[
            KnowledgeAnchor(
              blockId: 'doc:test#0#$index',
              quote:
                  'Первое верное утверждение. Второе верное утверждение. '
                  'Третье верное утверждение.',
            ),
          ],
          salience: 1,
        ),
    ];

    final AllocationPlan plan = planFor(units: units, requested: 30);

    expect(plan.requested, 30);
    expect(plan.plannedCards, 30, reason: 'ёмкости хватает: заказ покрыт');
    expect(plan.capacity, 30);
    expect(plan.shortfall, 0);
    expect(plan.materialLimited, isFalse);
  });

  test('конструктор плана отвергает повтор слота, а не тест постфактум', () {
    final KnowledgeUnit single = unit(0);
    final UnitBudget budget = UnitBudget(unit: single, cards: 2);

    expect(
      () => AllocationPlan(
        requested: 2,
        profile: profile,
        units: <UnitBudget>[budget],
        cards: const <AllocatedCard>[
          AllocatedCard(unitId: 'ku:0'),
          AllocatedCard(unitId: 'ku:0'),
        ],
        batches: const <AllocationBatch>[],
      ),
      throwsAssertionError,
      reason: 'две основные карточки одной единицы — один и тот же слот',
    );
  });

  test('конструктор плана отвергает карточки сверх ёмкости единиц', () {
    final KnowledgeUnit single = unit(0);
    final UnitBudget budget = UnitBudget(unit: single, cards: 1);

    expect(
      () => AllocationPlan(
        requested: 1,
        profile: profile,
        units: <UnitBudget>[budget],
        cards: const <AllocatedCard>[
          AllocatedCard(unitId: 'ku:0'),
          AllocatedCard(unitId: 'ku:0', angle: AllocationAngle.reverse),
        ],
        batches: const <AllocationBatch>[],
      ),
      throwsAssertionError,
      reason: 'карточек больше, чем различимых слотов у единиц',
    );
  });
}
