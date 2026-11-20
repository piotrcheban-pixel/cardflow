import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/output_batch_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// §5.3 задания 7.18: независимость входа, распределения и партий.
void main() {
  const GenerationPlanningConfig config = GenerationPlanningConfig();
  const InputPlanner planner = InputPlanner();
  const OutputBatchPlanner batchPlanner = OutputBatchPlanner();
  const CardAllocator allocator = CardAllocator();

  ModelLimits limits({
    int? context,
    int? maxOutput,
    ContextSemantics semantics = ContextSemantics.totalInputPlusOutput,
  }) => ModelLimits(
    contextTokens: context == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            context,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
    contextSemantics: semantics,
    maxOutputTokens: maxOutput == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            maxOutput,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
  );

  List<InputSection> sections(int count, int tokensEach) => <InputSection>[
    for (var index = 0; index < count; index++)
      InputSection(
        id: 's$index',
        shortId: 's$index',
        title: 'Раздел $index',
        tokens: tokensEach,
        text: 'Текст раздела $index.',
      ),
  ];

  List<AllocationSection> allocationSections(List<InputSection> list) =>
      <AllocationSection>[
        for (final InputSection section in list)
          AllocationSection(id: section.id, capacity: 1000),
      ];

  String partsSignature(InputPlan plan) => plan.parts
      .map(
        (InputPart part) =>
            '${part.index}:${part.sections.map((InputSection s) => s.id).join('+')}:${part.tokens}',
      )
      .join('|');

  group('§5.3.1 вход не зависит от заказа (T4)', () {
    test(
      'заказ 10/50/100 → одинаковые части, разные распределение и партии',
      () {
        final List<InputSection> material = sections(30, 10000);
        final ModelLimits model = limits(context: 128000, maxOutput: 8192);
        final List<InputPlan> plans = <int>[10, 50, 100]
            .map(
              (int requested) => planner.plan(
                sections: material,
                limits: model,
                fixedTokens: 3000,
                desiredOutputTokens: config.desiredOutputTokens(
                  requestedCards: requested,
                  maxOutputTokens: 8192,
                ),
                outlineReserveTokens: 1500,
              ),
            )
            .toList();
        for (final InputPlan plan in plans) {
          expect(plan.strategy, InputStrategy.fragmented);
          expect(plan.partCount, 3);
          expect(
            plan.inputTokens,
            114950,
            reason: 'бюджет части одинаков: ceil((4500 + 100000) × 1.1)',
          );
        }
        expect(
          partsSignature(plans[0]),
          partsSignature(plans[1]),
          reason: 'границы частей не зависят от заказа',
        );
        expect(partsSignature(plans[1]), partsSignature(plans[2]));

        final CardAllocation ten = allocator.allocate(
          sections: allocationSections(material),
          requestedCards: 10,
        );
        final CardAllocation fifty = allocator.allocate(
          sections: allocationSections(material),
          requestedCards: 50,
        );
        expect(ten.achievable, 10);
        expect(fifty.achievable, 50);
        expect(ten.planned, isNot(fifty.planned));

        final List<PlannedBatch> one = batchPlanner.plan(
          input: plans[0],
          allocation: ten,
          maxTokensPerBatch: plans[0].maxTokens,
        );
        final List<PlannedBatch> three = batchPlanner.plan(
          input: plans[1],
          allocation: fifty,
          maxTokensPerBatch: plans[1].maxTokens,
        );
        expect(one.length, lessThan(three.length));
        expect(one.map((PlannedBatch b) => b.limit).toList(), <int>[10]);
        // В fragmented-режиме партии строятся внутри частей: распределение 50
        // карточек по 30 равным разделам даёт 20/20/10 на три части.
        expect(three.map((PlannedBatch b) => b.limit).toList(), <int>[
          20,
          20,
          10,
        ]);
        expect(
          plans[0].budget.contextTokens,
          plans[2].budget.contextTokens,
          reason: 'лимиты модели от заказа не зависят',
        );
      },
    );
  });

  group('§5.3.2 вход цел, ответ меняется', () {
    test('ответ вмещает 10 → 1 источник и 1 партия', () {
      final List<InputSection> material = sections(4, 10000);
      final InputPlan plan = planner.plan(
        sections: material,
        limits: limits(context: 128000, maxOutput: 4000),
        fixedTokens: 3000,
        desiredOutputTokens: config.desiredOutputTokens(
          requestedCards: 10,
          maxOutputTokens: 4000,
        ),
      );
      expect(plan.strategy, InputStrategy.wholeDocument);
      expect(plan.partCount, 1);
      final CardAllocation allocation = allocator.allocate(
        sections: allocationSections(material),
        requestedCards: 10,
      );
      final List<PlannedBatch> batches = batchPlanner.plan(
        input: plan,
        allocation: allocation,
        maxTokensPerBatch: plan.maxTokens,
      );
      expect(batches, hasLength(1));
      expect(batches.single.limit, 10);
      expect(batches.single.partCount, 1);
    });

    test(
      'ответ вмещает 5, заказ 20 → 1 источник, 4 партии, входа не делим',
      () {
        final List<InputSection> material = sections(4, 10000);
        final InputPlan plan = planner.plan(
          sections: material,
          limits: limits(context: 128000, maxOutput: 2000),
          fixedTokens: 3000,
          desiredOutputTokens: config.desiredOutputTokens(
            requestedCards: 20,
            maxOutputTokens: 2000,
          ),
        );
        expect(plan.strategy, InputStrategy.wholeDocument);
        expect(plan.partCount, 1);
        final CardAllocation allocation = allocator.allocate(
          sections: allocationSections(material),
          requestedCards: 20,
        );
        expect(allocation.achievable, 20);
        final List<PlannedBatch> batches = batchPlanner.plan(
          input: plan,
          allocation: allocation,
          maxTokensPerBatch: plan.maxTokens,
        );
        expect(batches, hasLength(4));
        expect(batches.map((PlannedBatch b) => b.limit).toList(), <int>[
          5,
          5,
          5,
          5,
        ]);
        expect(
          batches.every((PlannedBatch b) => b.partCount == 1),
          isTrue,
          reason: 'вход не дробится из-за размера ответа',
        );
      },
    );
  });

  group('§5.3.3 промпт-онли и партии', () {
    test('prompt-only: партии по бюджету вывода, вход не дробится', () {
      final InputPlan plan = planner.plan(
        sections: const <InputSection>[],
        limits: limits(context: 128000, maxOutput: 4000),
        fixedTokens: 3000,
        desiredOutputTokens: config.desiredOutputTokens(
          requestedCards: 20,
          maxOutputTokens: 4000,
        ),
      );
      expect(plan.strategy, InputStrategy.promptOnly);
      expect(plan.parts, isEmpty);
      final List<PlannedBatch> batches = batchPlanner.plan(
        input: plan,
        allocation: allocator.allocate(
          sections: const <AllocationSection>[],
          requestedCards: 20,
        ),
        maxTokensPerBatch: plan.maxTokens,
        promptOnlyRequestedCards: 20,
      );
      expect(batches, hasLength(2), reason: '20 карточек при 10 на ответ');
      expect(batches.map((PlannedBatch b) => b.limit).toList(), <int>[10, 10]);
    });
  });
}
