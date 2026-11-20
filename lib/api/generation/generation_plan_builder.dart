/// Сборка плана адаптивной генерации из материалов приложения (раздел I.11
/// аудита TASK 01).
///
/// Слой между уже существующими моделями (`ParsedDocument`,
/// [GenerationAttachment], `DocumentImage`) и чистым планировщиком:
///
/// 1. строит перечень единиц содержимого [ContentInventory] (документ →
///    раздел → абзац; изображения с привязкой к разделу и странице; вложения
///    страницами);
/// 2. считает фиксированную обвязку запроса (системный промпт, JSON-схема
///    ответа, обёртка пользовательского сообщения) тем же оценщиком, что и
///    планировщик;
/// 3. вызывает [GenerationChunkPlanner.plan] и возвращает [GenerationPlan].
///
/// Ничего не отправляет и не меняет production-путь генерации: подключение к
/// `GenerationPipeline` — следующий этап. Строка каталога `<images>` берётся из
/// существующего `imageCatalogLine`, поэтому оценка каталога совпадает с
/// форматом реального запроса.
library;

import 'dart:convert';

import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Собирает [GenerationPlan] из разобранных документов и вложений.
class GenerationPlanBuilder {
  /// Создаёт сборщик плана.
  const GenerationPlanBuilder({this.planner = const GenerationChunkPlanner()});

  /// Планировщик (несёт общий оценщик токенов).
  final GenerationChunkPlanner planner;

  /// Оценщик единиц содержимого (тот же, что у планировщика).
  ContentTokenEstimator get estimator => planner.estimator;

  /// Строит перечень единиц содержимого без вызова планировщика.
  ///
  /// Токены текста и изображений считаются [estimator] (и
  /// [imageTokenModel], если модель его предоставляет): планировщик получает
  /// готовые значения и не создаёт вторую систему оценки.
  ContentInventory inventoryOf({
    required List<ParsedDocument> documents,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
    List<DocumentImage> documentImages = const <DocumentImage>[],
    ImageTokenModel? imageTokenModel,
  }) {
    final Map<String, List<DocumentImage>> extraByFile =
        <String, List<DocumentImage>>{};
    for (final DocumentImage image in documentImages) {
      (extraByFile[image.fileName] ??= <DocumentImage>[]).add(image);
    }
    final List<DocumentUnit> documentUnits = <DocumentUnit>[];
    for (final ParsedDocument parsed in documents) {
      final List<DocumentImage> images = <DocumentImage>[
        ...parsed.images,
        ...?extraByFile.remove(parsed.fileName),
      ];
      documentUnits.add(
        _documentUnit(parsed, images, imageTokenModel: imageTokenModel),
      );
    }
    final List<OrphanImageUnit> orphans = <OrphanImageUnit>[];
    extraByFile.forEach((String fileName, List<DocumentImage> images) {
      for (var index = 0; index < images.length; index++) {
        orphans.add(
          OrphanImageUnit(
            image: ImageRef(
              id: contentImageId(fileName, index),
              image: images[index],
              tokens: estimator
                  .estimateImage(
                    width: images[index].width,
                    height: images[index].height,
                    bytes: images[index].bytes.length,
                    model: imageTokenModel,
                  )
                  .tokens,
            ),
          ),
        );
      }
    });
    return ContentInventory(
      documents: documentUnits,
      attachments: _attachmentUnits(attachments, imageTokenModel),
      orphanImages: orphans,
    );
  }

  /// Строит план генерации по материалам.
  ///
  /// [systemPrompt] и [responseSchema] — фиксированная обвязка: системный
  /// промпт и каноническая JSON-схема ответа. Обёртка пользовательского
  /// сообщения считается существующим `buildGenerationUserContent` (без
  /// материалов и каталога), поэтому оценка совпадает с форматом запроса.
  /// [requestedCards] по умолчанию берётся из пожеланий существующим
  /// `requestedCardCount` — без искусственного среза: заказ сохраняется в
  /// плане, а расхождение с выполнимым количеством отражается предупреждением.
  GenerationPlan build({
    required List<ParsedDocument> documents,
    required ModelCapabilities capabilities,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
    List<DocumentImage> documentImages = const <DocumentImage>[],
    String? wishes,
    int? requestedCards,
    String systemPrompt = systemPromptGenRuV8,
    Map<String, Object?> responseSchema = canonicalCardsResponseSchema,
    GenerationOverheadTokens? overhead,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
  }) {
    final ContentInventory inventory = inventoryOf(
      documents: documents,
      attachments: attachments,
      documentImages: documentImages,
      imageTokenModel: capabilities.imageTokens,
    );
    final GenerationOverheadTokens fixed =
        overhead ??
        GenerationOverheadTokens(
          systemPromptTokens: estimator.estimateText(systemPrompt),
          schemaTokens: estimator.estimateText(jsonEncode(responseSchema)),
          wrapperTokens: estimator.estimateText(
            buildGenerationUserContent(
              materialsText: '',
              wishes: wishes,
              limit: 999,
              imagesCatalog: '',
            ),
          ),
          outlineTokens: estimator.estimateText(_outlineOf(documents)),
          taskTailTokens: estimator.estimateText(_taskTailTemplate),
        );
    return planner.plan(
      inventory: inventory,
      capabilities: capabilities,
      overhead: fixed,
      requestedCards: requestedCards ?? requestedCardCount(wishes),
      budgetConfig: budgetConfig,
      catalogLineBuilder: planner.catalogLineBuilder ?? _catalogLine,
      wishes: wishes,
    );
  }

