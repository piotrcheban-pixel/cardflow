import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// §3.4: `D = текст материалов + каталог изображений + токены вложений`.
///
/// Проверяется на **production-сборщике плана** (`GenerationPlanBuilder`), а не
/// на синтетическом `InputPlanner`: строка каталога должна быть ровно той, что
/// уйдёт в `<images>` реального запроса (`imageCatalogLine`).
void main() {
  const ContentTokenEstimator estimator = HeuristicContentTokenEstimator();
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
    int index = 0,
    int sectionIndex = 0,
    String caption = 'Схема',
    String context = 'Схема из текста раздела',
  }) {
    return DocumentImage(
      fileName: 'лекция.docx',
      bytes: Uint8List.fromList(
        List<int>.generate(64, (int i) => (index + i) % 251),
      ),
      mediaType: AttachmentMediaType.png,
      sectionIndex: sectionIndex,
      page: sectionIndex + 1,
      order: index,
      caption: caption,
      context: context,
    );
  }

  ModelCapabilities caps() => const ModelCapabilities(
    contextWindowTokens: 400000,
    contextSource: CapabilitySource.officialCatalog,
    maxOutputTokens: 8192,
    supportsVision: true,
  );

  /// Строка каталога ровно в том виде, в каком её собирает план: id `imgN`.
  String catalogLineFor(DocumentImage image, int position) =>
      imageCatalogLine(image.withId('img${position + 1}'));

  int catalogTokensOf(List<DocumentImage> images) {
    var total = 0;
    for (var index = 0; index < images.length; index++) {
      total += estimator.estimateText(catalogLineFor(images[index], index));
    }
    return total;
  }

  /// Текст и отправленные вложения частей — **без** каталога: каталог
  /// проверяется отдельно по независимо посчитанным строкам.
  int textAndImageTokens(GenerationPlan plan) =>
      plan.inputPlan!.parts.fold<int>(
        0,
        (int sum, part) =>
            sum +
            part.tokens +
            part.images.fold<int>(0, (int i, image) => i + image.tokens),
      );

  /// `D` плана: сумма материалов частей (текст + каталог + вложения).
  int partTokens(GenerationPlan plan) => plan.inputPlan!.parts.fold<int>(
    0,
    (int sum, part) => sum + part.totalMaterialTokens,
  );

  const String material =
      'Фотосинтез — процесс преобразования света в энергию.';

  test('без изображений: каталог не добавляет токенов', () {
    final GenerationPlan plan = builder.build(
      documents: <ParsedDocument>[
        docOf('лекция.docx', <String>[material]),
      ],
      capabilities: caps(),
    );
    expect(plan.chunks, hasLength(1));
    expect(
      plan.estimate.catalogTokens,
      0,
      reason: 'нет изображений — каталог пуст',
    );
    expect(
      plan.inputPlan!.materialTokens,
      textAndImageTokens(plan),
      reason: 'D = текст + вложения, каталога нет',
    );
  });

  test('одно изображение: токены каталога входят в D', () {
    final List<DocumentImage> images = <DocumentImage>[imageOf()];
    final GenerationPlan plan = builder.build(
      documents: <ParsedDocument>[
        docOf('лекция.docx', <String>[material], images: images),
      ],
      capabilities: caps(),
    );
    final int expectedCatalog = catalogTokensOf(images);
    expect(expectedCatalog, greaterThan(0));
    expect(
      plan.estimate.catalogTokens,
      expectedCatalog,
      reason: 'строка каталога — часть запроса, значит и часть D',
    );
    expect(
      plan.inputPlan!.materialTokens,
      textAndImageTokens(plan) + expectedCatalog,
      reason: 'D = текст + вложения + каталог (§3.4)',
    );
  });

  test('несколько изображений: каталог суммируется по строкам', () {
    final List<DocumentImage> images = <DocumentImage>[
      imageOf(index: 0),
      imageOf(index: 1, caption: 'Таблица'),
      imageOf(index: 2, caption: 'График'),
    ];
    final GenerationPlan plan = builder.build(
      documents: <ParsedDocument>[
        docOf('лекция.docx', <String>[material], images: images),
      ],
      capabilities: caps(),
    );
    final int expectedCatalog = catalogTokensOf(images);
    expect(
      plan.estimate.catalogTokens,
      expectedCatalog,
      reason: 'каталог трёх картинок — три строки',
    );
    expect(
      plan.inputPlan!.materialTokens,
      textAndImageTokens(plan) + expectedCatalog,
    );
    expect(plan.inputPlan!.materialTokens, partTokens(plan));
    // Бюджет входа обязан включать каталог: без него `inputTokens` занижен.
    final int expectedCounted =
        plan.inputPlan!.fixedTokens + plan.inputPlan!.materialTokens;
    expect(
      plan.inputPlan!.budget.inputTokens,
      expectedCounted + (expectedCounted * 0.10).ceil(),
      reason: 'inputTokens = ceil((P + D) × (1 + m)), где D включает каталог',
    );
  });

  test('длинные подписи и контекст увеличивают каталог и вход', () {
    final String longContext = 'Очень подробное описание рисунка. ' * 5;
    final List<DocumentImage> shortImages = <DocumentImage>[imageOf()];
    final List<DocumentImage> longImages = <DocumentImage>[
      imageOf(
        caption: 'Подробная схема процесса фотосинтеза',
        context: longContext,
      ),
    ];
    GenerationPlan planFor(List<DocumentImage> images) => builder.build(
      documents: <ParsedDocument>[
        docOf('лекция.docx', <String>[material], images: images),
      ],
      capabilities: caps(),
    );
    final GenerationPlan shortPlan = planFor(shortImages);
    final GenerationPlan longPlan = planFor(longImages);
    expect(
      longPlan.estimate.catalogTokens,
      greaterThan(shortPlan.estimate.catalogTokens),
      reason: 'длинная подпись/контекст — больше токенов каталога',
    );
    expect(
      longPlan.inputPlan!.materialTokens - shortPlan.inputPlan!.materialTokens,
      longPlan.estimate.catalogTokens - shortPlan.estimate.catalogTokens,
      reason: 'рост D равен росту каталога (текст одинаковый)',
    );
  });

  test('каталог в exact-режиме: нативный подсчёт не пересчитывается', () {
    final List<DocumentImage> images = <DocumentImage>[imageOf()];
    final GenerationPlan plan = builder.build(
      documents: <ParsedDocument>[
        docOf('лекция.docx', <String>[material], images: images),
      ],
      capabilities: caps(),
      nativeCount: const NativeInputCount(
        tokens: 500,
        source: 'count_tokens:anthropic',
      ),
    );
    expect(plan.inputPlan!.inputTokenSource, 'count_tokens:anthropic');
    expect(
      plan.inputPlan!.budget.inputTokens,
      500 + (500 * 0.03).ceil(),
      reason: 'нативный счётчик уже посчитал каталог; второй раз не добавляем',
    );
    expect(
      plan.estimate.catalogTokens,
      catalogTokensOf(images),
      reason: 'для «Подробнее» видно, сколько каталога в запросе',
    );
  });

  test('каталог в fragmentе: каждый фрагмент несёт каталог своих картинок', () {
    final List<DocumentImage> images = <DocumentImage>[
      imageOf(index: 0),
      imageOf(index: 1, sectionIndex: 1, caption: 'Второй раздел'),
    ];
    final GenerationPlan plan = builder.build(
      documents: <ParsedDocument>[
        docOf('лекция.docx', <String>[
          material,
          '$material Продолжение описания.',
        ], images: images),
      ],
      capabilities: const ModelCapabilities(
        // Окно намеренно маленькое: материал не помещается целиком.
        contextWindowTokens: 900,
        contextSource: CapabilitySource.userConfigured,
        maxOutputTokens: 400,
        supportsVision: true,
      ),
    );
    expect(
      plan.inputPlan!.isFragmented,
      isTrue,
      reason: 'материал не помещается в окно',
    );
    final int expectedCatalog = catalogTokensOf(images);
    expect(
      plan.estimate.catalogTokens,
      expectedCatalog,
      reason: 'каталог всех изображений распределён по фрагментам',
    );
    expect(
      plan.inputPlan!.materialTokens,
      textAndImageTokens(plan) + expectedCatalog,
      reason: 'D фрагментов включает каталог их картинок',
    );
    expect(plan.inputPlan!.materialTokens, partTokens(plan));
  });
}
