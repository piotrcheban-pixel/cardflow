import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// TASK 02B: адаптивный планировщик фрагментов (разделы D.4–D.7).
///
/// Сценарии 1–30 задания проверяются через production-путь сборки плана
/// (`GenerationPlanBuilder`): документы → единицы содержимого → бюджет →
/// упаковка → покрытие. Плюс прямой вызов планировщика для бюджетных случаев.
void main() {
  final GenerationPlanBuilder builder = GenerationPlanBuilder();

  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 1000,
    schemaTokens: 200,
    wrapperTokens: 100,
  );

  final String sentence = 'Это предложение содержит достаточно слов. ';
  String longParagraph({int sentences = 200}) => sentence * sentences;
  String words({int count = 40}) =>
      List<String>.filled(count, 'слово').join(' ');

  // -------------------------------------------------------------------------
  // Помощники
  // -------------------------------------------------------------------------

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
    String fileName = 'lecture.docx',
    int index = 0,
    int sectionIndex = 0,
    int bytes = 64,
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
      context: 'Окружающий текст рисунка ${index + 1}',
    );
  }

  GenerationAttachment attachmentOf({
    String fileName = 'scan.pdf',
    int bytes = 64,
    int? pageNumber,
    String? groupKey,
  }) {
    return GenerationAttachment(
      fileName: fileName,
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(
        List<int>.generate(bytes, (int i) => (bytes + i) % 251),
      ),
      pageNumber: pageNumber,
      groupKey: groupKey,
    );
  }

  ModelCapabilities caps({
    int? context = 128000,
    int? maxOutput,
    int? maxInput,
    int? maxCards,
    int? maxImages,
    int? maxImageBytesPerImage,
    int? maxImageBytesPerRequest,
    int? maxRequestBytes,
    bool vision = false,
    CapabilitySource source = CapabilitySource.preset,
  }) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: context == null ? CapabilitySource.unknown : source,
      maxInputTokens: maxInput,
      maxOutputTokens: maxOutput,
      maxCardsPerRequest: maxCards,
      maxImagesPerRequest: maxImages,
      maxImageBytesPerImage: maxImageBytesPerImage,
      maxImageBytesPerRequest: maxImageBytesPerRequest,
      maxRequestBytes: maxRequestBytes,
      supportsVision: vision,
    );
  }

  ({GenerationPlan plan, ContentInventory inventory}) makePlan({
    required List<ParsedDocument> documents,
    ModelCapabilities? capabilities,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
    List<DocumentImage> documentImages = const <DocumentImage>[],
    GenerationChunkPlanner planner = const GenerationChunkPlanner(),
    GenerationOverheadTokens? overheadTokens,
    int? requestedCards,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
  }) {
    final ModelCapabilities model = capabilities ?? caps();
    final ContentInventory inventory = builder.inventoryOf(
      documents: documents,
      attachments: attachments,
      documentImages: documentImages,
      imageTokenModel: model.imageTokens,
    );
    final GenerationPlan plan = planner.plan(
      inventory: inventory,
      capabilities: model,
      overhead: overheadTokens ?? overhead,
      requestedCards: requestedCards,
      budgetConfig: budgetConfig,
      catalogLineBuilder: (ImageRef image, int index) =>
          'img${index + 1} | ${image.image.fileName} | '
          '${image.caption ?? ''} | ${image.page ?? ''}',
    );
    return (plan: plan, inventory: inventory);
  }

  /// Проверяет инварианты D.4: покрытие, отсутствие дублей, непустые
  /// фрагменты, лимит ≥ 1, соблюдение жёсткого бюджета и размера тела.
  void expectPlanInvariants(
    ({GenerationPlan plan, ContentInventory inventory}) result, {
    ModelCapabilities? capabilities,
    GenerationOverheadTokens? overheadTokens,
    int? payloadLimit,
  }) {
    final GenerationPlan plan = result.plan;
    final ModelCapabilities model = capabilities ?? caps();
    final GenerationOverheadTokens fixed = overheadTokens ?? overhead;
    expect(plan.validity.isInvalid, isFalse, reason: '${plan.validity}');
    expect(plan.chunks, isNotEmpty);
    final GenerationPlanCoverage coverage = GenerationPlanCoverage.check(
      inventory: result.inventory,
      plan: plan,
    );
    expect(coverage.isComplete, isTrue, reason: '$coverage');
    expect(coverage.duplicatedUnits, isEmpty);

    final Set<String> partIds = <String>{};
    for (var index = 0; index < plan.chunks.length; index++) {
      final PlannedChunk chunk = plan.chunks[index];
      expect(chunk.index, index + 1);
      expect(
        chunk.limit,
        greaterThanOrEqualTo(1),
        reason: 'фрагмент ${chunk.index} без карточек',
      );
      expect(
        chunk.units.isNotEmpty ||
            chunk.imageParts.isNotEmpty ||
            chunk.catalogOnly.isNotEmpty ||
            chunk.attachments.isNotEmpty,
        isTrue,
        reason: 'пустой фрагмент ${chunk.index}',
      );
      for (final String id in chunk.imagePartIds) {
        expect(partIds.add(id), isTrue, reason: 'изображение $id дважды');
      }
      expect(
        chunk.imagePartIds.length,
        chunk.imageParts.length,
        reason: 'id частей не совпадают с изображениями',
      );
      expect(
        chunk.catalogOnlyIds.length,
        chunk.catalogOnly.length,
        reason: 'id каталога не совпадают с изображениями',
      );
      final int bound =
          payloadLimit ??
          (capabilities?.maxRequestBytes ??
              const GenerationChunkPlannerConfig().assumedMaxRequestBytes);
      expect(chunk.bodyBytes, lessThanOrEqualTo(bound));

      final int? window = model.contextWindowTokens;
      if (window != null) {
        final int outputCap =
            model.maxOutputTokens ??
            (window > 0
                ? const GenerationBudgetConfig().defaultOutputCapTokens
                : const GenerationBudgetConfig().unknownContextOutputCapTokens);
        final int expectedOutput = math.min(
          outputCap,
          chunk.limit * const GenerationBudgetConfig().perCardOutputTokens +
              const GenerationBudgetConfig().jsonEnvelopeTokens,
        );
        final int safety = math.max(
          const GenerationBudgetConfig().minSafetyMarginTokens,
          (window * const GenerationBudgetConfig().safetyMarginFraction)
              .round(),
        );
        expect(
          chunk.textTokens +
              chunk.imageTokens +
              fixed.fixedTokens +
              expectedOutput +
              safety,
          lessThanOrEqualTo(window),
          reason:
              'фрагмент ${chunk.index} не влезает в окно $window '
              '(text=${chunk.textTokens}, img=${chunk.imageTokens}, '
              'limit=${chunk.limit})',
        );
      }
    }
    expect(
      plan.plannedCards,
      plan.chunks.fold<int>(0, (int sum, PlannedChunk c) => sum + c.limit),
    );
    expect(plan.estimate.plannedChunks, plan.chunks.length);
    expect(plan.estimate.totalTokens, greaterThan(0));
  }

  /// Корневые id текстовых единиц в порядке появления в плане.
  List<String> spanRoots(GenerationPlan plan) {
    final List<String> roots = <String>[];
    for (final PlannedChunk chunk in plan.chunks) {
      for (final UnitSpan span in chunk.units) {
        final String root = span.unitId.split('~').first;
        if (!roots.contains(root)) roots.add(root);
      }
    }
    return roots;
  }

  List<String> inventoryPieceOrder(ContentInventory inventory) {
    return <String>[
      for (final DocumentUnit document in inventory.documents)
        for (final SectionUnit section in document.sections)
          for (final TextPiece piece in section.pieces) piece.id,
    ];
  }

  // -------------------------------------------------------------------------
  // 1–5. Текст и семантические границы
  // -------------------------------------------------------------------------

  group('Текст: бюджет и семантические границы', () {
    test('1. короткий текст помещается в один фрагмент', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('short.txt', <String>['Короткий текст про физику.']),
        ],
      );
      expectPlanInvariants(result);
      expect(result.plan.chunks, hasLength(1));
      expect(result.plan.chunks.single.materialsText, contains('физику'));
      expect(
        result.plan.chunks.single.materialsText,
        startsWith('Файл: short.txt'),
      );
      expect(result.plan.validity.kind, PlanValidityKind.warnings);
      expect(
        result.plan.validity.warnings,
        contains(PlanWarningCode.unknownCapabilities),
      );
    });

    test('2. большой текст требует нескольких фрагментов', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('big.txt', <String>[
            for (var index = 0; index < 20; index++)
              longParagraph(sentences: 300),
          ]),
        ],
      );
      expectPlanInvariants(result);
      expect(result.plan.chunks.length, greaterThan(1));
      final int pieces = result.inventory.documents.first.sections.length;
      expect(spanRoots(result.plan).length, lessThanOrEqualTo(pieces));
    });

    test('3. текст с большим количеством абзацев не теряется', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('paragraphs.txt', <String>[
            for (var index = 0; index < 80; index++)
              'Абзац $index: ${words(count: 12)}.',
          ]),
        ],
      );
      expectPlanInvariants(result);
      int total = 0;
      for (final DocumentUnit document in result.inventory.documents) {
        for (final SectionUnit section in document.sections) {
          total += section.pieces.length;
        }
      }
      expect(total, 80);
      expect(spanRoots(result.plan), hasLength(80));
      final String joined = result.plan.chunks
          .map((PlannedChunk chunk) => chunk.materialsText)
          .join('\n');
      for (var index = 0; index < 80; index++) {
        expect(joined, contains('Абзац $index:'));
      }
    });

    test('4. очень длинный абзац режется по предложениям, не по словам', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('long.txt', <String>[longParagraph(sentences: 6000)]),
        ],
        capabilities: caps(context: 32000),
      );
      expectPlanInvariants(result);
      expect(result.plan.chunks.length, greaterThan(2));
      for (final PlannedChunk chunk in result.plan.chunks) {
        expect(
          chunk.materialsText.endsWith('\n') ||
              chunk.materialsText.endsWith(' '),
          isTrue,
          reason:
              'фрагмент ${chunk.index} обрывается посреди предложения: '
              '«${chunk.materialsText.substring(math.max(0, chunk.materialsText.length - 30))}»',
        );
        expect(chunk.splitDepth, lessThanOrEqualTo(3));
      }
      final List<String> roots = spanRoots(result.plan);
      expect(roots, hasLength(1), reason: 'абзац один — корень один');
    });

    test('5. документ с несколькими страницами сохраняет порядок разделов', () {
      final List<String> sections = <String>[
        for (var index = 0; index < 10; index++)
          'Страница ${index + 1}. ${words(count: 30)}.',
      ];
      final result = makePlan(
        documents: <ParsedDocument>[docOf('pages.pdf', sections)],
        capabilities: caps(context: 32000),
      );
      expectPlanInvariants(result);
      final List<String> expected = inventoryPieceOrder(result.inventory);
      final List<String> observed = spanRoots(result.plan);
      expect(observed, orderedEquals(expected));
      final String joined = result.plan.chunks
          .map((PlannedChunk chunk) => chunk.materialsText)
          .join('\n');
      for (var index = 1; index <= 10; index++) {
        expect(joined, contains('Страница $index.'));
      }
    });
  });

  // -------------------------------------------------------------------------
  // 6–14. Изображения
  // -------------------------------------------------------------------------

  group('Изображения как единицы содержимого', () {
    test('6. документ с изображениями: связь с разделом сохранена', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf(
            'lecture.docx',
            <String>['Первый раздел с рисунком.', 'Второй раздел с рисунком.'],
            images: <DocumentImage>[
              imageOf(index: 0, sectionIndex: 0),
              imageOf(index: 1, sectionIndex: 1),
            ],
          ),
        ],
        capabilities: caps(vision: true, maxImages: 8),
      );
      expectPlanInvariants(result);
      final List<String> ids = <String>[
        for (final PlannedChunk chunk in result.plan.chunks)
          ...chunk.imagePartIds,
      ];
      expect(
        ids,
        containsAll(<String>['img:lecture.docx#0', 'img:lecture.docx#1']),
      );
      for (final PlannedChunk chunk in result.plan.chunks) {
        final List<String> roots = <String>[
          for (final UnitSpan span in chunk.units) span.unitId.split('~').first,
        ];
        if (roots.contains('doc:lecture.docx#0#0')) {
          expect(chunk.imagePartIds, contains('img:lecture.docx#0'));
        }
        if (roots.contains('doc:lecture.docx#1#0')) {
          expect(chunk.imagePartIds, contains('img:lecture.docx#1'));
        }
      }
    });

    test('7. несколько документов с изображениями: ничего не теряется', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf(
            'a.docx',
            <String>['Первый документ.'],
            images: <DocumentImage>[
              imageOf(fileName: 'a.docx', index: 0),
              imageOf(fileName: 'a.docx', index: 1),
            ],
          ),
          docOf(
            'b.docx',
            <String>['Второй документ.'],
            images: <DocumentImage>[imageOf(fileName: 'b.docx', index: 0)],
          ),
        ],
        capabilities: caps(vision: true, maxImages: 8),
      );
      expectPlanInvariants(result);
      final Set<String> ids = <String>{
        for (final PlannedChunk chunk in result.plan.chunks) ...[
          ...chunk.imagePartIds,
          ...chunk.catalogOnlyIds,
        ],
      };
      expect(
        ids,
        containsAll(<String>['img:a.docx#0', 'img:a.docx#1', 'img:b.docx#0']),
      );
    });

    for (final int count in <int>[1, 8, 20, 50, 100]) {
      test('${count == 1
              ? '8'
              : count == 8
              ? '9'
              : count == 20
              ? '10'
              : count == 50
              ? '11'
              : '12'}. '
          '$count изображений: части и подгруппы', () {
        final result = makePlan(
          documents: <ParsedDocument>[
            docOf(
              'images.docx',
              <String>['Раздел с изображениями.'],
              images: <DocumentImage>[
                for (var index = 0; index < count; index++)
                  imageOf(index: index),
              ],
            ),
          ],
          capabilities: caps(vision: true, maxImages: 8),
        );
        expectPlanInvariants(result);
        final List<String> partIds = <String>[
          for (final PlannedChunk chunk in result.plan.chunks)
            ...chunk.imagePartIds,
        ];
        expect(
          partIds,
          hasLength(count),
          reason: 'каждое изображение должно уйти частью ровно один раз',
        );
        expect(partIds.toSet(), hasLength(count));
        for (final PlannedChunk chunk in result.plan.chunks) {
          expect(chunk.imageParts.length, lessThanOrEqualTo(8));
        }
        expect(result.plan.omitted, isEmpty);
        final int expectedChunks = (count / 8).ceil();
        expect(result.plan.chunks.length, greaterThanOrEqualTo(expectedChunks));
      });
    }

    test('13. image_id сохраняется после дробления', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf(
            'ids.docx',
            <String>[longParagraph(sentences: 1500)],
            images: <DocumentImage>[
              for (var index = 0; index < 20; index++) imageOf(index: index),
            ],
          ),
        ],
        capabilities: caps(vision: true, maxImages: 8),
      );
      expectPlanInvariants(result);
      final Set<String> sourceIds = <String>{
        for (final ImageRef image in result.inventory.allImages) image.id,
      };
      final List<String> partIds = <String>[
        for (final PlannedChunk chunk in result.plan.chunks)
          ...chunk.imagePartIds,
      ];
      expect(
        partIds.toSet(),
        sourceIds,
        reason: 'id обязаны совпадать с инвентарём',
      );
      expect(partIds, hasLength(partIds.toSet().length));
    });

    test('14. связь изображений с разделами после дробления текста', () {
      final List<String> sections = <String>[
        for (var index = 0; index < 4; index++) longParagraph(sentences: 300),
      ];
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf(
            'sections.docx',
            sections,
            images: <DocumentImage>[
              for (var index = 0; index < 4; index++)
                imageOf(index: index, sectionIndex: index),
            ],
          ),
        ],
        capabilities: caps(vision: true, maxImages: 8),
      );
      expectPlanInvariants(result);
      for (var section = 0; section < 4; section++) {
        final String expectedImage = 'img:sections.docx#$section';
        final PlannedChunk? chunkWithImage =
            result.plan.chunks
                .where(
                  (PlannedChunk chunk) =>
                      chunk.imagePartIds.contains(expectedImage),
                )
                .isEmpty
            ? null
            : result.plan.chunks.firstWhere(
                (PlannedChunk chunk) =>
                    chunk.imagePartIds.contains(expectedImage),
              );
        expect(chunkWithImage, isNotNull, reason: 'нет части $expectedImage');
        final List<String> roots = <String>[
          for (final UnitSpan span in chunkWithImage!.units)
            span.unitId.split('~').first,
        ];
        expect(
          roots,
          contains('doc:sections.docx#$section#0'),
          reason: 'изображение $expectedImage ушло без своего раздела',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // 15–16. Лимиты моделей и размер запроса
  // -------------------------------------------------------------------------

  group('Лимиты модели и HTTP-запроса', () {
    test('15. разные лимиты изображений у моделей', () {
      final List<DocumentImage> images = <DocumentImage>[
        for (var index = 0; index < 20; index++) imageOf(index: index),
      ];
      ModelCapabilities model(int maxImages) =>
          caps(vision: true, maxImages: maxImages);
      final strict = makePlan(
        documents: <ParsedDocument>[
          docOf('lesson.docx', <String>['Материал.'], images: images),
        ],
        capabilities: model(2),
      );
      final loose = makePlan(
        documents: <ParsedDocument>[
          docOf('lesson.docx', <String>['Материал.'], images: images),
        ],
        capabilities: model(8),
      );
      expectPlanInvariants(strict, capabilities: model(2));
      expectPlanInvariants(loose, capabilities: model(8));
      for (final PlannedChunk chunk in strict.plan.chunks) {
        expect(chunk.imageParts.length, lessThanOrEqualTo(2));
      }
      for (final PlannedChunk chunk in loose.plan.chunks) {
        expect(chunk.imageParts.length, lessThanOrEqualTo(8));
      }
      expect(
        strict.plan.chunks.length,
        greaterThan(loose.plan.chunks.length),
        reason: 'строгий лимит требует больше подгрупп',
      );
    });

    test(
      '16. ограничение размера HTTP payload: изображение только в каталоге',
      () {
        final result = makePlan(
          documents: <ParsedDocument>[
            docOf(
              'payload.docx',
              <String>['Текст с большим рисунком.'],
              images: <DocumentImage>[imageOf(index: 0, bytes: 5000)],
            ),
          ],
          capabilities: caps(vision: true, maxRequestBytes: 3000, maxImages: 8),
        );
        expectPlanInvariants(result);
        for (final PlannedChunk chunk in result.plan.chunks) {
          expect(chunk.bodyBytes, lessThanOrEqualTo(3000));
          expect(chunk.imagePartIds, isEmpty);
        }
        expect(
          result.plan.chunks.expand((PlannedChunk c) => c.catalogOnlyIds),
          contains('img:payload.docx#0'),
        );
        expect(result.plan.omitted, isEmpty);
      },
    );

    test('16b. страница вложения больше payload — план невыполним', () {
      final result = makePlan(
        documents: const <ParsedDocument>[],
        attachments: <GenerationAttachment>[
          attachmentOf(bytes: 5000, pageNumber: 1, groupKey: 'scan.pdf'),
        ],
        capabilities: caps(vision: true, maxRequestBytes: 3000),
      );
      expect(result.plan.validity.isInvalid, isTrue);
      expect(result.plan.validity.reason, PlanInvalidReason.payloadTooLarge);
      expect(result.plan.chunks, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // Вложения пользователя
  // -------------------------------------------------------------------------

  group('Вложения пользователя', () {
    test('изображение-вложение уходит отдельной image-частью', () {
      final result = makePlan(
        documents: const <ParsedDocument>[],
        attachments: <GenerationAttachment>[attachmentOf(bytes: 64)],
        capabilities: caps(vision: true),
      );
      expectPlanInvariants(result);
      final PlannedChunk chunk = result.plan.chunks.single;
      expect(chunk.kind, ChunkKind.images);
      expect(chunk.attachments, hasLength(1));
      expect(chunk.attachments.single.fileName, 'scan.pdf');
      expect(chunk.imagePartIds, isEmpty, reason: 'у вложения нет img:-id');
      expect(chunk.imageTokens, greaterThan(0));
    });

    test('страницы PDF-скана: порядок, без дублей, покрытие', () {
      final result = makePlan(
        documents: const <ParsedDocument>[],
        attachments: <GenerationAttachment>[
          for (var page = 1; page <= 3; page++)
            attachmentOf(pageNumber: page, groupKey: 'scan.pdf'),
        ],
        capabilities: caps(vision: true, maxImages: 8),
      );
      expectPlanInvariants(result);
      final List<int?> plannedPages = <int?>[
        for (final PlannedChunk chunk in result.plan.chunks)
          for (final GenerationAttachment attachment in chunk.attachments)
            attachment.pageNumber,
      ];
      expect(plannedPages, <int>[1, 2, 3]);
      expect(
        result.plan.chunks.fold<int>(
          0,
          (int sum, PlannedChunk chunk) => sum + chunk.attachments.length,
        ),
        3,
      );
    });

    test('страница больше лимита изображения модели — invalid payload', () {
      final result = makePlan(
        documents: const <ParsedDocument>[],
        attachments: <GenerationAttachment>[attachmentOf(bytes: 5000)],
        capabilities: caps(
          vision: true,
          maxImageBytesPerImage: 3000,
          maxRequestBytes: 100000,
        ),
      );
      expect(result.plan.validity.isInvalid, isTrue);
      expect(result.plan.validity.reason, PlanInvalidReason.payloadTooLarge);
      expect(result.plan.chunks, isEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // 17–22. Окно контекста
  // -------------------------------------------------------------------------

  group('Окно контекста и бюджет (D.1)', () {
    test('17. неизвестное окно — консервативное допущение с пометкой', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('unknown.txt', <String>[words(count: 50)]),
        ],
        capabilities: caps(context: null),
      );
      final GenerationPlan plan = result.plan;
      expect(plan.validity.isInvalid, isFalse);
      expect(plan.budget.source, BudgetSource.assumption);
      expect(plan.budget.inputBudget, kBudgetUnknownContextInputTokens);
      expect(plan.budget.formula, GenerationBudget.formulaUnknownContext);
      expect(
        plan.unknownFields,
        contains(ModelCapabilities.unknownContextWindow),
      );
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.unknownCapabilities),
      );
      expect(plan.chunks, isNotEmpty);
      for (final PlannedChunk chunk in plan.chunks) {
        expect(
          chunk.textTokens + chunk.imageTokens,
          lessThanOrEqualTo(kBudgetUnknownContextInputTokens),
        );
      }
    });

    test('18. известный отдельный лимит входа уменьшает бюджет', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('input.txt', <String>['Текст.']),
        ],
        capabilities: caps(maxInput: 3000),
      );
      final GenerationPlan plan = result.plan;
      expect(plan.budget.maxInputTokensLimit, 3000 - overhead.fixedTokens);
      expect(plan.budget.inputBudget, 3000 - overhead.fixedTokens);
      expectPlanInvariants(result);
      expect(
        plan.chunks.single.textTokens + plan.chunks.single.imageTokens,
        lessThanOrEqualTo(3000 - overhead.fixedTokens),
      );
    });

    test('19. известное окно 8000 токенов', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('window8k.txt', <String>[words(count: 300)]),
        ],
        capabilities: caps(context: 8000),
      );
      expectPlanInvariants(result);
      final BudgetTrace trace = result.plan.budget;
      expect(trace.contextWindowTokens, 8000);
      expect(trace.safetyMarginTokens, 400);
      expect(
        result.plan.budget.inputBudget,
        8000 -
            trace.reservedOutputTokens -
            trace.fixedOverheadTokens -
            trace.safetyMarginTokens!,
      );
    });

    test('20. известное окно 128000 токенов', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('window128k.txt', <String>[words(count: 2000)]),
        ],
        capabilities: caps(context: 128000),
      );
      expectPlanInvariants(result);
      final BudgetTrace trace = result.plan.budget;
      expect(trace.contextWindowTokens, 128000);
      expect(trace.safetyMarginTokens, 6400);
      expect(
        result.plan.budget.inputBudget,
        128000 -
            trace.reservedOutputTokens -
            trace.fixedOverheadTokens -
            trace.safetyMarginTokens!,
      );
    });

    test('21. известное окно 200000 токенов: мягкая цель заполнения', () {
      final String paragraph = words(count: 4000);
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('window200k.txt', <String>[
            for (var index = 0; index < 10; index++) paragraph,
          ]),
        ],
        capabilities: caps(context: 200000),
      );
      expectPlanInvariants(result);
      expect(result.plan.chunks.length, greaterThan(1));
      final int softTarget =
          3 *
          const GenerationChunkPlannerConfig().softTargetMaterialTokensPerCard;
      for (final PlannedChunk chunk in result.plan.chunks) {
        expect(
          chunk.textTokens,
          lessThanOrEqualTo(softTarget + 12000),
          reason: 'фрагмент ${chunk.index} переполнен по мягкой цели',
        );
      }
    });

    test('22. большое окно 1M: фрагменты остаются осмысленного размера', () {
      final String paragraph = words(count: 6000);
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('window1m.txt', <String>[
            for (var index = 0; index < 6; index++) paragraph,
          ]),
        ],
        capabilities: caps(context: 1048576),
      );
      expectPlanInvariants(result);
      expect(result.plan.chunks.length, greaterThan(1));
      expect(result.plan.budget.contextWindowTokens, 1048576);
      for (final PlannedChunk chunk in result.plan.chunks) {
        expect(
          chunk.textTokens,
          lessThanOrEqualTo(36000),
          reason: 'мягкая цель не должна позволять гигантские фрагменты',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // 23–26. Невыполнимые и пограничные планы
  // -------------------------------------------------------------------------

  group('Невыполнимые планы и заказ карточек', () {
    test('23. недостаточный бюджет — invalid, а не «всё равно 2000»', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('tiny.txt', <String>['Текст.']),
        ],
        capabilities: caps(context: 8000, maxOutput: 1000),
        overheadTokens: const GenerationOverheadTokens(
          systemPromptTokens: 7000,
          schemaTokens: 400,
          wrapperTokens: 100,
        ),
      );
      final GenerationPlan plan = result.plan;
      expect(plan.validity.isInvalid, isTrue);
      expect(plan.validity.reason, PlanInvalidReason.contextWindowTooSmall);
      expect(plan.chunks, isEmpty);
      expect(plan.validity.availableTokens, lessThan(0));
      expect(plan.isExecutable, isFalse);
    });

    test(
      '24. очень большой документ: предохранитель maxChunks диагностируем',
      () {
        final result = makePlan(
          documents: <ParsedDocument>[
            docOf('huge.txt', <String>[
              for (var index = 0; index < 200; index++)
                longParagraph(sentences: 20),
            ]),
          ],
          planner: const GenerationChunkPlanner(
            config: GenerationChunkPlannerConfig(maxChunks: 3),
          ),
        );
        expect(result.plan.validity.isInvalid, isTrue);
        expect(result.plan.validity.reason, PlanInvalidReason.tooManyChunks);
        expect(result.plan.chunks, isEmpty);
        expect(result.plan.validity.neededTokens, greaterThan(3));
        expect(result.plan.validity.availableTokens, 3);
      },
    );

    test(
      '24b. очень большой документ в пределах предохранителя планируется',
      () {
        final result = makePlan(
          documents: <ParsedDocument>[
            docOf('large.txt', <String>[
              for (var index = 0; index < 40; index++)
                longParagraph(sentences: 200),
            ]),
          ],
        );
        expectPlanInvariants(result);
        expect(result.plan.chunks.length, greaterThan(1));
        expect(result.plan.chunks.length, lessThanOrEqualTo(512));
      },
    );

    test('25. невозможность безопасно сформировать план: нет Vision', () {
      final result = makePlan(
        documents: const <ParsedDocument>[],
        attachments: <GenerationAttachment>[attachmentOf()],
        capabilities: caps(vision: false),
      );
      expect(result.plan.validity.isInvalid, isTrue);
      expect(
        result.plan.validity.reason,
        PlanInvalidReason.imagesWithoutVision,
      );
      expect(result.plan.chunks, isEmpty);
    });

    test('26. заказ больше, чем позволяет бюджет вывода — предупреждение', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('requested.txt', <String>[
            for (var index = 0; index < 30; index++)
              longParagraph(sentences: 30),
          ]),
        ],
        requestedCards: 100,
      );
      final GenerationPlan plan = result.plan;
      expect(plan.validity.isInvalid, isFalse);
      expect(plan.requestedCards, 100, reason: 'заказ нельзя менять молча');
      expect(plan.plannedCards, lessThan(100));
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.requestedAbovePlan),
      );
      expectPlanInvariants(result);
    });

    test(
      '26b. заказ меньше числа фрагментов — не ноль карточек на фрагмент',
      () {
        final result = makePlan(
          documents: <ParsedDocument>[
            for (var index = 0; index < 4; index++)
              docOf('doc$index.txt', <String>[longParagraph(sentences: 800)]),
          ],
          requestedCards: 2,
        );
        final GenerationPlan plan = result.plan;
        expect(plan.requestedCards, 2);
        expect(plan.chunks, isNotEmpty);
        for (final PlannedChunk chunk in plan.chunks) {
          expect(chunk.limit, greaterThanOrEqualTo(1));
        }
        expect(
          plan.validity.warnings,
          contains(PlanWarningCode.cardsAboveRequested),
        );
        expectPlanInvariants(result);
      },
    );

    test(
      '26c. распределение заказа: сумма равна заказу в пределах потолка',
      () {
        final result = makePlan(
          documents: <ParsedDocument>[
            docOf('distribute.txt', <String>[
              for (var index = 0; index < 12; index++)
                longParagraph(sentences: 300),
            ]),
          ],
          requestedCards: 7,
        );
        final GenerationPlan plan = result.plan;
        if (plan.chunks.length <= 7) {
          expect(plan.plannedCards, 7);
        }
        expect(plan.requestedCards, 7);
        expectPlanInvariants(result);
      },
    );
  });

  // -------------------------------------------------------------------------
  // Количество карточек: расчёт, а не «универсальное 20»
  // -------------------------------------------------------------------------

  group('Количество карточек (D.2/D.7)', () {
    test('потолок считается из бюджета вывода, а не из 20', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('cards.txt', <String>['Материал для карточек.']),
        ],
        capabilities: caps(context: 128000, maxOutput: 50000, maxCards: 40),
      );
      expectPlanInvariants(result);
      expect(result.plan.chunks.single.limit, 40);
      expect(result.plan.plannedCards, 40);

      final ({GenerationPlan plan, ContentInventory inventory}) noModelCap =
          makePlan(
            documents: <ParsedDocument>[
              docOf('cards2.txt', <String>['Материал для карточек.']),
            ],
            capabilities: caps(context: 128000, maxOutput: 50000),
          );
      // (50 000 − 16) / 1024 = 48 — потолок по выводу, без произвольного 20.
      expect(noModelCap.plan.chunks.single.limit, 48);
    });

    test('лимит модели maxCardsPerRequest режет потолок вывода', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('cards.txt', <String>['Материал для карточек.']),
        ],
        capabilities: caps(context: 128000, maxOutput: 50000, maxCards: 7),
      );
      expect(result.plan.chunks.single.limit, 7);
    });

    test('заказ пользователя не уменьшается молча даже выше потолка', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('cards.txt', <String>['Материал для карточек.']),
        ],
        capabilities: caps(context: 128000, maxOutput: 50000, maxCards: 40),
        requestedCards: 100,
      );
      expect(result.plan.requestedCards, 100);
      expect(result.plan.chunks.single.limit, 40);
      expect(
        result.plan.validity.warnings,
        contains(PlanWarningCode.requestedAbovePlan),
      );
    });

    test('неизвестный лимит вывода — консервативный потолок из конфига', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('cards.txt', <String>['Материал для карточек.']),
        ],
        capabilities: caps(context: 128000),
      );
      final int expected =
          (const GenerationBudgetConfig().defaultOutputCapTokens -
              const GenerationBudgetConfig().jsonEnvelopeTokens) ~/
          const GenerationBudgetConfig().perCardOutputTokens;
      expect(result.plan.chunks.single.limit, expected);
      expect(result.plan.budget.outputCapAssumed, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // 27–30. Инварианты и совместимость
  // -------------------------------------------------------------------------

  group('Инварианты отсутствия потерь, дублей и порядка', () {
    test('27. отсутствие потерь: параметризованный набор объёмов', () {
      for (final int paragraphs in <int>[1, 3, 12, 40]) {
        for (final int images in <int>[0, 1, 8, 20]) {
          final result = makePlan(
            documents: <ParsedDocument>[
              docOf(
                'p$paragraphs-i$images.txt',
                <String>[
                  for (var index = 0; index < paragraphs; index++)
                    'Абзац $index: ${words(count: 25)}.',
                ],
                images: <DocumentImage>[
                  for (var index = 0; index < images; index++)
                    imageOf(
                      fileName: 'p$paragraphs-i$images.txt',
                      index: index,
                      sectionIndex: index % paragraphs,
                    ),
                ],
              ),
            ],
            capabilities: caps(vision: images > 0, maxImages: 8),
          );
          expectPlanInvariants(result);
          expect(
            result.plan.omitted,
            isEmpty,
            reason: 'p=$paragraphs i=$images: ${result.plan.omitted}',
          );
        }
      }
    });

    test('28. отсутствие дублей единиц и изображений', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf(
            'duplicates.docx',
            <String>[
              longParagraph(sentences: 120),
              longParagraph(sentences: 120),
            ],
            images: <DocumentImage>[
              for (var index = 0; index < 20; index++)
                imageOf(index: index, sectionIndex: index % 2),
            ],
          ),
        ],
        capabilities: caps(vision: true, maxImages: 8),
      );
      expectPlanInvariants(result);
      final List<String> spanIds = <String>[
        for (final PlannedChunk chunk in result.plan.chunks)
          for (final UnitSpan span in chunk.units) span.unitId,
      ];
      expect(spanIds.toSet(), hasLength(spanIds.length));
      final List<String> pageIds = <String>[
        for (final PlannedChunk chunk in result.plan.chunks)
          for (final GenerationAttachment a in chunk.attachments)
            '${a.fileName}#${a.pageNumber}',
      ];
      expect(pageIds.toSet(), hasLength(pageIds.length));
    });

    test('29. исходный порядок единиц сохраняется', () {
      final result = makePlan(
        documents: <ParsedDocument>[
          docOf('order-a.txt', <String>[
            'Первый документ, раздел 1.',
            'Первый документ, раздел 2.',
          ]),
          docOf('order-b.txt', <String>[
            'Второй документ, раздел 1.',
            longParagraph(sentences: 60),
          ]),
        ],
      );
      expectPlanInvariants(result);
      expect(
        spanRoots(result.plan),
        orderedEquals(inventoryPieceOrder(result.inventory)),
      );
    });

    test('линейность: оценщик не пересчитывает текст квадратично', () {
      final CountingEstimator counting = CountingEstimator();
      final GenerationChunkPlanner local = GenerationChunkPlanner(
        estimator: counting,
      );
      final List<String> sections = <String>[
        for (var index = 0; index < 60; index++)
          'Раздел $index. ${words(count: 15)}.',
      ];
      final result = makePlan(
        documents: <ParsedDocument>[docOf('linear.txt', sections)],
        planner: local,
      );
      expect(result.plan.chunks, isNotEmpty);
      // Оценка текста вызывается на единицу (построение фрагментов, заголовки
      // и разделители) — не на каждый кандидат упаковки.
      expect(
        counting.textCalls,
        lessThanOrEqualTo(sections.length * 3 + 8),
        reason: 'вызовов оценки текста: ${counting.textCalls}',
      );
    });
  });

  // -------------------------------------------------------------------------
  // 30. Совместимость старого GenerationChunker
  // -------------------------------------------------------------------------

  group('30. Совместимость GenerationChunker', () {
    test('старые методы не изменились, новые поля пусты', () {
      const GenerationChunker chunker = GenerationChunker();
      final List<GenerationChunk> chunks = chunker.chunkDocuments(
        <ParsedDocument>[
          docOf('legacy.txt', <String>['Первый раздел', 'Второй раздел']),
        ],
        maxInputTokens: 1000,
      );
      expect(chunks, isNotEmpty);
      for (final GenerationChunk chunk in chunks) {
        expect(chunk.unitIds, isEmpty);
        expect(chunk.splitDepth, 0);
        expect(chunk.imageParts, isEmpty);
        expect(chunk.catalogOnly, isEmpty);
        expect(chunk.limit, kMaxCardsPerChunk);
      }
    });

    test('splitInHalf очищает новые поля и увеличивает глубину', () {
      const GenerationChunker chunker = GenerationChunker();
      const GenerationChunk chunk = GenerationChunk(
        index: 1,
        materialsText: 'Первая половина текста.\n\nВторая половина текста.',
        sourceFiles: <String>['legacy.txt'],
        limit: 5,
        unitIds: <String>['doc:legacy.txt#0#0'],
        imageParts: <DocumentImage>[],
        catalogOnly: <DocumentImage>[],
      );
      final List<GenerationChunk>? halves = chunker.splitInHalf(chunk);
      expect(halves, isNotNull);
      for (final GenerationChunk half in halves!) {
        expect(half.unitIds, isEmpty);
        expect(half.imageParts, isEmpty);
        expect(half.catalogOnly, isEmpty);
        expect(half.splitDepth, 1);
        expect(half.splitAttempted, isTrue);
      }
    });

    test('planChunks/chunksFromPlan — новый путь без изменения старого', () {
      const GenerationChunker chunker = GenerationChunker();
      final ContentInventory inventory = builder.inventoryOf(
        documents: <ParsedDocument>[
          docOf(
            'bridge.docx',
            <String>['Раздел с рисунком.'],
            images: <DocumentImage>[imageOf(index: 0)],
          ),
        ],
      );
      final GenerationPlan plan = chunker.planChunks(
        inventory,
        capabilities: caps(vision: true, maxImages: 8),
        overhead: overhead,
      );
      expect(plan.validity.isInvalid, isFalse);
      final List<GenerationChunk> chunks = chunker.chunksFromPlan(plan);
      expect(chunks, hasLength(plan.chunks.length));
      for (var index = 0; index < chunks.length; index++) {
        final GenerationChunk chunk = chunks[index];
        final PlannedChunk planned = plan.chunks[index];
        expect(chunk.materialsText, planned.materialsText);
        expect(chunk.limit, planned.limit);
        expect(chunk.unitIds, <String>[
          for (final UnitSpan span in planned.units) span.unitId,
        ]);
        expect(
          chunk.imageParts.map((DocumentImage i) => i.fileName),
          isNotEmpty,
        );
        expect(
          chunk.documentImages.length,
          planned.imageParts.length + planned.catalogOnly.length,
        );
        expect(chunk.sourceFiles, contains('bridge.docx'));
      }
    });
  });

  // -------------------------------------------------------------------------
  // Защита от «универсальных» чисел
  // -------------------------------------------------------------------------

  group('Нет зависимости от фиксированных чисел', () {
    test('планировщик не использует kMaxCardsPerChunk/kImageTokenEstimate', () {
      final String source = File(
        'lib/domain/generation/generation_chunk_planner.dart',
      ).readAsStringSync();
      expect(source, isNot(contains('kMaxCardsPerChunk')));
      expect(source, isNot(contains('kImageTokenEstimate')));
      expect(source, isNot(contains('* 20')));
      final String budget = File('lib/domain/generation/generation_budget.dart')
          .readAsStringSync();
      expect(budget, isNot(contains('kMinInputTokenBudget')));
    });
  });
}

/// Оценщик, считающий вызовы оценки текста (проверка линейности упаковки).
class CountingEstimator implements ContentTokenEstimator {
  int textCalls = 0;

  final HeuristicContentTokenEstimator _delegate =
      const HeuristicContentTokenEstimator();

  @override
  String get version => 'counting/1';

  @override
  double get charsPerToken => _delegate.charsPerToken;

  @override
  int estimateText(String text) {
    textCalls++;
    return _delegate.estimateText(text);
  }

  @override
  ImageTokenEstimate estimateImage({
    int? width,
    int? height,
    required int bytes,
    ImageTokenModel? model,
  }) {
    return _delegate.estimateImage(
      width: width,
      height: height,
      bytes: bytes,
      model: model,
    );
  }
}
