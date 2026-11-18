import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// TASK 02B-FINAL: второй проход D.5 — укрупнение совместимых фрагментов,
/// когда заказ карточек меньше числа фрагментов.
void main() {
  final GenerationPlanBuilder builder = GenerationPlanBuilder();

  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 1000,
    schemaTokens: 200,
    wrapperTokens: 100,
  );

  String words(int count) => List<String>.filled(count, 'слово').join(' ');

  ParsedDocument docOf(
    String fileName,
    List<String> sections, {
    List<DocumentImage> images = const <DocumentImage>[],
  }) {
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> parsed = <ParsedSection>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      buffer.write(sections[index]);
      parsed.add(ParsedSection(start: start, end: buffer.length));
    }
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: fileName,
      text: buffer.toString(),
      sections: parsed,
      images: images,
    );
  }

  DocumentImage imageOf({
    String fileName = 'doc.txt',
    int index = 0,
    int sectionIndex = 0,
    int bytes = 3000,
  }) {
    return DocumentImage(
      fileName: fileName,
      bytes: Uint8List.fromList(
        List<int>.generate(bytes, (int i) => (index + i) % 251),
      ),
      mediaType: AttachmentMediaType.png,
      sectionIndex: sectionIndex,
      page: sectionIndex + 1,
      order: index,
      caption: 'Рис. ${index + 1}',
      context: 'Контекст рисунка ${index + 1}',
    );
  }

  ModelCapabilities caps({
    int? context = 128000,
    int? maxOutput = 50000,
    int? maxCards,
    int? maxImages,
    int? maxRequestBytes,
    bool vision = false,
  }) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: context == null
          ? CapabilitySource.unknown
          : CapabilitySource.preset,
      maxOutputTokens: maxOutput,
      maxCardsPerRequest: maxCards,
      maxImagesPerRequest: maxImages,
      maxRequestBytes: maxRequestBytes,
      supportsVision: vision,
    );
  }

  GenerationPlan makePlan({
    required List<ParsedDocument> documents,
    required ModelCapabilities capabilities,
    int? requestedCards,
    GenerationChunkPlannerConfig config = const GenerationChunkPlannerConfig(),
  }) {
    return GenerationPlanBuilder(
      planner: GenerationChunkPlanner(config: config),
    ).build(
      documents: documents,
      capabilities: capabilities,
      requestedCards: requestedCards,
      overhead: overhead,
    );
  }

  void expectCoverage(GenerationPlan plan, List<ParsedDocument> documents) {
    final ContentInventory inventory = builder.inventoryOf(
      documents: documents,
    );
    final GenerationPlanCoverage coverage = GenerationPlanCoverage.check(
      inventory: inventory,
      plan: plan,
    );
    expect(coverage.isComplete, isTrue, reason: '$coverage');
  }

  List<String> rootsOf(GenerationPlan plan) => <String>[
    for (final PlannedChunk chunk in plan.chunks)
      for (final UnitSpan span in chunk.units) span.unitId.split('~').first,
  ];

  test('5 карточек и 12 исходных фрагментов → 5 фрагментов, 5 карточек', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf('lecture.txt', <String>[
        for (var index = 0; index < 24; index++) 'Раздел $index. ${words(450)}',
      ]),
    ];
    const GenerationChunkPlannerConfig config = GenerationChunkPlannerConfig(
      softTargetMaterialTokensPerCard: 400,
    );
    final ModelCapabilities capabilities = caps(maxCards: 5);
    final GenerationPlan baseline = makePlan(
      documents: documents,
      capabilities: capabilities,
      config: config,
    );
    expect(baseline.chunks.length, 12, reason: 'исходное разбиение');
    expect(baseline.validity.isInvalid, isFalse);

    final GenerationPlan merged = makePlan(
      documents: documents,
      capabilities: capabilities,
      requestedCards: 5,
      config: config,
    );
    expect(merged.chunks, hasLength(5));
    expect(merged.requestedCards, 5);
    expect(merged.plannedCards, 5);
    expect(merged.achievableCards, 5);
    expect(
      merged.chunks.map((PlannedChunk chunk) => chunk.limit),
      everyElement(1),
    );
    expect(
      merged.validity.warnings,
      isNot(contains(PlanWarningCode.cardsAboveRequested)),
    );
    expectCoverage(merged, documents);
    expect(
      rootsOf(merged),
      rootsOf(baseline),
      reason: 'порядок единиц сохранён',
    );
    for (final PlannedChunk chunk in merged.chunks) {
      expect(chunk.units, isNotEmpty);
      expect(chunk.materialsText, isNotEmpty);
    }
  });

  test('10 карточек и 25 исходных фрагментов → 10 фрагментов', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf('big.txt', <String>[
        for (var index = 0; index < 25; index++) 'Раздел $index. ${words(900)}',
      ]),
    ];
    const GenerationChunkPlannerConfig config = GenerationChunkPlannerConfig(
      softTargetMaterialTokensPerCard: 400,
    );
    final ModelCapabilities capabilities = caps(maxCards: 10);
    final GenerationPlan baseline = makePlan(
      documents: documents,
      capabilities: capabilities,
      config: config,
    );
    expect(baseline.chunks.length, greaterThan(10));
    final GenerationPlan merged = makePlan(
      documents: documents,
      capabilities: capabilities,
      requestedCards: 10,
      config: config,
    );
    expect(merged.chunks.length, lessThanOrEqualTo(10));
    expect(merged.plannedCards, 10);
    expect(merged.achievableCards, 10);
    expectCoverage(merged, documents);
  });

  test('1 карточка на несколько фрагментов → один запрос', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf('one.txt', <String>[
        for (var index = 0; index < 6; index++) 'Раздел $index. ${words(450)}',
      ]),
    ];
    const GenerationChunkPlannerConfig config = GenerationChunkPlannerConfig(
      softTargetMaterialTokensPerCard: 400,
    );
    final ModelCapabilities capabilities = caps(maxCards: 5);
    final GenerationPlan merged = makePlan(
      documents: documents,
      capabilities: capabilities,
      requestedCards: 1,
      config: config,
    );
    expect(merged.chunks, hasLength(1));
    expect(merged.chunks.single.limit, 1);
    expect(merged.plannedCards, 1);
    expectCoverage(merged, documents);
  });

  test('50 карточек и 10 фрагментов: слияния нет, заказ распределён', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf('many.txt', <String>[
        for (var index = 0; index < 10; index++)
          'Раздел $index. ${words(2100)}',
      ]),
    ];
    const GenerationChunkPlannerConfig config = GenerationChunkPlannerConfig(
      softTargetMaterialTokensPerCard: 700,
    );
    final ModelCapabilities capabilities = caps(maxCards: 7);
    final GenerationPlan plan = makePlan(
      documents: documents,
      capabilities: capabilities,
      requestedCards: 50,
      config: config,
    );
    expect(plan.chunks, hasLength(10));
    expect(plan.plannedCards, 50);
    expect(plan.requestedCards, 50);
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.limit, inInclusiveRange(1, 7));
    }
    expectCoverage(plan, documents);
  });

  test(
    'укрупнение невозможно из-за input budget: предупреждение, без потерь',
    () {
      final List<ParsedDocument> documents = <ParsedDocument>[
        docOf('dense.txt', <String>[
          for (var index = 0; index < 3; index++)
            'Раздел $index. ${words(3000)}',
        ]),
      ];
      final ModelCapabilities capabilities = caps(
        context: 16000,
        maxOutput: 8000,
        maxCards: 1,
      );
      final GenerationPlan plan = makePlan(
        documents: documents,
        capabilities: capabilities,
        requestedCards: 1,
      );
      expect(plan.chunks.length, greaterThan(1));
      expect(plan.requestedCards, 1, reason: 'заказ не подменяется');
      expect(plan.plannedCards, greaterThan(1));
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.cardsAboveRequested),
      );
      expectCoverage(plan, documents);
    },
  );

  test('укрупнение невозможно из-за лимита изображений модели', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf(
        'pictures.txt',
        <String>['Раздел 0. ${words(450)}', 'Раздел 1. ${words(450)}'],
        images: <DocumentImage>[
          imageOf(fileName: 'pictures.txt', index: 0, sectionIndex: 0),
          imageOf(fileName: 'pictures.txt', index: 1, sectionIndex: 1),
        ],
      ),
    ];
    const GenerationChunkPlannerConfig config = GenerationChunkPlannerConfig(
      softTargetMaterialTokensPerCard: 400,
    );
    final GenerationPlan plan = makePlan(
      documents: documents,
      capabilities: caps(vision: true, maxCards: 5, maxImages: 1),
      requestedCards: 1,
      config: config,
    );
    expect(plan.chunks.length, greaterThan(1));
    expect(plan.plannedCards, greaterThan(1));
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.cardsAboveRequested),
    );
    final List<String> partIds = <String>[
      for (final PlannedChunk chunk in plan.chunks) ...chunk.imagePartIds,
    ];
    expect(partIds.toSet(), hasLength(partIds.length), reason: 'без дублей');
    expect(partIds, hasLength(2), reason: 'оба изображения учтены');
    expectCoverage(plan, documents);
  });

  test('укрупнение невозможно из-за размера тела запроса', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf(
        'payload.txt',
        <String>['Раздел 0. ${words(200)}', 'Раздел 1. ${words(200)}'],
        images: <DocumentImage>[
          imageOf(fileName: 'payload.txt', index: 0, sectionIndex: 0),
          imageOf(fileName: 'payload.txt', index: 1, sectionIndex: 1),
        ],
      ),
    ];
    const GenerationChunkPlannerConfig config = GenerationChunkPlannerConfig(
      softTargetMaterialTokensPerCard: 400,
    );
    final GenerationPlan plan = makePlan(
      documents: documents,
      capabilities: caps(
        vision: true,
        maxCards: 5,
        maxImages: 4,
        maxRequestBytes: 8000,
      ),
      requestedCards: 1,
      config: config,
    );
    expect(plan.chunks.length, greaterThan(1));
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.bodyBytes, lessThanOrEqualTo(8000));
    }
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.cardsAboveRequested),
    );
    expectCoverage(plan, documents);
  });

  test('заказ 1/2/5/10/20/50/100: сумма не превышает заказ', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf('cards.txt', <String>['Короткий материал для карточек.']),
    ];
    final ModelCapabilities capabilities = caps(maxCards: 40);
    for (final int requested in <int>[1, 2, 5, 10, 20, 50, 100]) {
      final GenerationPlan plan = makePlan(
        documents: documents,
        capabilities: capabilities,
        requestedCards: requested,
      );
      expect(plan.requestedCards, requested);
      expect(
        plan.plannedCards,
        lessThanOrEqualTo(requested),
        reason: 'заказ $requested',
      );
      if (requested <= 40) {
        expect(plan.plannedCards, requested, reason: 'заказ $requested');
      }
    }
  });

  test('заказ выше возможностей модели: requestedAbovePlan видим', () {
    final List<ParsedDocument> documents = <ParsedDocument>[
      docOf('cards.txt', <String>['Короткий материал.']),
    ];
    final GenerationPlan plan = makePlan(
      documents: documents,
      capabilities: caps(maxOutput: 8192),
      requestedCards: 100,
    );
    expect(plan.requestedCards, 100);
    expect(plan.plannedCards, lessThan(100));
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.requestedAbovePlan),
    );
    expect(plan.requestedAboveAchievable, isTrue);
  });
}
