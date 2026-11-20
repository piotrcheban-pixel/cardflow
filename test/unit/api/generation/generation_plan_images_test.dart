import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// TASK 03, раздел 6: прозрачный статус изображения в плане.
void main() {
  ParsedDocument docWith(List<DocumentImage> images) {
    const String text = 'Раздел с рисунком и текстом для карточки.';
    return ParsedDocument(
      format: DocumentFormat.docx,
      fileName: 'лекция.docx',
      text: text,
      sections: const <ParsedSection>[
        ParsedSection(start: 0, end: text.length),
      ],
      images: images,
    );
  }

  DocumentImage imageOf(int index, {List<int>? bytes}) {
    return DocumentImage(
      fileName: 'лекция.docx',
      bytes: Uint8List.fromList(
        bytes ?? List<int>.generate(4096, (int i) => (index * 31 + i) % 251),
      ),
      mediaType: AttachmentMediaType.png,
      width: 800,
      height: 600,
      sectionIndex: 0,
      caption: 'Рис. $index',
    );
  }

  ModelCapabilities caps({bool vision = true, int context = 128000}) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: CapabilitySource.officialCatalog,
      supportsVision: vision,
    );
  }

  GenerationPlan build(
    List<DocumentImage> images, {
    bool vision = true,
    int context = 128000,
  }) {
    return const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docWith(images)],
      capabilities: caps(vision: vision, context: context),
      requestedCards: 5,
    );
  }

  test('Vision: изображения реально передаются частями', () {
    final GenerationPlan plan = build(<DocumentImage>[imageOf(0), imageOf(1)]);
    expect(plan.images, hasLength(2));
    expect(plan.imagesSentToModel, 2);
    expect(plan.imagesCatalogOnly, 0);
    expect(plan.imagesUnsupported, 0);
    expect(plan.hasImagesNotSent, isFalse);
    expect(plan.chunks.single.imageParts, hasLength(2));
    expect(plan.chunks.single.catalogOnly, isEmpty);
    expect(
      plan.validity.warnings,
      isNot(contains(PlanWarningCode.imagesWithoutVision)),
    );
  });

  test('без Vision: изображения только в каталоге, план не врёт о частях', () {
    final GenerationPlan plan = build(<DocumentImage>[
      imageOf(0),
      imageOf(1),
    ], vision: false);
    expect(plan.validity.isInvalid, isFalse);
    expect(plan.imagesUnsupported, 2);
    expect(plan.imagesSentToModel, 0);
    expect(plan.hasImagesNotSent, isTrue);
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.imageParts, isEmpty);
      expect(chunk.catalogOnly, hasLength(2));
    }
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.imagesWithoutVision),
    );
  });

  test('одинаковые байты не отправляются дважды (дедуп в плане)', () {
    final List<int> sameBytes = List<int>.generate(4096, (int i) => i % 251);
    final GenerationPlan plan = build(<DocumentImage>[
      imageOf(0, bytes: sameBytes),
      imageOf(1, bytes: sameBytes),
    ]);
    expect(plan.images, hasLength(2));
    expect(plan.imagesSentToModel, 1);
    expect(plan.imagesCatalogOnly, 1);
  });

  test('источники возможностей доступны в плане', () {
    final GenerationPlan plan = build(<DocumentImage>[imageOf(0)]);
    expect(plan.capabilitySources.containsKey('context_window'), isTrue);
    expect(plan.capabilitySources['context_window'], CapabilitySource.officialCatalog);
    expect(
      plan.capabilitySources['max_cards_per_request'],
      CapabilitySource.unknown,
    );
    expect(
      plan.unknownFields,
      anyOf(contains('max_images_per_request'), contains('max_output_tokens')),
    );
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.assumedImageLimits),
    );
  });

  test('лимит числа частей из аккаунта соблюдается планом', () {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[
        docWith(<DocumentImage>[
          for (var index = 0; index < 10; index++) imageOf(index),
        ]),
      ],
      capabilities: ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.officialCatalog,
        supportsVision: true,
        maxImagesPerRequest: 3,
        imageSource: CapabilitySource.userConfigured,
      ),
      requestedCards: 5,
    );
    expect(plan.imagesSentToModel, 10);
    expect(plan.imagesCatalogOnly, 0);
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.imageParts.length, lessThanOrEqualTo(3));
    }
    expect(plan.capabilitySources['image_limits'], CapabilitySource.userConfigured);
  });

  test('изображение больше лимита байт не отправляется частью', () {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[
        docWith(<DocumentImage>[imageOf(0)]),
      ],
      capabilities: ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.officialCatalog,
        supportsVision: true,
        maxImageBytesPerImage: 1000,
        imageSource: CapabilitySource.userConfigured,
      ),
      requestedCards: 5,
    );
    expect(plan.imagesSentToModel, 0);
    expect(plan.imagesCatalogOnly, 1);
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.imageParts, isEmpty);
      expect(chunk.catalogOnly, hasLength(1));
    }
  });

  test('сумма байт image-частей не превышает лимит запроса', () {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[
        docWith(<DocumentImage>[
          for (var index = 0; index < 3; index++) imageOf(index),
        ]),
      ],
      capabilities: ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.officialCatalog,
        supportsVision: true,
        maxImageBytesPerRequest: 5000,
        imageSource: CapabilitySource.userConfigured,
      ),
      requestedCards: 5,
    );
    expect(
      plan.imagesSentToModel,
      3,
      reason: 'все части уходят, но по разным запросам',
    );
    for (final PlannedChunk chunk in plan.chunks) {
      final int bytes = chunk.imageParts.fold<int>(
        0,
        (int sum, DocumentImage image) => sum + image.bytes.length,
      );
      expect(bytes, lessThanOrEqualTo(5000));
    }
  });

  test('вложения без Vision — план невыполним (не молчаливое исключение)', () {
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: const <ParsedDocument>[],
      capabilities: caps(vision: false),
      attachments: <GenerationAttachment>[
        GenerationAttachment(
          fileName: 'схема.png',
          mediaType: AttachmentMediaType.png,
          bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
        ),
      ],
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.imagesWithoutVision);
  });
}
