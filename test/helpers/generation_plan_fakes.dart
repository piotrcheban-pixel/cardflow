import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// Строит [GenerationPlan] из старого списка [GenerationChunk] для тестов
/// пайплайна (production строит план планировщиком, старый чанкер не
/// используется). Материалы и лимиты сохраняются как заданы.
GenerationPlan testPlanFromChunks(
  List<GenerationChunk> chunks, {
  int? requestedCards,
  GenerationMode mode = GenerationMode.materials,
  String? prompt,
  List<PlannedImage> images = const <PlannedImage>[],
}) {
  final List<PlannedChunk> planned = <PlannedChunk>[];
  for (final GenerationChunk chunk in chunks) {
    final String text = chunk.materialsText;
    final bool hasText = text.trim().isNotEmpty;
    final List<DocumentImage> parts = chunk.imageParts.isNotEmpty
        ? chunk.imageParts
        : chunk.documentImages;
    final List<DocumentImage> catalog = chunk.catalogOnly;
    final List<GenerationAttachment> attachments = chunk.images;
    final bool hasParts = parts.isNotEmpty || attachments.isNotEmpty;
    final ChunkKind kind = mode == GenerationMode.promptOnly
        ? ChunkKind.promptOnly
        : hasText
        ? (hasParts ? ChunkKind.mixed : ChunkKind.text)
        : hasParts
        ? ChunkKind.images
        : ChunkKind.catalog;
    final List<UnitSpan> units;
    if (!hasText) {
      units = const <UnitSpan>[];
    } else if (chunk.unitIds.length > 1) {
      // Несколько единиц: делим текст поровну (смещения нужны для дробления).
      units = <UnitSpan>[];
      final int step = (text.length / chunk.unitIds.length).ceil();
      var start = 0;
      for (var index = 0; index < chunk.unitIds.length; index++) {
        final int end = index == chunk.unitIds.length - 1
            ? text.length
            : (start + step).clamp(start, text.length);
        units.add(
          UnitSpan(
            unitId: chunk.unitIds[index],
            start: start,
            end: end,
            tokens: 0,
          ),
        );
        start = end;
      }
    } else {
      units = <UnitSpan>[
        UnitSpan(
          unitId: chunk.unitIds.isNotEmpty
              ? chunk.unitIds.first
              : 'test:${chunk.index}',
          start: 0,
          end: text.length,
          tokens: 0,
        ),
      ];
    }
    planned.add(
      PlannedChunk(
        index: chunk.index,
        kind: kind,
        units: units,
        imageParts: parts,
        imagePartIds: <String>[
          for (var index = 0; index < parts.length; index++)
            'img:${parts[index].fileName}#$index',
        ],
        catalogOnly: catalog,
        catalogOnlyIds: <String>[
          for (var index = 0; index < catalog.length; index++)
            'img:${catalog[index].fileName}#c$index',
        ],
        attachments: attachments,
        textTokens: 0,
        imageTokens: 0,
        bodyBytes: 0,
        limit: chunk.limit < 1 ? 1 : chunk.limit,
        splitDepth: chunk.splitDepth,
        materialsText: mode == GenerationMode.promptOnly ? '' : text,
      ),
    );
  }
  return GenerationPlan(
    validity: const PlanValidity.valid(),
    estimate: GenerationEstimate(
      inputTextTokens: 0,
      imageTokens: 0,
      fixedPromptTokens: 0,
      wrapperTokens: 0,
      schemaTokens: 0,
      catalogTokens: 0,
      reservedOutputTokens: 0,
      expectedOutputTokens: 0,
      totalTokens: 1,
      plannedChunks: planned.length,
      plannedRequests: planned.length,
      retryAllowanceRequests: 0,
      pricingState: PricingState.unknown,
      estimatorVersion: 'test/1',
    ),
    budget: GenerationBudget.compute(
      capabilities: const ModelCapabilities(),
      limit: 1,
      systemPromptTokens: 0,
      schemaTokens: 0,
      wrapperTokens: 0,
      catalogTokens: 0,
      imageTokens: 0,
    ).trace,
    chunks: planned,
    images: images,
    requestedCards: requestedCards ?? 0,
    mode: mode,
    promptOnlyPrompt: mode == GenerationMode.promptOnly
        ? (prompt ?? 'Тема')
        : null,
  );
}

/// Фабрика плана для [GenerationPipeline]: всегда возвращает [chunks].
GenerationPlanFactory fixedPlanFactory(
  List<GenerationChunk> chunks, {
  int? requestedCards,
  GenerationMode mode = GenerationMode.materials,
  String? prompt,
  List<PlannedImage> images = const <PlannedImage>[],
}) {
  final GenerationPlan plan = testPlanFromChunks(
    chunks,
    requestedCards: requestedCards,
    mode: mode,
    prompt: prompt,
    images: images,
  );
  return (_, _) => plan;
}
