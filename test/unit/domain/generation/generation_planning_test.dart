import 'dart:typed_data';

import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/output_batch_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// §5.1 задания 7.18: бюджет и стратегия входа (T1–T9).
///
/// Конфигурация: tpc = 300, fill = 0.85, schemaOverhead = 200, m = 0.10,
/// minBatchCards = 5, ceiling = 40. Токены материалов — явно, без эстиматора.
void main() {
  const GenerationPlanningConfig config = GenerationPlanningConfig();
  const InputPlanner planner = InputPlanner();
  const OutputBatchPlanner batches = OutputBatchPlanner();

  ModelLimits limits({
    int? context,
    int? maxInput,
    int? maxOutput,
    ContextSemantics semantics = ContextSemantics.totalInputPlusOutput,
    int? maxRequestBytes,
    bool? supportsImage,
  }) => ModelLimits(
    contextTokens: context == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            context,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
    contextSemantics: semantics,
    maxInputTokens: maxInput == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            maxInput,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
    maxOutputTokens: maxOutput == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            maxOutput,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
    maxRequestBytes: maxRequestBytes == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            maxRequestBytes,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
    supportsImageInput: supportsImage == null
        ? const Sourced<bool>.absent()
        : Sourced<bool>(
            supportsImage,
            source: CapabilitySource.officialCatalog,
            sourceRef: 'test/catalog',
          ),
  );

  List<InputSection> sections({
    required int count,
    required int tokensEach,
    String prefix = 's',
  }) => <InputSection>[
    for (var index = 0; index < count; index++)
      InputSection(
        id: '$prefix$index',
        shortId: '$prefix$index',
        title: 'Раздел $index',
        tokens: tokensEach,
        text: 'Текст раздела $index.',
      ),
  ];

  int desired(int? requested, int maxOutput) => config.desiredOutputTokens(
    requestedCards: requested,
    maxOutputTokens: maxOutput,
  );

  CardAllocation allocationFor(List<InputSection> list, int requested) =>
      const CardAllocator().allocate(
        sections: <AllocationSection>[
          for (final InputSection section in list)
            AllocationSection(id: section.id, capacity: 100000),
        ],
        requestedCards: requested,
      );

  group('T1–T3: whole-document', () {
    test(
      'T1: total 128000/out 8192, D=40000, 10 карточек → whole, 47300, 3765',
      () {
        final InputPlan plan = planner.plan(
          sections: sections(count: 4, tokensEach: 10000),
          limits: limits(context: 128000, maxOutput: 8192),
          fixedTokens: 3000,
          desiredOutputTokens: desired(10, 8192),
        );
        expect(plan.strategy, InputStrategy.wholeDocument);
        expect(plan.partCount, 1);
        expect(
          plan.inputTokens,
          47300,
          reason: 'ceil((3000 + 40000) × 1.10) = 47300',
        );
        expect(plan.maxTokens, 3765, reason: 'tokensFor(10) = 3765');
      },
    );

    test(
      'T2: тот же бюджет, 50 карточек → whole, 8192, 22 в партии, 3 партии',
      () {
        final List<InputSection> material = sections(
          count: 4,
          tokensEach: 10000,
        );
        final InputPlan plan = planner.plan(
          sections: material,
          limits: limits(context: 128000, maxOutput: 8192),
          fixedTokens: 3000,
          desiredOutputTokens: desired(50, 8192),
        );
        expect(plan.strategy, InputStrategy.wholeDocument);
        expect(plan.inputTokens, 47300);
        expect(plan.maxTokens, 8192);
        final List<PlannedBatch> planned = batches.plan(
          input: plan,
          allocation: allocationFor(material, 50),
          maxTokensPerBatch: plan.maxTokens,
        );
        expect(planned.length, 3);
        // 7.20: партии заполняются до вместимости (cardsFor(8192) = 22),
        // остаток — последней; сбалансированные 17/17/16 больше не нужны.
        expect(planned.map((PlannedBatch b) => b.limit), <int>[22, 22, 6]);
        expect(
          batches.cardsPerBatch(plan.maxTokens),
          22,
          reason: 'cardsFor(8192) = 22',
        );
      },
    );

    test(
      'T3: inputOnly maxInput 500000/out 5530, 100 карточек → 15, 7 партий',
      () {
        final List<InputSection> material = sections(
          count: 10,
          tokensEach: 10000,
        );
        final InputPlan plan = planner.plan(
          sections: material,
          limits: limits(
            context: 500000,
            maxInput: 500000,
            maxOutput: 5530,
            semantics: ContextSemantics.inputOnly,
          ),
          fixedTokens: 3000,
          desiredOutputTokens: desired(100, 5530),
        );
        expect(plan.strategy, InputStrategy.wholeDocument);
        expect(plan.inputTokens, 113300, reason: 'ceil(103000 × 1.10)');
        expect(plan.maxTokens, 5530);
        final List<PlannedBatch> planned = batches.plan(
          input: plan,
          allocation: allocationFor(material, 100),
          maxTokensPerBatch: plan.maxTokens,
        );
        expect(planned.length, 7);
        // 7.20: заполнение до вместимости, остаток последней партии.
        expect(planned.map((PlannedBatch b) => b.limit), <int>[
          15,
          15,
          15,
          15,
          15,
          15,
          10,
        ]);
      },
    );
  });

  group('T4–T8: fragmented и ограничения', () {
    test('T4: D=300000 не помещается → 3 части, Dmax=104416', () {
      final InputPlan plan = planner.plan(
        sections: sections(count: 30, tokensEach: 10000),
        limits: limits(context: 128000, maxOutput: 8192),
        fixedTokens: 3000,
        desiredOutputTokens: desired(50, 8192),
        outlineReserveTokens: 1500,
      );
      expect(plan.strategy, InputStrategy.fragmented);
      expect(plan.partCount, 3);
      expect(
        plan.materialBudgetPerPart,
        104416,
        reason: 'floor((128000 − 8192)/1.1) − 4500 = 104416',
      );
    });

    test(
      'T5: токены помещаются, ограничение — requestBytes; картинки не теряются',
      () {
        final Uint8List big = Uint8List(13 * 1024 * 1024);
        final Uint8List other = Uint8List(13 * 1024 * 1024)..[0] = 1;
        final InputImage first = InputImage(
          id: 'img1',
          fileName: 'scheme1.png',
          bytes: big,
          tokens: 1600,
        );
        final InputImage second = InputImage(
          id: 'img2',
          fileName: 'scheme2.png',
          bytes: other,
          tokens: 1600,
        );
        final InputSection section = InputSection(
          id: 'doc:lecture.pdf#0',
          shortId: 's1',
          title: 'Схемы',
          tokens: 30000,
          text: 'Текст схем.',
          images: <InputImage>[first, second],
        );
        final InputPlan plan = planner.plan(
          sections: <InputSection>[section],
          limits: limits(
            context: 128000,
            maxOutput: 8192,
            maxRequestBytes: 20 * 1024 * 1024,
            supportsImage: true,
          ),
          fixedTokens: 3000,
          desiredOutputTokens: desired(20, 8192),
          accuracy: InputAccuracy.estimated,
        );
        expect(plan.strategy, InputStrategy.wholeDocument);
        expect(plan.partCount, 1);
        expect(
          plan.images.where((PlannedImage i) => i.sentToModel).length,
          1,
          reason: 'в 20 МБ после base64 помещается одна из двух картинок',
        );
        expect(
          plan.images
              .where(
                (PlannedImage i) =>
                    i.status == ImageParticipationStatus.omittedPayload,
              )
              .length,
          1,
          reason:
              'вторая картинка помечена omittedPayload, а не потеряна молча',
        );
        expect(plan.warnings, contains(PlanWarningCode.payloadLimited));
        expect(
          plan.parts.first.bytes,
          lessThanOrEqualTo(20 * 1024 * 1024),
          reason: 'тело части укладывается в лимит байтов',
        );
      },
    );

    test(
      'T6: неизвестное окно → допущение, contextUnconfirmed, честное дробление',
      () {
        final InputPlan plan = planner.plan(
          sections: sections(count: 20, tokensEach: 1000),
          limits: limits(),
          fixedTokens: 3000,
          desiredOutputTokens: desired(10, 2048),
        );
        expect(plan.contextTokens, isNull);
        expect(plan.strategy, InputStrategy.fragmented);
        expect(
          plan.partCount,
          4,
          reason: 'материал 20000 при бюджете 6000 → 4 части по 5000',
        );
        expect(plan.materialBudgetPerPart, 6000);
        expect(plan.warnings, contains(PlanWarningCode.contextUnconfirmed));
      },
    );

    test(
      'T7: total 64000/out 32000, D=50000 → резерв уменьшен до 5700, вход цел',
      () {
        final List<InputSection> material = sections(
          count: 50,
          tokensEach: 1000,
        );
        final InputPlan plan = planner.plan(
          sections: material,
          limits: limits(context: 64000, maxOutput: 32000),
          fixedTokens: 3000,
          desiredOutputTokens: desired(100, 32000),
        );
        expect(plan.strategy, InputStrategy.wholeDocument);
        expect(plan.inputTokens, 58300, reason: 'ceil(53000 × 1.1)');
        expect(plan.maxTokens, 5700, reason: 'room = 64000 − 58300');
        final List<PlannedBatch> planned = batches.plan(
          input: plan,
          allocation: allocationFor(material, 100),
          maxTokensPerBatch: plan.maxTokens,
        );
        expect(planned.length, 7);
        // 7.20: заполнение до вместимости, остаток последней партии.
        expect(planned.map((PlannedBatch b) => b.limit), <int>[
          15,
          15,
          15,
          15,
          15,
          15,
          10,
        ]);
      },
    );

    test(
      'T8: total 64000/out 32000, D=56000 → room < tokensFor(5) → fragmented',
      () {
        final InputPlan plan = planner.plan(
          sections: sections(count: 56, tokensEach: 1000),
          limits: limits(context: 64000, maxOutput: 32000),
          fixedTokens: 3000,
          desiredOutputTokens: desired(10, 32000),
        );
        expect(plan.strategy, InputStrategy.fragmented);
        expect(plan.partCount, 2);
        expect(
          plan.materialBudgetPerPart,
          42133,
          reason: 'floor((64000 − 14353)/1.1) − 3000',
        );
      },
    );
  });

  group('T9: границы', () {
    test('тотальная семантика: ±1 токен материала меняет стратегию', () {
      final InputPlan whole = planner.plan(
        sections: sections(count: 1, tokensEach: 53363),
        limits: limits(context: 64000, maxOutput: 32000),
        fixedTokens: 3000,
        desiredOutputTokens: desired(100, 32000),
      );
      expect(whole.inputTokens, 62000, reason: 'ceil(56363 × 1.1) = 62000');
      expect(whole.maxTokens, 2000, reason: 'room = 2000 = tokensFor(5)');
      expect(whole.strategy, InputStrategy.wholeDocument);

      final InputPlan fragmented = planner.plan(
        sections: sections(count: 1, tokensEach: 53364),
        limits: limits(context: 64000, maxOutput: 32000),
        fixedTokens: 3000,
        desiredOutputTokens: desired(100, 32000),
      );
      expect(
        fragmented.inputTokens,
        62001,
        reason: 'ceil(56364 × 1.1) = 62001',
      );
      expect(fragmented.strategy, InputStrategy.fragmented);
    });

    test('нативный подсчёт входа: точное значение меняет стратегию честно', () {
      final InputPlan whole = planner.plan(
        sections: sections(count: 1, tokensEach: 53364),
        limits: limits(context: 64000, maxOutput: 32000),
        fixedTokens: 3000,
        desiredOutputTokens: desired(100, 32000),
        nativeCount: const NativeInputCount(
          tokens: 60000,
          source: 'count_tokens:test',
        ),
      );
      expect(whole.accuracy, InputAccuracy.exact);
      expect(whole.inputTokens, 61800, reason: '60000 + 3 % запаса');
      expect(whole.maxTokens, 2200, reason: 'room = 64000 − 61800');
      expect(whole.strategy, InputStrategy.wholeDocument);

      final InputPlan fragmented = planner.plan(
        sections: sections(count: 1, tokensEach: 53364),
        limits: limits(context: 64000, maxOutput: 32000),
        fixedTokens: 3000,
        desiredOutputTokens: desired(100, 32000),
        nativeCount: const NativeInputCount(
          tokens: 62000,
          source: 'count_tokens:test',
        ),
      );
      expect(
        fragmented.strategy,
        InputStrategy.fragmented,
        reason: 'точный вход 63 860 оставляет 140 под ответ → дробим',
      );
      expect(fragmented.partCount, greaterThanOrEqualTo(1));
    });
    test('inputOnly: выход не вычитается из лимита входа повторно', () {
      final InputPlan whole = planner.plan(
        sections: sections(count: 10, tokensEach: 8750),
        limits: limits(
          context: 100000,
          maxInput: 100000,
          maxOutput: 5530,
          semantics: ContextSemantics.inputOnly,
        ),
        fixedTokens: 3000,
        desiredOutputTokens: desired(100, 5530),
      );
      expect(whole.inputTokens, 99550);
      expect(whole.strategy, InputStrategy.wholeDocument);

      final InputPlan fragmented = planner.plan(
        sections: sections(count: 10, tokensEach: 8800),
        limits: limits(
          context: 100000,
          maxInput: 100000,
          maxOutput: 5530,
          semantics: ContextSemantics.inputOnly,
        ),
        fixedTokens: 3000,
        desiredOutputTokens: desired(100, 5530),
      );
      expect(
        fragmented.inputTokens,
        51700,
        reason: 'после дробления вход части: ceil((3000 + 44000) × 1.1)',
      );
      expect(fragmented.strategy, InputStrategy.fragmented);
    });
  });
}
