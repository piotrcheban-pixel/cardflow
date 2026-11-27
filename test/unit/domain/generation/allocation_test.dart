import 'dart:math' as math;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт этапа Allocation (TASK «Срез 4», ADR-050, `ARCH.md` §2):
/// вес единицы, распределение наибольшими остатками, минимум одна карточка на
/// отобранную единицу, добор «вторым углом» и упаковка батчей под профиль.
void main() {
  const TokenEstimator estimator = TokenEstimator();
  const ModelProfile bigProfile = ModelProfile(
    id: 'big',
    provider: 'test',
    contextWindow: 1000000,
    maxOutputTokens: 100000,
    supportsJsonSchema: true,
    supportsVision: true,
    concurrency: 4,
  );

  KnowledgeUnit unit({
    String id = 'ku:unit',
    KnowledgeUnitKind kind = KnowledgeUnitKind.fact,
    double salience = 1,
    String statement = 'Фотосинтез',
    String? sectionId,
  }) => KnowledgeUnit(
    id: id,
    sectionId: sectionId ?? 'doc:test#0',
    topic: 'тема',
    kind: kind,
    statement: statement,
    anchors: <KnowledgeAnchor>[
      KnowledgeAnchor(blockId: 'doc:test#0#0', quote: 'цитата $id'),
    ],
    salience: salience,
  );

  KnowledgeMap mapOf(List<KnowledgeUnit> units) =>
      KnowledgeMap(documentId: 'doc:test', units: units);

  int unitInputTokens(KnowledgeUnit unit) {
    var tokens = kUnitFramingTokens + estimator.estimate(unit.statement);
    for (final KnowledgeAnchor anchor in unit.anchors) {
      tokens += estimator.estimate(anchor.quote);
    }
    return tokens;
  }

  listOfCards(List<AllocatedCard> cards) => <Object>[
    for (final AllocatedCard card in cards)
      <String, Object?>{'unit': card.unitId, 'angle': card.angle?.wireName},
  ];

  listOfBatches(List<AllocationBatch> batches) => <Object>[
    for (final AllocationBatch batch in batches)
      <String, Object?>{
        'cards': listOfCards(batch.cards),
        'input': batch.inputTokens,
        'output': batch.outputTokens,
      },
  ];

  group('Вес единицы: salience × плотность × тип', () {
    test('плотность — доля значимых слов утверждения', () {
      expect(
        unitDensity(
          unit(
            statement:
                'Фотосинтез превращает свет в химическую '
                'энергию',
          ),
        ),
        closeTo(5 / 6, 1e-9),
        reason: '«в» — служебное слово, остальные значимые',
      );
      expect(
        unitDensity(unit(statement: 'Фотосинтез')),
        1,
        reason: 'Одно значимое слово — максимальная плотность',
      );
    });

    test('плотность не падает ниже пола и не зависит от длины', () {
      expect(
        unitDensity(unit(statement: 'и в на с по')),
        kMinUnitDensity,
        reason: 'Только служебные слова — пол 0,25, а не 0',
      );
      expect(
        unitDensity(unit(statement: '— — —')),
        kMinUnitDensity,
        reason: 'Нет слов — пол',
      );
      final KnowledgeUnit shortDense = unit(statement: 'PV = nRT');
      final KnowledgeUnit longDense = unit(
        statement: 'PV = nRT ${'очень ' * 40}',
      );
      expect(unitDensity(shortDense), greaterThanOrEqualTo(kMinUnitDensity));
      expect(unitDensity(longDense), greaterThanOrEqualTo(kMinUnitDensity));
    });

    test('множители вида: ключевые единицы весят больше фактов', () {
      expect(kindWeight(KnowledgeUnitKind.definition), 1.25);
      expect(kindWeight(KnowledgeUnitKind.formula), 1.2);
      expect(kindWeight(KnowledgeUnitKind.relation), 1.1);
      expect(kindWeight(KnowledgeUnitKind.procedure), 1.05);
      expect(kindWeight(KnowledgeUnitKind.fact), 1);
      for (final KnowledgeUnitKind kind in KnowledgeUnitKind.values) {
        expect(kindWeight(kind), greaterThan(0));
      }
      expect(
        kindWeight(KnowledgeUnitKind.definition),
        greaterThan(kindWeight(KnowledgeUnitKind.fact)),
      );
    });

    test('вес = salience × плотность × тип', () {
      final KnowledgeUnit definition = unit(
        kind: KnowledgeUnitKind.definition,
        salience: 0.5,
      );
      expect(unitWeight(definition), closeTo(0.5 * 1 * 1.25, 1e-12));
      final KnowledgeUnit fact = unit(salience: 0.8, statement: 'и в на');
      expect(
        unitWeight(fact),
        closeTo(0.8 * kMinUnitDensity * 1, 1e-12),
        reason: 'Разбавленное утверждение весит меньше',
      );
      expect(unitWeight(unit(salience: 0)), 0);
    });
  });

  group('Распределение наибольшими остатками', () {
    test('по одной карточке, когда заказ равен числу единиц', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1'),
        unit(id: 'ku:2'),
        unit(id: 'ku:3'),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 3,
      );
      expect(budgets, hasLength(3));
      for (final UnitBudget budget in budgets) {
        expect(budget.cards, 1);
        expect(budget.angledCards, 0);
      }
    });

    test('остаток делится пропорционально весам, сумма равна заказу', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1', salience: 1),
        unit(id: 'ku:2', salience: 0.5),
        unit(id: 'ku:3', salience: 0.25),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 10,
      );
      expect(
        <int>[for (final UnitBudget budget in budgets) budget.cards],
        <int>[5, 3, 2],
        reason: 'Минимум 1 + остаток 7 по весам 1 : 0,5 : 0,25',
      );
      expect(
        budgets.fold<int>(0, (int sum, UnitBudget b) => sum + b.cards),
        10,
      );
    });

    test('равные остатки раздаются по порядку единиц (детерминизм)', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1'),
        unit(id: 'ku:2'),
        unit(id: 'ku:3'),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 5,
      );
      expect(
        <int>[for (final UnitBudget budget in budgets) budget.cards],
        <int>[2, 2, 1],
      );
    });

    test('заказ меньше числа единиц — отбираются самые весомые', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1', salience: 0.2),
        unit(id: 'ku:2', salience: 0.9),
        unit(id: 'ku:3', salience: 0.5),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 2,
      );
      expect(
        <String>[for (final UnitBudget b in budgets) b.unit.id],
        <String>['ku:2', 'ku:3'],
      );
      expect(<int>[for (final UnitBudget b in budgets) b.cards], <int>[1, 1]);
    });

    test('заказ меньше единиц: равные веса — первые по порядку', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1'),
        unit(id: 'ku:2'),
        unit(id: 'ku:3'),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 2,
      );
      expect(
        <String>[for (final UnitBudget b in budgets) b.unit.id],
        <String>['ku:1', 'ku:2'],
      );
    });

    test('большой заказ не теряет карточки (BigInt-арифметика)', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1'),
        unit(id: 'ku:2'),
        unit(id: 'ku:3'),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 1000000,
      );
      expect(
        budgets.fold<int>(0, (int sum, UnitBudget b) => sum + b.cards),
        1000000,
      );
      expect(
        <int>[for (final UnitBudget b in budgets) b.cards],
        <int>[333334, 333333, 333333],
      );
    });

    test('крошечный вес не обнуляется и не съедает заказ', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1', salience: 1),
        unit(id: 'ku:2', salience: 1e-9),
      ];
      final List<UnitBudget> budgets = allocateUnits(
        units: units,
        requestedCards: 4,
      );
      expect(budgets.fold<int>(0, (int sum, UnitBudget b) => sum + b.cards), 4);
      expect(
        <int>[for (final UnitBudget b in budgets) b.cards],
        <int>[3, 1],
        reason: 'У каждой единицы минимум 1 карточка',
      );
    });

    test('единицы с нулевым весом не отбираются', () {
      final List<UnitBudget> budgets = allocateUnits(
        units: <KnowledgeUnit>[unit(id: 'ku:1', salience: 0)],
        requestedCards: 5,
      );
      expect(budgets, isEmpty);
    });

    test('неположительный заказ — ArgumentError', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[unit(id: 'ku:1')];
      expect(
        () => allocateUnits(units: units, requestedCards: 0),
        throwsArgumentError,
      );
      expect(
        () => allocateUnits(units: units, requestedCards: -3),
        throwsArgumentError,
      );
      expect(
        () => planAllocation(
          map: mapOf(units),
          requestedCards: 0,
          profile: bigProfile,
        ),
        throwsArgumentError,
      );
    });
  });

  group('Добор «вторым углом»', () {
    test('угол по виду единицы: reverse | cloze | application', () {
      expect(
        preferredAngleForKind(KnowledgeUnitKind.definition),
        AllocationAngle.reverse,
      );
      expect(
        preferredAngleForKind(KnowledgeUnitKind.relation),
        AllocationAngle.reverse,
      );
      expect(
        preferredAngleForKind(KnowledgeUnitKind.formula),
        AllocationAngle.cloze,
      );
      expect(
        preferredAngleForKind(KnowledgeUnitKind.fact),
        AllocationAngle.cloze,
      );
      expect(
        preferredAngleForKind(KnowledgeUnitKind.procedure),
        AllocationAngle.application,
      );
      expect(
        <String>[
          for (final AllocationAngle angle in AllocationAngle.values)
            angle.wireName,
        ],
        <String>['reverse', 'cloze', 'application'],
      );
    });

    test('единиц меньше заказа — добор только флагами angle', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:d', kind: KnowledgeUnitKind.definition),
        unit(id: 'ku:p', kind: KnowledgeUnitKind.procedure),
      ];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 5,
        profile: bigProfile,
      );
      expect(plan.plannedCards, 5);
      expect(plan.angledCards, 3, reason: '5 карточек на 2 утверждения');
      expect(plan.unitsBelowRequested, isTrue);
      expect(plan.distinctStatements, 2);
      expect(_angles(plan.cards), <String?>[
        'ku:d',
        null,
        'ku:d',
        'reverse',
        'ku:d',
        'cloze',
        'ku:p',
        null,
        'ku:p',
        'application',
      ]);
      for (final KnowledgeUnit unit in units) {
        final Iterable<AllocatedCard> primaries = plan.cards.where(
          (AllocatedCard card) => card.unitId == unit.id && card.isPrimary,
        );
        expect(
          primaries,
          hasLength(1),
          reason: 'Второй основной карточки (повтора statement) быть не может',
        );
      }
      for (final AllocatedCard card in plan.cards) {
        if (card.isPrimary) continue;
        expect(
          card.angle,
          isNotNull,
          reason: 'Добор идёт только флагами angle',
        );
      }
    });

    test('углы идут циклом, а не повторяют основную карточку', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:a', kind: KnowledgeUnitKind.definition),
      ];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 5,
        profile: bigProfile,
      );
      expect(_angles(plan.cards), <String?>[
        'ku:a',
        null,
        'ku:a',
        'reverse',
        'ku:a',
        'cloze',
        'ku:a',
        'application',
        'ku:a',
        'reverse',
      ]);
      expect(plan.angledCards, 4);
      expect(plan.distinctStatements, 1);
    });
  });

  group('Упаковка батчей', () {
    const ModelProfile outputLimited = ModelProfile(
      id: 'output-limited',
      provider: 'test',
      contextWindow: 8000,
      maxOutputTokens: 900,
      supportsJsonSchema: false,
      supportsVision: false,
      concurrency: 2,
    );

    test('батч ограничен пределом вывода профиля', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[unit(id: 'ku:1')];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 10,
        profile: outputLimited,
      );
      expect(
        <int>[for (final AllocationBatch b in plan.batches) b.cards.length],
        <int>[3, 3, 3, 1],
        reason: '900 / 300 = 3 карточки на ответ',
      );
      final int input = kRequestOverheadTokens + unitInputTokens(units.single);
      for (final AllocationBatch batch in plan.batches) {
        expect(batch.inputTokens, input);
        expect(
          batch.outputTokens,
          batch.cards.length * kDefaultOutputTokensPerCard,
        );
        expect(batch.fitsProfile, isTrue);
        expect(batch.totalTokens, batch.inputTokens + batch.outputTokens);
      }
      expect(
        <int>[for (final AllocationBatch b in plan.batches) b.outputTokens],
        <int>[900, 900, 900, 300],
      );
    });

    test('батч ограничен 40 % окна контекста', () {
      const ModelProfile windowLimited = ModelProfile(
        id: 'window-limited',
        provider: 'test',
        contextWindow: 5000,
        maxOutputTokens: 5000,
        supportsJsonSchema: false,
        supportsVision: false,
        concurrency: 1,
      );
      final List<KnowledgeUnit> units = <KnowledgeUnit>[unit(id: 'ku:1')];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 10,
        profile: windowLimited,
      );
      expect(windowLimited.batchTokenBudget, 2000);
      expect(
        <int>[for (final AllocationBatch b in plan.batches) b.cards.length],
        <int>[2, 2, 2, 2, 2],
        reason: 'Вход 1234 + 2 × 300 = 1834 ≤ 2000, три карточки — уже 2134',
      );
      for (final AllocationBatch batch in plan.batches) {
        expect(
          batch.totalTokens,
          lessThanOrEqualTo(windowLimited.batchTokenBudget),
        );
      }
    });

    test('резерв схемы входа — только при supportsJsonSchema', () {
      const ModelProfile withoutSchema = ModelProfile(
        id: 'no-schema',
        provider: 'test',
        contextWindow: 10000,
        maxOutputTokens: 10000,
        supportsJsonSchema: false,
        supportsVision: false,
        concurrency: 1,
      );
      const ModelProfile withSchema = ModelProfile(
        id: 'with-schema',
        provider: 'test',
        contextWindow: 10000,
        maxOutputTokens: 10000,
        supportsJsonSchema: true,
        supportsVision: false,
        concurrency: 1,
      );
      final List<KnowledgeUnit> units = <KnowledgeUnit>[unit(id: 'ku:1')];
      final AllocationPlan without = planAllocation(
        map: mapOf(units),
        requestedCards: 10,
        profile: withoutSchema,
      );
      final AllocationPlan withSchemaPlan = planAllocation(
        map: mapOf(units),
        requestedCards: 10,
        profile: withSchema,
      );
      expect(
        <int>[for (final AllocationBatch b in without.batches) b.cards.length],
        <int>[9, 1],
      );
      expect(
        <int>[
          for (final AllocationBatch b in withSchemaPlan.batches)
            b.cards.length,
        ],
        <int>[6, 4],
        reason: 'Схема съедает 900 токенов входа',
      );
      expect(
        without.batches.first.inputTokens + kSchemaOverheadTokens,
        withSchemaPlan.batches.first.inputTokens,
      );
    });

    test('разные единицы в одном батче суммируются по входу', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        unit(id: 'ku:1', statement: 'Первое утверждение'),
        unit(id: 'ku:2', statement: 'Второе утверждение'),
      ];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 2,
        profile: bigProfile,
      );
      expect(plan.batches, hasLength(1));
      expect(
        plan.batches.single.inputTokens,
        kRequestOverheadTokens +
            kSchemaOverheadTokens +
            unitInputTokens(units[0]) +
            unitInputTokens(units[1]),
      );
      expect(plan.batches.single.outputTokens, 2 * kDefaultOutputTokensPerCard);
    });

    test('карточки одной единицы переиспользуют вход батча', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[unit(id: 'ku:1')];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 3,
        profile: bigProfile,
      );
      expect(plan.batches, hasLength(1));
      expect(
        plan.batches.single.inputTokens,
        kRequestOverheadTokens +
            kSchemaOverheadTokens +
            unitInputTokens(units.single),
        reason: 'Вход считается по единице, а не по карточке',
      );
      expect(plan.batches.single.cards, hasLength(3));
    });

    test('единица, не влезающая в бюджет, — ArgumentError', () {
      const ModelProfile small = ModelProfile(
        id: 'small',
        provider: 'test',
        contextWindow: 32000,
        maxOutputTokens: 4096,
        supportsJsonSchema: false,
        supportsVision: false,
        concurrency: 1,
      );
      final KnowledgeUnit huge = unit(id: 'ku:huge', statement: 'а' * 40000);
      expect(
        () => planAllocation(
          map: mapOf(<KnowledgeUnit>[huge]),
          requestedCards: 2,
          profile: small,
        ),
        throwsArgumentError,
        reason: 'Даже одна карточка не влезает в 40 % окна',
      );
    });

    test('неположительная оценка выхода карточки — ArgumentError', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[unit(id: 'ku:1')];
      expect(
        () => packBatches(
          units: allocateUnits(units: units, requestedCards: 1),
          cards: allocateCards(allocateUnits(units: units, requestedCards: 1)),
          profile: bigProfile,
          outputTokensPerCard: 0,
        ),
        throwsArgumentError,
      );
      expect(
        () => packBatches(
          units: allocateUnits(units: units, requestedCards: 1),
          cards: allocateCards(allocateUnits(units: units, requestedCards: 1)),
          profile: bigProfile,
          outputTokensPerCard: -1,
        ),
        throwsArgumentError,
      );
    });

    test('пустой план карточек — нет батчей', () {
      expect(
        packBatches(
          units: const <UnitBudget>[],
          cards: const <AllocatedCard>[],
          profile: bigProfile,
        ),
        isEmpty,
      );
    });

    test('карточка неизвестной единицы — ArgumentError', () {
      expect(
        () => packBatches(
          units: const <UnitBudget>[],
          cards: const <AllocatedCard>[AllocatedCard(unitId: 'ku:none')],
          profile: bigProfile,
        ),
        throwsArgumentError,
        reason: 'Вход батча считается по единице карты',
      );
    });

    test('батчи сохраняют все карточки и их порядок', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        for (var i = 0; i < 6; i++)
          unit(id: 'ku:$i', statement: 'Утверждение номер $i'),
      ];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 20,
        profile: outputLimited,
      );
      final List<AllocatedCard> flattened = <AllocatedCard>[
        for (final AllocationBatch batch in plan.batches) ...batch.cards,
      ];
      expect(
        flattened,
        plan.cards,
        reason: 'Батчи не теряют и не меняют порядок',
      );
      expect(
        <int>[for (final AllocationBatch b in plan.batches) b.index],
        <int>[for (var i = 0; i < plan.batches.length; i++) i],
      );
    });

    test('волны исполнения — по profile.concurrency', () {
      const ModelProfile oneCard = ModelProfile(
        id: 'one-card',
        provider: 'test',
        contextWindow: 8000,
        maxOutputTokens: 300,
        supportsJsonSchema: false,
        supportsVision: false,
        concurrency: 2,
      );
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        for (var i = 0; i < 5; i++) unit(id: 'ku:$i'),
      ];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 5,
        profile: oneCard,
      );
      expect(plan.batches, hasLength(5));
      expect(
        <int>[for (final List<AllocationBatch> wave in plan.waves) wave.length],
        <int>[2, 2, 1],
        reason: 'concurrency = 2',
      );
      expect(
        plan.waves.expand((List<AllocationBatch> wave) => wave).toList(),
        plan.batches,
      );

      final List<KnowledgeUnit> two = <KnowledgeUnit>[
        unit(id: 'ku:1'),
        unit(id: 'ku:2'),
      ];
      final AllocationPlan small = planAllocation(
        map: mapOf(two),
        requestedCards: 2,
        profile: oneCard,
      );
      expect(small.waves, hasLength(1));
      expect(small.waves.single, hasLength(2));

      final AllocationPlan empty = planAllocation(
        map: mapOf(<KnowledgeUnit>[unit(id: 'ku:0', salience: 0)]),
        requestedCards: 3,
        profile: oneCard,
      );
      expect(empty.waves, isEmpty);
    });
  });

  group('Инварианты типов', () {
    test('UnitBudget: минимум одна карточка, число доборных', () {
      final UnitBudget budget = UnitBudget(unit: unit(id: 'ku:1'), cards: 3);
      expect(budget.angledCards, 2);
      expect(budget.toString(), contains('ku:1'));
      expect(
        () => UnitBudget(unit: unit(id: 'ku:2'), cards: 0),
        throwsAssertionError,
      );
    });

    test('AllocatedCard: равенство, основная/доборная, строка', () {
      const AllocatedCard primary = AllocatedCard(unitId: 'ku:1');
      const AllocatedCard same = AllocatedCard(unitId: 'ku:1');
      const AllocatedCard angled = AllocatedCard(
        unitId: 'ku:1',
        angle: AllocationAngle.cloze,
      );
      expect(primary.isPrimary, isTrue);
      expect(angled.isPrimary, isFalse);
      expect(primary, same);
      expect(primary.hashCode, same.hashCode);
      expect(primary, isNot(angled));
      expect(primary.toString(), contains('primary'));
      expect(angled.toString(), contains('cloze'));
    });

    test('AllocationBatch: инварианты профиля и строка', () {
      const ModelProfile profile = ModelProfile(
        id: 'batch',
        provider: 'test',
        contextWindow: 10000,
        maxOutputTokens: 2000,
        supportsJsonSchema: false,
        supportsVision: false,
        concurrency: 1,
      );
      const AllocatedCard card = AllocatedCard(unitId: 'ku:1');
      final AllocationBatch good = AllocationBatch(
        index: 0,
        profile: profile,
        cards: const <AllocatedCard>[card],
        inputTokens: 3000,
        outputTokens: 300,
      );
      expect(good.totalTokens, 3300);
      expect(good.fitsProfile, isTrue);
      expect(good.toString(), contains('1 карт.'));
      expect(
        () => AllocationBatch(
          index: -1,
          profile: profile,
          cards: const <AllocatedCard>[card],
          inputTokens: 100,
          outputTokens: 100,
        ),
        throwsAssertionError,
      );
      expect(
        () => AllocationBatch(
          index: 0,
          profile: profile,
          cards: const <AllocatedCard>[],
          inputTokens: 100,
          outputTokens: 100,
        ),
        throwsAssertionError,
      );
      expect(
        () => AllocationBatch(
          index: 0,
          profile: profile,
          cards: const <AllocatedCard>[card],
          inputTokens: 100,
          outputTokens: 2001,
        ),
        throwsAssertionError,
        reason: 'Выход больше maxOutputTokens',
      );
      expect(
        () => AllocationBatch(
          index: 0,
          profile: profile,
          cards: const <AllocatedCard>[card],
          inputTokens: 3900,
          outputTokens: 300,
        ),
        throwsAssertionError,
        reason: 'Вход + выход больше 40 % окна',
      );
    });

    test('AllocationPlan: заказ положителен, сумма карточек равна заказу', () {
      final UnitBudget budget = UnitBudget(unit: unit(id: 'ku:1'), cards: 2);
      final AllocationBatch batch = AllocationBatch(
        index: 0,
        profile: bigProfile,
        cards: allocateCards(<UnitBudget>[budget]),
        inputTokens: 1000,
        outputTokens: 600,
      );
      final AllocationPlan plan = AllocationPlan(
        requested: 2,
        profile: bigProfile,
        units: <UnitBudget>[budget],
        cards: allocateCards(<UnitBudget>[budget]),
        batches: <AllocationBatch>[batch],
      );
      expect(plan.plannedCards, 2);
      expect(plan.shortfall, 0);
      expect(plan.distinctStatements, 1);
      expect(plan.angledCards, 1);
      expect(plan.toString(), contains('2 карт.'));
      expect(
        () => AllocationPlan(
          requested: 0,
          profile: bigProfile,
          units: const <UnitBudget>[],
          cards: const <AllocatedCard>[],
          batches: const <AllocationBatch>[],
        ),
        throwsAssertionError,
      );
      expect(
        () => AllocationPlan(
          requested: 5,
          profile: bigProfile,
          units: <UnitBudget>[budget],
          cards: allocateCards(<UnitBudget>[budget]),
          batches: <AllocationBatch>[batch],
        ),
        throwsAssertionError,
        reason: '2 карточки на заказ 5 — недопустимый план (сумма ≠ заказ)',
      );
    });
  });

  group('DoD: property-тесты плана', () {
    test('сумма == цель, минимум 1, детерминизм, профиль соблюдён', () {
      final math.Random random = math.Random(20261127);
      const List<KnowledgeUnitKind> kinds = KnowledgeUnitKind.values;
      const List<String> statements = <String>[
        'Фотосинтез превращает свет в химическую энергию',
        'PV = nRT',
        'и в на с',
        'Закон сохранения энергии',
        'Для расчёта используем формулу',
      ];
      for (var iteration = 0; iteration < 200; iteration++) {
        final int unitCount = random.nextInt(12);
        final int target = 1 + random.nextInt(150);
        final List<KnowledgeUnit> units = <KnowledgeUnit>[
          for (var index = 0; index < unitCount; index++)
            unit(
              id: 'ku:$iteration:$index',
              kind: kinds[random.nextInt(kinds.length)],
              salience: 0.05 + random.nextDouble() * 0.95,
              statement: statements[random.nextInt(statements.length)],
            ),
        ];
        final KnowledgeMap map = mapOf(units);
        final AllocationPlan plan = planAllocation(
          map: map,
          requestedCards: target,
          profile: bigProfile,
        );
        final AllocationPlan again = planAllocation(
          map: map,
          requestedCards: target,
          profile: bigProfile,
        );

        if (unitCount == 0) {
          expect(plan.materialLimited, isTrue);
          expect(plan.plannedCards, 0);
          expect(plan.shortfall, target);
          expect(plan.batches, isEmpty);
          continue;
        }
        expect(
          plan.plannedCards,
          target,
          reason: 'Сумма карточек равна заказу (итерация $iteration)',
        );
        expect(plan.shortfall, 0);
        expect(plan.materialLimited, isFalse);
        expect(
          plan.units.fold<int>(0, (int sum, UnitBudget b) => sum + b.cards),
          target,
        );
        expect(
          plan.units,
          hasLength(math.min(unitCount, target)),
          reason: 'Отобрано ровно столько единиц, сколько покрывает заказ',
        );
        for (final UnitBudget budget in plan.units) {
          expect(
            budget.cards,
            greaterThanOrEqualTo(1),
            reason: 'Минимум 1 карточка на отобранную единицу',
          );
          expect(
            plan.cards.where(
              (AllocatedCard card) =>
                  card.unitId == budget.unit.id && card.isPrimary,
            ),
            hasLength(1),
          );
        }
        expect(
          plan.cards.where((AllocatedCard card) => card.isPrimary),
          hasLength(plan.units.length),
          reason: 'Основная карточка — ровно одна на единицу',
        );
        for (final AllocationBatch batch in plan.batches) {
          expect(
            batch.fitsProfile,
            isTrue,
            reason: 'Батч не превышает профиль (итерация $iteration)',
          );
          expect(
            batch.totalTokens,
            lessThanOrEqualTo(batch.profile.batchTokenBudget),
          );
          expect(
            batch.outputTokens,
            lessThanOrEqualTo(batch.profile.maxOutputTokens),
          );
        }
        expect(
          <Object>[
            for (final AllocationBatch batch in plan.batches)
              <Object>[
                listOfCards(batch.cards),
                batch.inputTokens,
                batch.outputTokens,
              ],
          ],
          <Object>[
            for (final AllocationBatch batch in again.batches)
              <Object>[
                listOfCards(batch.cards),
                batch.inputTokens,
                batch.outputTokens,
              ],
          ],
          reason: 'Один вход — один план (итерация $iteration)',
        );
        expect(listOfCards(plan.cards), listOfCards(again.cards));
      }
    });

    test('полный план: бюджет единиц == заказ, добор углами', () {
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        for (var i = 0; i < 12; i++)
          unit(
            id: 'ku:$i',
            kind: KnowledgeUnitKind.values[i % KnowledgeUnitKind.values.length],
            salience: 0.3 + (i % 7) / 10,
            statement: 'Утверждение материала номер $i',
          ),
      ];
      final AllocationPlan plan = planAllocation(
        map: mapOf(units),
        requestedCards: 40,
        profile: bigProfile,
      );
      expect(plan.requested, 40);
      expect(plan.plannedCards, 40);
      expect(
        plan.units.fold<int>(0, (int sum, UnitBudget b) => sum + b.cards),
        40,
        reason: 'Σ бюджетов == заказ (инвариант ARCH.md §3)',
      );
      expect(plan.distinctStatements, 12);
      expect(plan.unitsBelowRequested, isTrue);
      expect(plan.angledCards, 28);
      expect(
        plan.cards.where((AllocatedCard card) => card.isPrimary),
        hasLength(12),
      );
      expect(plan.batches, isNotEmpty);
      expect(listOfBatches(plan.batches), isNotEmpty);
    });
  });
}

/// Пары «единица → угол» в порядке плана (для читаемых ожиданий).
List<String?> _angles(List<AllocatedCard> cards) => <String?>[
  for (final AllocatedCard card in cards) ...<String?>[
    card.unitId,
    card.angle?.wireName,
  ],
];
