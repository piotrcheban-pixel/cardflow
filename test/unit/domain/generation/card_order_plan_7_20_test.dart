import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Итерация 7.20: заказ карточек не ограничен бюджетом одного ответа.
///
/// До 7.20 `CardAllocator` зажимал сумму заказа мягкой ёмкостью материала
/// (`min(requested, Σ capacity)`), а UI объяснял это бюджетом модели. Здесь
/// проверяется контракт: сумма партий = заказ, каждая партия ≤ вместимости
/// ответа, а нехватка материала — **отдельный** статус.
void main() {
  /// Оценщик 6 символов на токен: объём входа задаётся текстом, а не сетью.
  const ContentTokenEstimator estimator = _SizedEstimator();

  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 2000,
    schemaTokens: 300,
    wrapperTokens: 100,
  );

  /// Один «плотный» блок: определения, формулы, числа и латиница — так мягкая
  /// ёмкость (эвристика ADR-040 §5) растёт предсказуемо, без мегабайт текста.
  const String block =
      r'1. Определение phi — это $a=1$, alpha-beta. 2. Термин называется delta, '
      r'понимается как gamma. 3. Величина является omega, представляет собой '
      r'отношение. - sigma $b=2$ 12, 34, 56, 78. ';

  String sectionText() => '$block$block';

  ParsedDocument documentOf(int sections) {
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> parsed = <ParsedSection>[];
    for (var index = 0; index < sections; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      buffer.write(sectionText());
      parsed.add(ParsedSection(start: start, end: buffer.length));
    }
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'материал.txt',
      text: buffer.toString(),
      sections: parsed,
    );
  }

  /// Один раздел даёт ёмкость 2 карточки; материал — `cards` карточек ёмкости.
  int capacityPerSection() =>
      SectionFeatures.of(title: '', text: sectionText()).capacity;

  ({ParsedDocument document, int capacity}) materialFor(int cards) {
    final int perSection = capacityPerSection();
    expect(perSection, greaterThanOrEqualTo(1));
    final int sections = (cards / perSection).ceil();
    final ParsedDocument document = documentOf(sections);
    // Ёмкость сверяется той же эвристикой, что и в плане: фикстура обязана
    // быть достаточной, иначе тест проверял бы не то.
    final int capacity = sections * perSection;
    return (document: document, capacity: capacity);
  }

  ModelCapabilities capabilitiesOf({
    int context = 1000000,
    int? maxOutput = 8192,
    bool reasoning = false,
  }) => ModelCapabilities(
    contextWindowTokens: context,
    contextSource: CapabilitySource.officialCatalog,
    maxOutputTokens: maxOutput,
    isReasoningModel: reasoning,
    supportsVision: false,
  );

  GenerationPlan planFor({
    required ParsedDocument document,
    required int? requestedCards,
    int context = 1000000,
    int? maxOutput = 8192,
    bool reasoning = false,
    GenerationPlanningConfig planning = const GenerationPlanningConfig(),
  }) =>
      GenerationPlanBuilder(
        planner: GenerationChunkPlanner(
          estimator: estimator,
          config: GenerationChunkPlannerConfig(planning: planning),
        ),
      ).build(
        documents: <ParsedDocument>[document],
        capabilities: capabilitiesOf(
          context: context,
          maxOutput: maxOutput,
          reasoning: reasoning,
        ),
        overhead: overhead,
        requestedCards: requestedCards,
      );

  List<int> sizesOf(GenerationPlan plan) =>
      plan.chunks.map((PlannedChunk chunk) => chunk.limit).toList();

  group('§3 задания: заказ сохраняется, партии считаются по вместимости', () {
    test(
      'заказ 40 при вместимости 16 → 3 последовательные партии (16,16,8)',
      () {
        final ({ParsedDocument document, int capacity}) material = materialFor(
          40,
        );
        final GenerationPlan plan = planFor(
          document: material.document,
          requestedCards: 40,
          maxOutput: 6000,
        );
        expect(plan.inputStrategy, InputStrategy.wholeDocument);
        expect(plan.requestedCards, 40);
        expect(sizesOf(plan), <int>[
          16,
          16,
          8,
        ], reason: 'партии заполняются до вместимости, остаток — последней');
        expect(plan.plannedCards, 40, reason: 'заказ не обрезан вместимостью');
        expect(plan.achievableCards, 40);
        expect(plan.materialLimited, isFalse);
        expect(
          plan.validity.warnings,
          isNot(contains(PlanWarningCode.requestedAbovePlan)),
          reason: 'вместимость одного ответа компенсируется партиями',
        );
        expect(
          plan.validity.warnings,
          isNot(contains(PlanWarningCode.materialCapacityBelowRequested)),
        );
      },
    );

    test('заказ 100 при вместимости 12 → 9 партий (12×8 + 4)', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        100,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 100,
        maxOutput: 4600,
      );
      expect(sizesOf(plan), <int>[12, 12, 12, 12, 12, 12, 12, 12, 4]);
      expect(plan.chunks, hasLength(9));
      expect(plan.plannedCards, 100);
      expect(
        plan.chunks.every((PlannedChunk chunk) => chunk.limit <= 12),
        isTrue,
      );
    });

    test('заказ 200 при вместимости 20 → 10 партий', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        200,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 200,
        maxOutput: 7400,
      );
      expect(plan.chunks, hasLength(10));
      expect(plan.plannedCards, 200);
      expect(
        plan.chunks.every((PlannedChunk chunk) => chunk.limit == 20),
        isTrue,
      );
    });

    test('заказ 1, 5, 10, 20 при вместимости 16 → ровно один запрос', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        20,
      );
      for (final int requested in <int>[1, 5, 10, 16]) {
        final GenerationPlan plan = planFor(
          document: material.document,
          requestedCards: requested,
          maxOutput: 6000,
        );
        expect(plan.chunks, hasLength(1), reason: 'заказ $requested');
        expect(plan.chunks.single.limit, requested);
      }
    });

    test('заказ 17 при вместимости 16 → 2 запроса', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        17,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 17,
        maxOutput: 6000,
      );
      expect(sizesOf(plan), <int>[16, 1]);
      expect(plan.plannedCards, 17);
    });
  });

  group('§2 задания: три механизма независимы', () {
    test('maxOutputTokens меняет число партий, но не общий заказ', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        40,
      );
      final List<GenerationPlan> plans = <int>[2500, 4600, 6000, 7400, 12000]
          .map(
            (int maxOutput) => planFor(
              document: material.document,
              requestedCards: 40,
              maxOutput: maxOutput,
            ),
          )
          .toList();
      expect(
        plans.map((GenerationPlan plan) => plan.plannedCards).toSet(),
        <int>{40},
        reason: 'бюджет одного ответа не ограничивает сумму',
      );
      expect(
        plans.map((GenerationPlan plan) => plan.chunks.length).toSet().length,
        greaterThan(1),
        reason: 'бюджет ответа меняет только число партий',
      );
      for (int index = 0; index < plans.length; index++) {
        final GenerationPlanningConfig config =
            const GenerationPlanningConfig();
        final int perBatch = config.cardsFor(plans[index].outputReserveTokens!);
        final int cap = perBatch < config.batchCardsCeiling
            ? perBatch
            : config.batchCardsCeiling;
        for (final PlannedChunk chunk in plans[index].chunks) {
          expect(chunk.limit, lessThanOrEqualTo(cap));
        }
      }
    });

    test('resoniningReserveTokens меняет число партий, но не заказ', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        40,
      );
      final GenerationPlan plain = planFor(
        document: material.document,
        requestedCards: 40,
      );
      final GenerationPlan reasoning = planFor(
        document: material.document,
        requestedCards: 40,
        reasoning: true,
      );
      expect(plain.plannedCards, 40);
      expect(reasoning.plannedCards, 40);
      expect(reasoning.reasoningReserveTokens, greaterThan(0));
      expect(
        plain.chunks.length,
        lessThan(reasoning.chunks.length),
        reason: 'резерв рассуждения уменьшает партию, а не заказ',
      );
      expect(
        reasoning.chunks.every((PlannedChunk chunk) => chunk.limit <= 16),
        isTrue,
      );
    });

    test('batchCardsCeiling меняет число партий, но не обрезает заказ', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        100,
      );
      final GenerationPlan narrow = planFor(
        document: material.document,
        requestedCards: 100,
        maxOutput: 12000,
        planning: const GenerationPlanningConfig(batchCardsCeiling: 10),
      );
      final GenerationPlan wide = planFor(
        document: material.document,
        requestedCards: 100,
        maxOutput: 12000,
      );
      expect(wide.plannedCards, 100);
      expect(narrow.plannedCards, 100);
      expect(narrow.chunks.length, greaterThan(wide.chunks.length));
      expect(
        narrow.chunks.every((PlannedChunk chunk) => chunk.limit <= 10),
        isTrue,
      );
    });

    test('requestedCards меняет партии, но не план входа', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        100,
      );
      final List<GenerationPlan> plans = <int>[10, 40, 100]
          .map(
            (int requested) => planFor(
              document: material.document,
              requestedCards: requested,
              maxOutput: 6000,
            ),
          )
          .toList();
      String partsSignature(GenerationPlan plan) => plan.parts
          .map(
            (InputPart part) =>
                '${part.index}:${part.sections.map((InputSection s) => s.id).join('+')}',
          )
          .join('|');
      expect(partsSignature(plans[0]), partsSignature(plans[2]));
      expect(
        plans.map((GenerationPlan plan) => plan.plannedCards).toList(),
        <int>[10, 40, 100],
      );
      expect(plans[0].chunks.length, 1);
      expect(plans[1].chunks.length, 3);
      expect(plans[2].chunks.length, 7);
    });
  });

  group('нехватка материала — отдельный статус, не бюджет модели', () {
    test('заказ больше ёмкости: сумма = заказ, статус про материал', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        30,
      );
      final int requested = material.capacity + 8;
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: requested,
        maxOutput: 6000,
      );
      expect(plan.requestedCards, requested);
      expect(plan.plannedCards, requested, reason: 'тихой обрезки нет');
      expect(plan.materialCapacity, material.capacity);
      expect(plan.materialLimited, isTrue);
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.materialCapacityBelowRequested),
      );
      expect(
        plan.validity.warnings,
        isNot(contains(PlanWarningCode.requestedAbovePlan)),
        reason: 'бюджет одного ответа здесь не при чём',
      );
    });

    test('бюджет одного ответа не влияет на achievable', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        40,
      );
      for (final int maxOutput in <int>[2000, 8192, 64000]) {
        final GenerationPlan plan = planFor(
          document: material.document,
          requestedCards: 40,
          maxOutput: maxOutput,
        );
        expect(plan.achievableCards, 40, reason: 'maxOutput=$maxOutput');
        expect(plan.materialLimited, isFalse);
      }
    });

    test(
      'материала нет вовсе (только служебные заголовки) → belowRequested',
      () {
        final ParsedDocument document = ParsedDocument(
          format: DocumentFormat.txt,
          fileName: 'служебное.txt',
          text: 'Содержание\n\nСписок литературы',
          sections: const <ParsedSection>[
            ParsedSection(start: 0, end: 10, title: 'Содержание'),
            ParsedSection(start: 12, end: 29, title: 'Список литературы'),
          ],
        );
        final GenerationPlan plan = planFor(
          document: document,
          requestedCards: 10,
        );
        expect(plan.plannedCards, 0);
        expect(
          plan.validity.warnings,
          contains(PlanWarningCode.requestedAbovePlan),
        );
      },
    );
  });

  group('wholeDocument и fragmented обслуживают несколько партий', () {
    test(
      'whole: все партии используют полный материал и различаются focus',
      () {
        final ({ParsedDocument document, int capacity}) material = materialFor(
          40,
        );
        final GenerationPlan plan = planFor(
          document: material.document,
          requestedCards: 40,
          maxOutput: 6000,
        );
        expect(plan.inputStrategy, InputStrategy.wholeDocument);
        expect(plan.parts, hasLength(1));
        expect(plan.chunks, hasLength(3));
        for (final PlannedChunk chunk in plan.chunks) {
          expect(chunk.materialsText, plan.parts.single.materialsText);
          expect(chunk.focusSectionIds, isNotEmpty);
          expect(chunk.partIndex, 0);
          expect(chunk.partCount, 1);
        }
      },
    );

    test('fragmented: партии внутри частей, сумма = заказ', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        100,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 100,
        context: 5500,
        maxOutput: 2000,
      );
      expect(plan.inputStrategy, InputStrategy.fragmented);
      expect(plan.parts.length, greaterThan(1));
      expect(plan.plannedCards, 100);
      final Set<int> partsWithBatches = <int>{
        for (final PlannedChunk chunk in plan.chunks) chunk.partIndex,
      };
      expect(
        partsWithBatches.length,
        plan.parts.length,
        reason: 'каждая часть обслуживается хотя бы одной партией',
      );
      for (final PlannedChunk chunk in plan.chunks) {
        expect(
          chunk.limit,
          lessThanOrEqualTo(5),
          reason: 'cardsFor(2000) = 5 — вместимость одного ответа',
        );
      }
      expect(
        plan.chunks.fold<int>(0, (int sum, PlannedChunk c) => sum + c.limit),
        100,
      );
    });

    test('число партий не выводится из числа частей', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        100,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 100,
        context: 5500,
        maxOutput: 2000,
      );
      expect(plan.inputStrategy, InputStrategy.fragmented);
      expect(
        plan.chunks.length,
        greaterThan(plan.parts.length),
        reason: 'партии считаются по бюджету ответа, а не по частям входа',
      );
    });
  });

  group('технические границы', () {
    test('максимально допустимый заказ: 512 партий по 10 → 5120 карточек', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        40,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 5120,
        maxOutput: 12000,
        planning: const GenerationPlanningConfig(batchCardsCeiling: 10),
      );
      expect(plan.chunks, hasLength(512));
      expect(plan.plannedCards, 5120);
      expect(plan.validity.isInvalid, isFalse);
    });

    test('заказ выше технического предела → invalid tooManyChunks', () {
      final ({ParsedDocument document, int capacity}) material = materialFor(
        40,
      );
      final GenerationPlan plan = planFor(
        document: material.document,
        requestedCards: 5121,
        maxOutput: 12000,
        planning: const GenerationPlanningConfig(batchCardsCeiling: 10),
      );
      expect(plan.validity.isInvalid, isTrue);
      expect(plan.validity.reason, PlanInvalidReason.tooManyChunks);
      expect(plan.chunks, isEmpty);
      expect(
        plan.requestedCards,
        5121,
        reason: 'заказ не подменяется даже в невыполнимом плане',
      );
    });

    test(
      'int.max заказ в материалах: invalid tooManyChunks, без зависания',
      () {
        final ({ParsedDocument document, int capacity}) material = materialFor(
          40,
        );
        final GenerationPlan plan = planFor(
          document: material.document,
          requestedCards: kMaxIntRequest,
        );
        expect(plan.validity.isInvalid, isTrue);
        expect(plan.validity.reason, PlanInvalidReason.tooManyChunks);
        expect(plan.chunks, isEmpty);
      },
    );
  });
}

/// Технический предел представления заказа (`int.max`).
const int kMaxIntRequest = 9223372036854775807;

/// Оценщик «6 символов = 1 токен»: объём входа задаётся текстом фикстуры.
class _SizedEstimator implements ContentTokenEstimator {
  const _SizedEstimator();

  @override
  String get version => 'test_sized/1';

  @override
  double get charsPerToken => 6;

  @override
  int estimateText(String text) => (text.runes.length / 6).ceil() + 1;

  @override
  ImageTokenEstimate estimateImage({
    int? width,
    int? height,
    required int bytes,
    ImageTokenModel? model,
  }) => const ImageTokenEstimate(
    tokens: 100,
    source: ImageTokenSource.byteHeuristic,
    isAssumption: true,
  );
}