  /// Строит план генерации без материалов (prompt-only, ADR-024).
  ///
  /// Использует **ту же** машинерию, что и план по материалам (§0.11):
  /// [GenerationChunkPlanner] → [InputPlanner] → [OutputBatchPlanner]. Тема
  /// входит в обвязку каждого запроса, распределения по разделам нет;
  /// обёртка здесь считается **без** темы, поэтому двойного счёта нет.
  GenerationPlan buildPromptOnly({
    required PromptOnlyRequest request,
    required ModelCapabilities capabilities,
    String systemPrompt = systemPromptGenRuV8,
    Map<String, Object?> responseSchema = canonicalCardsResponseSchema,
    GenerationOverheadTokens? overhead,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
  }) {
    assert(!request.isEmpty, 'Prompt-only план требует непустую тему');
    final GenerationOverheadTokens fixed =
        overhead ??
        GenerationOverheadTokens(
          systemPromptTokens: estimator.estimateText(systemPrompt),
          schemaTokens: estimator.estimateText(jsonEncode(responseSchema)),
          wrapperTokens: estimator.estimateText(
            buildGenerationUserContent(
              materialsText: '',
              wishes: null,
              limit: 999,
              imagesCatalog: '',
            ),
          ),
        );
    return planner.plan(
      inventory: ContentInventory.empty,
      capabilities: capabilities,
      overhead: fixed,
      requestedCards: request.requestedCards,
      allowPromptOnly: true,
      wishes: request.prompt,
      budgetConfig: budgetConfig,
      catalogLineBuilder: planner.catalogLineBuilder,
    );
  }

  /// Строка каталога `<images>` в формате реального запроса.
  static String _catalogLine(ImageRef image, int index) {
    return imageCatalogLine(
      image.image.withId('$kDocumentImageIdPrefix${index + 1}'),
    );
  }

  /// Хвост `<task>`: изменяемая часть запроса (ADR-040 §7).
  static const String _taskTailTemplate =
      '<task><part>1 из 2</part><focus>s1, s2</focus>'
      '<cards>40</cards></task>';

  /// Компактное оглавление всех заголовков (оценка резерва fragmented).
  static String _outlineOf(List<ParsedDocument> documents) {
    final List<String> titles = <String>[
      for (final ParsedDocument document in documents)
        for (final ParsedSection section in document.sections)
          if (section.title != null && section.title!.trim().isNotEmpty)
            section.title!.trim(),
    ];
    if (titles.isEmpty) return '';
    return 'Оглавление: ${titles.join(' · ')}';
  }

  DocumentUnit _documentUnit(
    ParsedDocument parsed,
    List<DocumentImage> images, {
    required ImageTokenModel? imageTokenModel,
  }) {
    final String documentId = contentDocumentId(parsed.fileName);
    final List<ImageRef> imageRefs = <ImageRef>[
      for (var index = 0; index < images.length; index++)
        ImageRef(
          id: contentImageId(parsed.fileName, index),
          image: images[index],
          sectionId:
              images[index].sectionIndex >= 0 &&
                  images[index].sectionIndex < parsed.sections.length
              ? contentSectionId(documentId, images[index].sectionIndex)
              : null,
          tokens: estimator
              .estimateImage(
                width: images[index].width,
                height: images[index].height,
                bytes: images[index].bytes.length,
                model: imageTokenModel,
              )
              .tokens,
        ),
    ];
    final List<SectionUnit> sections = <SectionUnit>[
      for (var index = 0; index < parsed.sections.length; index++)
        _sectionUnit(parsed, index, documentId, imageRefs),
    ];
    return DocumentUnit(
      id: documentId,
      fileName: parsed.fileName,
      format: parsed.format,
      pageCount: parsed.metadata.pageCount ?? parsed.metadata.slideCount,
      sections: sections,
      catalog: DocumentCatalog(documentId: documentId, images: imageRefs),
    );
  }

