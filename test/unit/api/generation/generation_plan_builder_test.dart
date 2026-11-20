import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/generation_request_estimator.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// TASK 02B: сборка `ContentInventory` и `GenerationPlan` из материалов.
void main() {
  const GenerationPlanBuilder builder = GenerationPlanBuilder();

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
      format: DocumentFormat.docx,
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
    bool withSize = false,
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
      caption: 'Рис. $index',
      context: 'Контекст рисунка $index',
      width: withSize ? 100 : null,
      height: withSize ? 100 : null,
    );
  }

  GenerationAttachment pageOf({
    String fileName = 'scan.pdf',
    int page = 1,
    String? groupKey = 'scan.pdf',
  }) {
    return GenerationAttachment(
      fileName: fileName,
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(
        List<int>.generate(32, (int i) => (page + i) % 251),
      ),
      pageNumber: page,
      groupKey: groupKey,
    );
  }

  ModelCapabilities caps({
    int? context = 128000,
    GenerationPricing? pricing,
    ImageTokenModel? imageTokens,
    bool supportsVision = false,
  }) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: context == null
          ? CapabilitySource.unknown
          : CapabilitySource.officialCatalog,
      pricing: pricing,
      pricingSource: pricing == null
          ? CapabilitySource.unknown
          : CapabilitySource.userConfigured,
      imageTokens: imageTokens,
      supportsVision: supportsVision,
    );
  }

  group('ContentInventory: документы, разделы, фрагменты', () {
    test('стабильные id, смещения и точное покрытие текста раздела', () {
      final ContentInventory inventory = builder.inventoryOf(
        documents: <ParsedDocument>[
          docOf('lecture.docx', <String>[
            'Первый абзац.\n\nВторой абзац.',
            'Третий раздел.',
          ]),
        ],
      );
      expect(inventory.documents, hasLength(1));
      final DocumentUnit document = inventory.documents.single;
      expect(document.id, 'doc:lecture.docx');
      expect(document.sections, hasLength(2));
      final SectionUnit first = document.sections.first;
      expect(first.id, 'doc:lecture.docx#0');
      expect(first.pieces, hasLength(2));
      expect(first.pieces[0].id, 'doc:lecture.docx#0#0');
      expect(first.pieces[1].id, 'doc:lecture.docx#0#1');
      expect(first.pieces[0].text, 'Первый абзац.\n\n');
      expect(first.pieces[1].text, 'Второй абзац.');
      expect(
        first.pieces.map((TextPiece p) => p.text).join(),
        first.text,
        reason: 'фрагменты обязаны точно покрывать текст раздела',
      );
      for (final TextPiece piece in first.pieces) {
        expect(piece.tokens, greaterThan(0));
        expect(piece.start, lessThan(piece.end));
      }
      expect(
        first.pieces[0].end,
        first.pieces[1].start,
        reason: 'фрагменты идут подряд без пропусков',
      );
      expect(document.sections[1].pieces.single.text, 'Третий раздел.');
    });

    test('изображения получают стабильные id и связь с разделом', () {
      final ContentInventory inventory = builder.inventoryOf(
        documents: <ParsedDocument>[
          docOf(
            'lecture.docx',
            <String>['Раздел 1.', 'Раздел 2.'],
            images: <DocumentImage>[
              imageOf(index: 0, sectionIndex: 0),
              imageOf(index: 1, sectionIndex: 1),
            ],
          ),
        ],
      );
      final DocumentUnit document = inventory.documents.single;
      expect(document.images, hasLength(2));
      expect(document.images[0].id, 'img:lecture.docx#0');
      expect(document.images[0].sectionId, 'doc:lecture.docx#0');
      expect(document.images[1].id, 'img:lecture.docx#1');
      expect(document.images[1].sectionId, 'doc:lecture.docx#1');
      expect(document.catalog.images, hasLength(2));
      for (final ImageRef image in document.images) {
        expect(image.tokens, greaterThan(0));
        expect(image.isOrphan, isFalse);
      }
      expect(document.sections[0].images.single.id, 'img:lecture.docx#0');
      expect(document.sections[1].images.single.id, 'img:lecture.docx#1');
    });

    test('дополнительные изображения файла попадают в его документ', () {
      final ContentInventory inventory = builder.inventoryOf(
        documents: <ParsedDocument>[
          docOf('a.pdf', <String>['Страница PDF.']),
        ],
        documentImages: <DocumentImage>[
          imageOf(fileName: 'a.pdf', index: 0, sectionIndex: 0),
        ],
      );
      final DocumentUnit document = inventory.documents.single;
      expect(document.images, hasLength(1));
      expect(document.images.single.id, 'img:a.pdf#0');
      expect(document.sections.single.images, hasLength(1));
    });

    test('вложения: страницы группируются, id страницы стабилен', () {
      final ContentInventory inventory = builder.inventoryOf(
        documents: const <ParsedDocument>[],
        attachments: <GenerationAttachment>[
          pageOf(page: 1),
          pageOf(page: 2),
          pageOf(fileName: 'photo.png', groupKey: null),
        ],
      );
      expect(inventory.attachments, hasLength(2));
      final AttachmentUnit scan = inventory.attachments[0];
      expect(scan.id, 'att:scan.pdf');
      expect(scan.pages, hasLength(2));
      expect(scan.pages[0].id, 'att:scan.pdf#p1');
      expect(scan.pages[1].id, 'att:scan.pdf#p2');
      expect(scan.totalTokens, greaterThan(0));
      expect(scan.byteLength, 64);
      final AttachmentUnit photo = inventory.attachments[1];
      expect(photo.id, 'att:photo.png');
      expect(photo.pages.single.id, 'att:photo.png#p1');
    });

    test('изображения файла без документа — orphan, но не теряются', () {
      final ContentInventory inventory = builder.inventoryOf(
        documents: const <ParsedDocument>[],
        documentImages: <DocumentImage>[
          imageOf(fileName: 'scan.pdf', index: 0),
        ],
      );
      expect(inventory.documents, isEmpty);
      expect(inventory.orphanImages, hasLength(1));
      expect(inventory.orphanImages.single.id, 'img:scan.pdf#0');
      expect(inventory.orphanImages.single.image.isOrphan, isTrue);
      expect(inventory.imageById('img:scan.pdf#0'), isNotNull);
    });
  });

  group('GenerationPlanBuilder: обвязка и заказ', () {
    test('системный промпт, схема и обёртка входят в бюджет', () {
      final GenerationPlan plan = builder.build(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        capabilities: caps(),
      );
      final GenerationPlanBuilder local = builder;
      final int promptTokens = local.estimator.estimateText(
        systemPromptGenRuV7,
      );
      expect(plan.budget.systemPromptTokens, promptTokens);
      expect(plan.budget.schemaTokens, greaterThan(0));
      expect(plan.budget.wrapperTokens, greaterThan(0));
      expect(plan.budget.fixedOverheadTokens, greaterThan(promptTokens));
      expect(plan.estimate.fixedPromptTokens, promptTokens);
      expect(plan.validity.isInvalid, isFalse);
    });

    test('пожелания увеличивают обёртку и задают заказ карточек', () {
      final GenerationPlan plan = builder.build(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        capabilities: caps(),
        wishes: 'Сделайте 7 карточек по теме «Статика»',
      );
      expect(plan.requestedCards, 7);
      final GenerationPlan withoutWishes = builder.build(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        capabilities: caps(),
      );
      expect(
        plan.budget.wrapperTokens,
        greaterThan(withoutWishes.budget.wrapperTokens),
      );
    });

    test('своя схема/промпт учитываются в фиксированной обвязке', () {
      final GenerationPlan small = builder.build(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        capabilities: caps(),
        systemPrompt: 'короткий промпт',
        responseSchema: const <String, Object?>{'type': 'object'},
      );
      expect(
        small.budget.schemaTokens,
        builder.estimator.estimateText('{"type":"object"}'),
      );
      expect(
        small.budget.systemPromptTokens,
        builder.estimator.estimateText('короткий промпт'),
      );
    });

    test('пустые материалы и пожелания — пустой план без фрагментов', () {
      final GenerationPlan plan = builder.build(
        documents: const <ParsedDocument>[],
        capabilities: caps(),
        wishes: null,
      );
      expect(plan.chunks, isEmpty);
      expect(plan.validity.isValid, isTrue);
      expect(plan.isExecutable, isFalse);
    });

    test(
      'prompt-only без файлов: материалов нет — фрагмент создаёт пайплайн',
      () {
        final GenerationPlan plan = builder.build(
          documents: const <ParsedDocument>[],
          capabilities: caps(),
          wishes: 'Тема: статика',
        );
        expect(plan.chunks, isEmpty);
      },
    );
  });

  group('GenerationPlanBuilder: цены и оценка изображений', () {
    test('полные цены дают стоимость, неизвестные — null (не 0)', () {
      final GenerationPlan priced = builder.build(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        capabilities: caps(
          pricing: const GenerationPricing(
            inputPerMillion: 1,
            outputPerMillion: 2,
            currency: 'USD',
          ),
        ),
      );
      expect(priced.estimate.pricingState, PricingState.complete);
      expect(priced.estimate.totalCost, isNotNull);
      expect(priced.estimate.inputCost, isNotNull);
      expect(priced.estimate.outputCost, isNotNull);
      expect(priced.estimate.currency, 'USD');

      final GenerationPlan unknown = builder.build(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        capabilities: caps(),
      );
      expect(unknown.estimate.pricingState, PricingState.unknown);
      expect(unknown.estimate.totalCost, isNull);
      expect(unknown.estimate.inputCost, isNull);
      expect(unknown.estimate.totalCost, isNot(0));
      expect(
        unknown.validity.warnings,
        contains(PlanWarningCode.unknownCapabilities),
      );
    });

    test('токены изображения берутся из возможностей модели', () {
      final GenerationPlan plan = builder.build(
        documents: <ParsedDocument>[
          docOf(
            'lecture.docx',
            <String>['Раздел с рисунком.'],
            images: <DocumentImage>[imageOf(index: 0)],
          ),
        ],
        capabilities: caps(
          imageTokens: const _FixedImageModel(500),
          supportsVision: true,
        ),
      );
      expect(plan.chunks, isNotEmpty);
      final int imageTokens = plan.chunks.fold<int>(
        0,
        (int sum, PlannedChunk chunk) => sum + chunk.imageTokens,
      );
      expect(imageTokens, 500);
    });
  });

  group('GenerationPlanBuilder: планирование по общему пути', () {
    test('оценка плана и оценка собранного запроса согласованы', () {
      const String wishes = 'Сделай 5 карточек';
      final GenerationPlan plan = builder.build(
        documents: <ParsedDocument>[
          docOf('agree.txt', <String>[
            'Первый абзац материала.',
            'Второй абзац.',
          ]),
        ],
        capabilities: caps(),
        wishes: wishes,
        requestedCards: 5,
      );
      final PlannedChunk chunk = plan.chunks.single;
      final String userContent = buildGenerationUserContent(
        materialsText: chunk.materialsText,
        wishes: wishes,
        limit: chunk.limit,
        imagesCatalog: null,
      );
      final GenerationRequestEstimate requestEstimate =
          const GenerationRequestEstimator().estimate(
            userContent: userContent,
            attachments: const <GenerationAttachment>[],
            maxOutputTokens: plan.budget.outputCapTokens,
          );
      final int plannedInput =
          plan.budget.systemPromptTokens +
          plan.budget.schemaTokens +
          plan.budget.wrapperTokens +
          chunk.textTokens +
          chunk.imageTokens;
      expect(
        requestEstimate.inputTotal.tokens,
        closeTo(plannedInput, 100),
        reason:
            'планировщик и исполнитель считают одним оценщиком; разница — '
            'обёртка/цифры <limit>, а не другая формула',
      );
    });

    test('build и plan дают одинаковый бюджет на одних входах', () {
      const GenerationOverheadTokens overhead = GenerationOverheadTokens(
        systemPromptTokens: 100,
        schemaTokens: 10,
        wrapperTokens: 10,
      );
      final List<ParsedDocument> documents = <ParsedDocument>[
        docOf('path.txt', <String>['Материал для плана.']),
      ];
      final ModelCapabilities capabilities = caps();
      final GenerationPlan viaBuild = builder.build(
        documents: documents,
        capabilities: capabilities,
        overhead: overhead,
      );
      final ContentInventory inventory = builder.inventoryOf(
        documents: documents,
      );
      final GenerationPlan viaPlan = const GenerationChunkPlanner().plan(
        inventory: inventory,
        capabilities: capabilities,
        overhead: overhead,
        catalogLineBuilder: plannerCatalogLine,
      );
      expect(viaBuild.chunks.length, viaPlan.chunks.length);
      expect(
        viaBuild.chunks.first.materialsText,
        viaPlan.chunks.first.materialsText,
      );
      expect(viaBuild.budget.inputBudget, viaPlan.budget.inputBudget);
    });
  });
}

String plannerCatalogLine(ImageRef image, int index) =>
    'img${index + 1} | ${image.image.fileName}';

class _FixedImageModel implements ImageTokenModel {
  const _FixedImageModel(this.tokens);

  final int tokens;

  @override
  int estimate({int? width, int? height, required int bytes}) => tokens;

  @override
  String get source => 'test_formula';
}