  SectionUnit _sectionUnit(
    ParsedDocument parsed,
    int index,
    String documentId,
    List<ImageRef> images,
  ) {
    final ParsedSection section = parsed.sections[index];
    final String text = parsed.text.substring(section.start, section.end);
    final String sectionId = contentSectionId(documentId, index);
    return SectionUnit(
      id: sectionId,
      index: index,
      title: section.title,
      text: text,
      tokens: estimator.estimateText(text),
      pieces: _pieces(parsed.fileName, sectionId, text, section.start),
      images: <ImageRef>[
        for (final ImageRef image in images)
          if (image.sectionIndex == index) image,
      ],
    );
  }

  /// Делит текст раздела на абзацы, сохраняя точное покрытие.
  ///
  /// Каждый фрагмент включает свой разделитель (пустую строку), поэтому
  /// конкатенация текста фрагментов равна тексту раздела, а `start/end` —
  /// смещения в тексте документа.
  List<TextPiece> _pieces(
    String fileName,
    String sectionId,
    String text,
    int sectionStart,
  ) {
    if (text.isEmpty) return const <TextPiece>[];
    final List<int> ends = <int>[];
    for (final Match match in _paragraphBoundary.allMatches(text)) {
      final int end = match.end;
      if (end > 0 &&
          end < text.length &&
          end > (ends.isEmpty ? 0 : ends.last)) {
        ends.add(end);
      }
    }
    ends.add(text.length);
    final List<TextPiece> pieces = <TextPiece>[];
    var start = 0;
    for (var index = 0; index < ends.length; index++) {
      final int end = ends[index];
      if (end <= start) continue;
      final String pieceText = text.substring(start, end);
      pieces.add(
        TextPiece(
          id: contentTextPieceId(sectionId, index),
          kind: TextPieceKind.paragraph,
          order: index,
          text: pieceText,
          start: sectionStart + start,
          end: sectionStart + end,
          tokens: estimator.estimateText(pieceText),
        ),
      );
      start = end;
    }
    return pieces;
  }

  /// Группирует вложения в единицы: страницы одного файла (groupKey) — вместе.
  List<AttachmentUnit> _attachmentUnits(
    List<GenerationAttachment> attachments,
    ImageTokenModel? imageTokenModel,
  ) {
    final List<String> order = <String>[];
    final Map<String, List<GenerationAttachment>> groups =
        <String, List<GenerationAttachment>>{};
    for (var index = 0; index < attachments.length; index++) {
      final GenerationAttachment attachment = attachments[index];
      final String? groupKey =
          attachment.groupKey == null || attachment.groupKey!.isEmpty
          ? null
          : attachment.groupKey;
      final String key = groupKey ?? 'file:${attachment.fileName}#$index';
      if (!groups.containsKey(key)) {
        order.add(key);
        groups[key] = <GenerationAttachment>[];
      }
      groups[key]!.add(attachment);
    }
    final List<AttachmentUnit> units = <AttachmentUnit>[];
    for (final String key in order) {
      final List<GenerationAttachment> group = groups[key]!;
      final GenerationAttachment first = group.first;
      final String? groupKey = first.groupKey == null || first.groupKey!.isEmpty
          ? null
          : first.groupKey;
      final String unitId = contentAttachmentId(
        first.fileName,
        groupKey: groupKey ?? first.fileName,
      );
      units.add(
        AttachmentUnit(
          id: unitId,
          fileName: first.fileName,
          mediaType: first.mediaType,
          groupKey: groupKey,
          pages: <PageUnit>[
            for (final GenerationAttachment attachment in group)
              PageUnit(
                id: contentPageId(unitId, attachment.pageNumber),
                pageNumber: attachment.pageNumber,
                bytes: attachment.bytes,
                tokens: estimator
                    .estimateImage(
                      bytes: attachment.bytes.length,
                      model: imageTokenModel,
                    )
                    .tokens,
              ),
          ],
        ),
      );
    }
    return units;
  }
}

/// Граница абзаца внутри раздела: пустая строка (как в чанкере).
final RegExp _paragraphBoundary = RegExp(r'\n[ \t]*\n+');
