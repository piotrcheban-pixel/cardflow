/// Адаптивный планировщик генерации (ADR-040).
///
/// Три независимых решения, собранные в один план:
/// 1. [InputPlanner] — весь документ целиком или минимальное число частей
///    (только по бюджету входа и резерву вывода, без числа карточек);
/// 2. [CardAllocator] — распределение заказа по разделам по насыщенности;
/// 3. [OutputBatchPlanner] — партии (API-запросы), `focus` и лимит карточек.
///
/// `GenerationChunkPlanner.plan` сохраняет прежний публичный API: он собирает
/// [GenerationPlan] из перечня единиц содержимого и возможностей модели.
/// Домен не зависит от Flutter.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_continuity.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/output_batch_planner.dart';

/// Строка каталога `<images>` для изображения [image] с порядковым номером
/// [index] (0 — первое изображение документа).
typedef ImageCatalogLineBuilder = String Function(ImageRef image, int index);

/// Допущения и технические предохранители планировщика.
final class GenerationChunkPlannerConfig {
  /// Создаёт конфигурацию.
  ///
  /// [softTargetMaterialTokensPerCard] и [minSoftTargetMaterialTokens] —
  /// legacy-поля мягкой цели (ADR-040 §1: больше не режут материал, оставлены
  /// ради обратной совместимости вызовов); [assumedMaxImagesPerChunk] и
  /// байтовые лимиты — конфигурационные допущения приложения, когда
  /// модель/аккаунт лимитов не сообщают.
  const GenerationChunkPlannerConfig({
    this.softTargetMaterialTokensPerCard = 6000,
    this.minSoftTargetMaterialTokens = 512,
    this.assumedMaxImagesPerChunk = 8,
    this.assumedMaxImageBytesPerImage = 10 * 1024 * 1024,
    this.assumedMaxImageBytesPerChunk = 24 * 1024 * 1024,
    this.assumedMaxRequestBytes = 32 * 1024 * 1024,
    this.jsonBodyOverheadBytes = 1024,
    this.maxChunks = 512,
    this.maxSplitDepth = 3,
    this.retryAllowanceRequests = 0,
    this.planning = const GenerationPlanningConfig(),
  }) : assert(softTargetMaterialTokensPerCard > 0),
       assert(minSoftTargetMaterialTokens > 0),
       assert(assumedMaxImagesPerChunk > 0),
       assert(assumedMaxImageBytesPerImage > 0),
       assert(assumedMaxImageBytesPerChunk > 0),
       assert(assumedMaxRequestBytes > 0),
       assert(maxChunks > 0, 'Предохранитель числа фрагментов должен быть > 0'),
       assert(maxSplitDepth >= 0),
       assert(retryAllowanceRequests >= 0);

  /// Legacy: мягкая цель материала на карточку (ADR-040 §1 её не использует).
  final int softTargetMaterialTokensPerCard;

  /// Legacy: минимальная мягкая цель материала.
  final int minSoftTargetMaterialTokens;

  /// Допущение: максимум image-частей в запросе.
  final int assumedMaxImagesPerChunk;

  /// Допущение: максимум байт одного изображения.
  final int assumedMaxImageBytesPerImage;

  /// Допущение: максимум байт изображений запроса.
  final int assumedMaxImageBytesPerChunk;

  /// Допущение: максимум байт тела запроса.
  final int assumedMaxRequestBytes;

  /// Запас тела запроса (JSON-обёртка), байт.
  final int jsonBodyOverheadBytes;

  /// Технический предохранитель: максимум частей входа на запуск.
  final int maxChunks;

  /// Технический предохранитель: глубина дробления при восстановлении.
  final int maxSplitDepth;

  /// Допуск на повторы (не входит в плановые запросы).
  final int retryAllowanceRequests;

  /// Коэффициенты бюджета/вывода ADR-040 §2.
  final GenerationPlanningConfig planning;
}

/// Фиксированная обвязка запроса, токенов (P).
final class GenerationOverheadTokens {
  /// Создаёт обвязку.
  const GenerationOverheadTokens({
    this.systemPromptTokens = 0,
    this.schemaTokens = 0,
    this.wrapperTokens = 0,
    this.outlineTokens = 0,
    this.taskTailTokens = 0,
    this.fixedBytes = 0,
  });

  /// Пустая обвязка.
  static const GenerationOverheadTokens none = GenerationOverheadTokens();

  /// Системный промпт.
  final int systemPromptTokens;

  /// Каноническая схема ответа.
  final int schemaTokens;

  /// Обёртка пользовательского сообщения (без `<materials>`).
  final int wrapperTokens;

  /// Резерв на компактное оглавление (только при fragmented).
  final int outlineTokens;

  /// Хвост `<task>` (part/focus/cards).
  final int taskTailTokens;

  /// Байты неподвижной обвязки запроса: системный промпт, JSON-схема ответа,
  /// обёртка сообщения (`<materials>`/`<images>`/`<wishes>`/`<task>`).
  ///
  /// Считается сборщиком плана по реальным строкам и входит в `requestBytes`:
  /// без него оценка тела была ниже сериализованного payload на десятки КБ, и
  /// лимит `maxRequestBytes` мог быть превышен на реальном запросе.
  final int fixedBytes;

  /// Суммарная служебная часть `P`.
  int get fixedTokens =>
      systemPromptTokens + schemaTokens + wrapperTokens + taskTailTokens;

  @override
  String toString() =>
      'GenerationOverheadTokens($systemPromptTokens + $schemaTokens + '
      '$wrapperTokens + $outlineTokens + $taskTailTokens)';
}

/// Планировщик: бюджет, части, распределение карточек и партии.
final class GenerationChunkPlanner {
  /// Создаёт планировщик.
  const GenerationChunkPlanner({
    this.estimator = const HeuristicContentTokenEstimator(),
    this.config = const GenerationChunkPlannerConfig(),
    this.catalogLineBuilder,
  });

  /// Единый оценщик единиц содержимого.
  final ContentTokenEstimator estimator;

  /// Допущения и предохранители.
  final GenerationChunkPlannerConfig config;

  /// Построитель строк каталога `<images>`; `null` — приближение по полям.
  final ImageCatalogLineBuilder? catalogLineBuilder;

  /// Строит план по перечню содержимого и возможностям модели.
  ///
  /// [requestedCards] распределяется [CardAllocator], но **не влияет** на
  /// разбиение входа: [InputPlanner] получает только бюджет и резерв вывода.
  /// [wishes] нужны для подъёма веса разделов, совпавших с пожеланиями.
  GenerationPlan plan({
    required ContentInventory inventory,
    required ModelCapabilities capabilities,
    GenerationOverheadTokens overhead = GenerationOverheadTokens.none,
    int? requestedCards,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
    ImageCatalogLineBuilder? catalogLineBuilder,
    String? wishes,
    bool allowPromptOnly = false,
    int? exactInputTokens,
    String? inputTokenSource,
  }) {
    assert(
      requestedCards == null || requestedCards > 0,
      'Заказ карточек должен быть положительным или null',
    );
    final GenerationPlanningConfig planning = config.planning;
    final ModelLimits limits = modelLimitsFromCapabilities(capabilities);
    final _InventoryData data = _inventoryData(inventory, estimator);
    final bool promptOnly =
        data.sections.isEmpty &&
        data.attachments.isEmpty &&
        data.orphanImages.isEmpty;
    if (promptOnly &&
        (!allowPromptOnly || wishes == null || wishes.trim().isEmpty)) {
      return _emptyPlan(limits: limits, overhead: overhead);
    }
    final int outputCap = planning.outputCapFor(limits);
    // §3.4: reasoning-модель тратит часть `max_tokens` на рассуждение. Резерв
    // добавляется явно (допущение) и исчезает после калибровки по `usage`.
    final int reasoningReserve =
        limits.isReasoningModel.value == true && planning.reasoningReserveTokens > 0
        ? planning.reasoningReserveTokens
        : 0;
    final int desired = math.min(
      outputCap,
      planning.desiredOutputTokens(
            requestedCards: requestedCards,
            maxOutputTokens: outputCap,
          ) +
          reasoningReserve,
    );

    final InputPlan inputPlan;
    var promptTokens = 0;
    var promptCardsCap = 0;
    var promptBodyBytes = planning.jsonBodyOverheadBytes;
    if (promptOnly) {
      // Prompt-only идёт по той же машинерии (§0.11): тема — часть обвязки
      // каждого запроса, распределения по разделам нет, заказ делится только
      // на партии [OutputBatchPlanner].
      final String topic = wishes!.trim();
      promptTokens = math.max(1, estimator.estimateText(topic));
      final int promptBytes = utf8.encode(topic).length;
      final int cardsCap = budgetCardsPerRequestCap(capabilities, budgetConfig);
      promptCardsCap = cardsCap;
      final int targetCards = math.max(1, requestedCards ?? cardsCap);
      // Безопасное деление вверх: `(a + b - 1) ~/ b` переполняет int на
      // `requestedCards == int.max`; остаток считается отдельно.
      final int chunksByCards = targetCards ~/ cardsCap;
      final int estimatedChunks =
          chunksByCards + (targetCards % cardsCap == 0 ? 0 : 1);
      // Сводка уже созданных карточек добавляется со второго запроса; её
      // бюджет резервируется заранее (TASK 03, D13).
      final int continuationReserve = estimatedChunks > 1
          ? kPromptOnlyContinuationMaxTokens
          : 0;
      final int fixedTokens =
          overhead.fixedTokens + promptTokens + continuationReserve;
      promptBodyBytes =
          promptBytes +
          overhead.fixedBytes +
          planning.jsonBodyOverheadBytes +
          (continuationReserve > 0 ? kPromptOnlyContinuationReserveBytes : 0);
      inputPlan = InputPlanner(config: planning).plan(
        sections: const <InputSection>[],
        limits: limits,
        fixedTokens: fixedTokens,
        desiredOutputTokens: desired,
        accuracy: exactInputTokens == null
            ? InputAccuracy.estimated
            : InputAccuracy.exact,
        exactInputTokens: exactInputTokens,
        promptOnlyRequestBytes: promptBodyBytes,
        inputTokenSource: inputTokenSource ?? 'estimate:${estimator.version}',
        reasoningReserveTokens: reasoningReserve,
      );
      if (inputPlan.budget.payloadExceeded) {
        return _invalidPlan(
          PlanInvalidReason.payloadTooLarge,
          inputPlan: inputPlan,
          limits: limits,
          overhead: overhead,
          requestedCards: requestedCards,
          mode: GenerationMode.promptOnly,
          promptText: topic,
        );
      }
      if (inputPlan.budget.contextExceeded || inputPlan.maxTokens < 1) {
        return _invalidPlan(
          PlanInvalidReason.contextWindowTooSmall,
          inputPlan: inputPlan,
          limits: limits,
          overhead: overhead,
          requestedCards: requestedCards,
          mode: GenerationMode.promptOnly,
          promptText: topic,
        );
      }
      if (estimatedChunks > config.maxChunks) {
        return _invalidPlan(
          PlanInvalidReason.tooManyChunks,
          inputPlan: inputPlan,
          limits: limits,
          overhead: overhead,
          requestedCards: requestedCards,
          mode: GenerationMode.promptOnly,
          promptText: topic,
        );
      }
    } else if (data.sections.isEmpty) {
      inputPlan = _attachmentsOnlyPlan(
        data: data,
        limits: limits,
        overhead: overhead,
        desired: desired,
      );
    } else {
      inputPlan = InputPlanner(config: planning).plan(
        sections: data.sections,
        limits: limits,
        fixedTokens: overhead.fixedTokens,
        fixedBytes: overhead.fixedBytes,
        desiredOutputTokens: desired,
        reasoningReserveTokens: reasoningReserve,
        accuracy: exactInputTokens == null
            ? InputAccuracy.estimated
            : InputAccuracy.exact,
        outlineReserveTokens: overhead.outlineTokens,
        orphanImages: data.orphanImages,
        exactInputTokens: exactInputTokens,
        inputTokenSource: inputTokenSource ?? 'estimate:${estimator.version}',
      );
    }

    if (!capabilities.supportsVision && data.hasVisionPayload) {
      return _invalidPlan(
        PlanInvalidReason.imagesWithoutVision,
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        requestedCards: requestedCards,
      );
    }
    if (inputPlan.partCount > config.maxChunks) {
      return _invalidPlan(
        PlanInvalidReason.tooManyChunks,
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        requestedCards: requestedCards,
      );
    }
    if (inputPlan.budget.payloadExceeded) {
      return _invalidPlan(
        PlanInvalidReason.payloadTooLarge,
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        requestedCards: requestedCards,
      );
    }
    if (_hasUnplaceableUnit(data, inputPlan)) {
      return _invalidPlan(
        PlanInvalidReason.unitTooLarge,
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        requestedCards: requestedCards,
      );
    }
    if (inputPlan.budget.contextTokens != null &&
        overhead.fixedTokens >= inputPlan.budget.contextTokens! &&
        !promptOnly) {
      return _invalidPlan(
        PlanInvalidReason.contextWindowTooSmall,
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        requestedCards: requestedCards,
      );
    }

    final CardAllocation allocation = data.sections.isEmpty
        ? _syntheticAllocation(
            requestedCards: requestedCards,
            batchCap: planning.cardsFor(inputPlan.maxTokens),
          )
        : const CardAllocator().allocate(
            sections: _allocationSections(data, wishes),
            requestedCards: requestedCards,
          );
    final List<PlannedBatch> batches = promptOnly
        ? OutputBatchPlanner(config: planning).plan(
            input: inputPlan,
            allocation: allocation,
            maxTokensPerBatch: inputPlan.maxTokens,
            promptOnlyRequestedCards: requestedCards ?? promptCardsCap,
            // Prompt-only сохраняет прежний консервативный лимит карточек на
            // запрос (`budgetCardsPerRequestCap`): у него нет материалов, а
            // качество партии без фокуса по разделам проверено этим числом.
            maxCardsPerRequest: math.min(
              limits.maxCardsPerRequest.value ?? promptCardsCap,
              promptCardsCap,
            ),
          )
        : data.sections.isEmpty
        ? _batchesWithoutSections(
            inputPlan: inputPlan,
            allocation: allocation,
            planning: planning,
            reasoningReserveTokens: reasoningReserve,
          )
        : OutputBatchPlanner(config: planning).plan(
            input: inputPlan,
            allocation: allocation,
            maxTokensPerBatch: inputPlan.maxTokens,
            promptOnlyRequestedCards: requestedCards,
            maxCardsPerRequest: limits.maxCardsPerRequest.value,
            reasoningReserveTokens: reasoningReserve,
          );

    final Set<PlanWarningCode> warnings = <PlanWarningCode>{
      ...inputPlan.warnings,
      if (allocation.belowRequested) PlanWarningCode.requestedAbovePlan,
      if (requestedCards != null &&
          allocation.achievable > requestedCards &&
          allocation.achievable > 0)
        PlanWarningCode.cardsAboveRequested,
      if (inputPlan.images.any(
        (PlannedImage image) =>
            image.status == ImageParticipationStatus.unsupportedModel,
      ))
        PlanWarningCode.imagesWithoutVision,
      if (inputPlan.images.any(
        (PlannedImage image) =>
            image.status == ImageParticipationStatus.omittedPayload,
      ))
        PlanWarningCode.payloadLimited,
      if (limits.contextTokens.isKnown == false ||
          limits.maxOutputTokens.isKnown == false)
        PlanWarningCode.unknownCapabilities,
      if (_assumedImageLimits(capabilities)) PlanWarningCode.assumedImageLimits,
    };
    final PlanValidity validity = warnings.isEmpty
        ? const PlanValidity.valid()
        : PlanValidity.warnings(List<PlanWarningCode>.unmodifiable(warnings));

    final List<PlannedChunk> chunks = <PlannedChunk>[];
    final Map<String, PlannedImage> imageStatuses = <String, PlannedImage>{
      for (final PlannedImage image in inputPlan.images) image.id: image,
    };
    var nextChunkIndex = 1;
    if (inputPlan.isPromptOnly || data.sections.isEmpty) {
      for (final PlannedBatch batch in batches) {
        if (inputPlan.isPromptOnly) {
          chunks.add(
            PlannedChunk.promptOnly(
              index: nextChunkIndex++,
              limit: batch.limit,
              textTokens: promptTokens,
              bodyBytes: promptBodyBytes,
            ),
          );
        } else {
          chunks.add(
            _attachmentChunk(
              batch: batch,
              index: nextChunkIndex++,
              partCount: inputPlan.partCount,
              data: data,
              config: config,
              fixedBytes: overhead.fixedBytes,
            ),
          );
        }
      }
    } else {
      final Map<int, List<PlannedBatch>> batchesByPart =
          <int, List<PlannedBatch>>{};
      for (final PlannedBatch batch in batches) {
        (batchesByPart[batch.partIndex] ??= <PlannedBatch>[]).add(batch);
      }
      final Set<int> partsWithChunks = <int>{};
      for (final InputPart part in inputPlan.parts) {
        final List<PlannedBatch> base =
            batchesByPart[part.index] ?? const <PlannedBatch>[];
        if (base.isEmpty) continue;
        final int totalCards = base.fold<int>(
          0,
          (int sum, PlannedBatch batch) => sum + batch.limit,
        );
        if (totalCards <= 0) continue;
        final List<InputImage> partImages = _imagesOfPart(data, part);
        final List<List<InputImage>> bins = _imageBins(part.images, limits);
        var count = base.length;
        if (bins.length > count) {
          count = math.min(bins.length, totalCards);
        }
        final List<int> sizes = _balancedSizes(totalCards, count);
        final List<List<String>> focus = OutputBatchPlanner.focusGroupsFor(
          part.sections,
          allocation,
          sizes,
        );
        for (var index = 0; index < sizes.length; index++) {
          final List<InputImage> batchImages = index < bins.length
              ? bins[index]
              : const <InputImage>[];
          final List<InputImage> catalogImages = <InputImage>[
            for (final InputImage image in partImages)
              if (!batchImages.any((InputImage sent) => sent.id == image.id))
                image,
          ];
          for (final InputImage image in batchImages) {
            imageStatuses[image.id] = PlannedImage(
              id: image.id,
              fileName: image.fileName,
              status: ImageParticipationStatus.sentToModel,
              page: image.page,
              tokens: image.tokens,
            );
          }
          chunks.add(
            _chunkFor(
              index: nextChunkIndex++,
              partIndex: part.index,
              partCount: inputPlan.partCount,
              focusSectionIds: focus[index],
              limit: sizes[index],
              part: part,
              data: data,
              attachments: partsWithChunks.contains(part.index)
                  ? const <GenerationAttachment>[]
                  : _attachmentsForPart(
                      data: data,
                      part: part,
                      firstBatchOfPart: true,
                    ),
              config: config,
              fixedBytes: overhead.fixedBytes,
              batchImages: batchImages,
              catalogImages: catalogImages,
            ),
          );
        }
        partsWithChunks.add(part.index);
      }
    }

    return GenerationPlan(
      validity: validity,
      estimate: _estimate(
        chunks: chunks,
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        config: config,
      ),
      budget: _trace(
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        unknownFields: _unknownFields(limits, inputPlan),
        outputTokens: inputPlan.maxTokens,
      ),
      chunks: chunks,
      requestedCards: requestedCards ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
      unknownFields: _unknownFields(limits, inputPlan),
      images: imageStatuses.values.toList(growable: false),
      capabilitySources: capabilities.sources,
      mode: promptOnly ? GenerationMode.promptOnly : GenerationMode.materials,
      promptOnlyPrompt: promptOnly ? (wishes ?? '') : null,
      inputPlan: inputPlan,
      allocation: allocation,
      reasoningReserveTokens: reasoningReserve,
    );
  }

  // -- данные ---------------------------------------------------------------

  /// Пустой план: материалов нет, темы тоже (не ошибка плана).
  GenerationPlan _emptyPlan({
    required ModelLimits limits,
    required GenerationOverheadTokens overhead,
  }) {
    final InputPlan inputPlan = InputPlanner(config: config.planning).plan(
      sections: const <InputSection>[],
      limits: limits,
      fixedTokens: overhead.fixedTokens,
      desiredOutputTokens: 0,
    );
    return GenerationPlan(
      validity: const PlanValidity.valid(),
      estimate: _estimate(
        chunks: const <PlannedChunk>[],
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        config: config,
      ),
      budget: _trace(
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        unknownFields: _unknownFields(limits, inputPlan),
        outputTokens: 0,
      ),
      chunks: const <PlannedChunk>[],
      inputPlan: inputPlan,
      unknownFields: _unknownFields(limits, inputPlan),
    );
  }

  _InventoryData _inventoryData(
    ContentInventory inventory,
    ContentTokenEstimator estimator,
  ) {
    final List<InputSection> sections = <InputSection>[];
    final Map<String, List<_PieceInfo>> piecesBySection =
        <String, List<_PieceInfo>>{};
    final List<InputImage> orphanImages = <InputImage>[];
    final List<AttachmentUnit> attachments = <AttachmentUnit>[];
    var shortIndex = 0;
    for (final DocumentUnit document in inventory.documents) {
      for (final SectionUnit section in document.sections) {
        shortIndex++;
        final List<_PieceInfo> pieces = <_PieceInfo>[];
        var cursor = 0;
        for (final TextPiece piece in section.pieces) {
          if (piece.text.isEmpty) continue;
          final int index = section.text.indexOf(piece.text, cursor);
          final int startRel = index >= 0 ? index : cursor;
          cursor = startRel + piece.text.length;
          pieces.add(
            _PieceInfo(
              unitId: piece.id,
              startRel: startRel,
              length: piece.text.length,
              tokens: piece.tokens,
            ),
          );
        }
        piecesBySection[section.id] = pieces;
        sections.add(
          InputSection(
            id: section.id,
            shortId: 's$shortIndex',
            title: section.title ?? '',
            text: section.text,
            tokens: section.tokens,
            documentName: document.fileName,
            unitIds: <String>[
              for (final TextPiece piece in section.pieces) piece.id,
            ],
            images: <InputImage>[
              for (final ImageRef image in section.images)
                InputImage(
                  id: image.id,
                  fileName: image.image.fileName,
                  bytes: image.image.bytes,
                  tokens: image.tokens,
                  page: image.image.page,
                  sectionId: section.id,
                  catalogLineBytes: image.catalogLineBytes,
                  catalogTokens: image.catalogTokens,
                ),
            ],
          ),
        );
      }
    }
    for (final OrphanImageUnit orphan in inventory.orphanImages) {
      orphanImages.add(
        InputImage(
          id: orphan.image.id,
          fileName: orphan.image.image.fileName,
          bytes: orphan.image.image.bytes,
          tokens: orphan.image.tokens,
          page: orphan.image.image.page,
          catalogLineBytes: orphan.image.catalogLineBytes,
          catalogTokens: orphan.image.catalogTokens,
        ),
      );
    }
    attachments.addAll(inventory.attachments);
    return _InventoryData(
      sections: sections,
      piecesBySection: piecesBySection,
      orphanImages: orphanImages,
      attachments: attachments,
    );
  }

  /// План для инвентаря без текста: только вложения (страницы скана/картинки).
  InputPlan _attachmentsOnlyPlan({
    required _InventoryData data,
    required ModelLimits limits,
    required GenerationOverheadTokens overhead,
    required int desired,
  }) {
    final int tokens = data.attachmentPageTokens;
    final int catalogTokens = data.orphanImages.fold<int>(
      0,
      (int sum, InputImage image) => sum + image.catalogTokens,
    );
    final int bytes = data.attachmentPageBytes;
    final RequestBudget budget = RequestBudget.compute(
      limits: limits,
      fixedTokens: overhead.fixedTokens,
      materialTokens: tokens + catalogTokens,
      desiredOutputTokens: desired,
      accuracy: InputAccuracy.estimated,
      config: config.planning,
      requestBytes: bytes + overhead.fixedBytes + config.planning.jsonBodyOverheadBytes,
    );
    final bool whole =
        !budget.contextExceeded &&
        budget.maxTokens >=
            config.planning.tokensFor(config.planning.minBatchCards);
    final InputPart part = InputPart(
      index: 0,
      sections: const <InputSection>[],
      materialsText: '',
      tokens: 0,
      bytes: bytes + overhead.fixedBytes + config.planning.jsonBodyOverheadBytes,
      images: List<InputImage>.unmodifiable(data.orphanImages),
      catalogTokens: catalogTokens,
    );
    return InputPlan(
      strategy: whole ? InputStrategy.wholeDocument : InputStrategy.fragmented,
      parts: List<InputPart>.unmodifiable(<InputPart>[part]),
      fixedTokens: overhead.fixedTokens,
      inputTokens: budget.inputTokens,
      maxTokens: budget.maxTokens,
      accuracy: InputAccuracy.estimated,
      budget: budget,
      materialTokens: tokens + catalogTokens,
      contextTokens: limits.contextTokens.value,
      warnings: List<PlanWarningCode>.unmodifiable(<PlanWarningCode>[
        if (limits.contextTokens.isKnown == false)
          PlanWarningCode.contextUnconfirmed,
        if (budget.payloadExceeded) PlanWarningCode.payloadLimited,
      ]),
      catalogTokens: catalogTokens,
    );
  }

  List<AllocationSection> _allocationSections(
    _InventoryData data,
    String? wishes,
  ) {
    final List<String> keywords = _wishKeywords(wishes);
    final List<AllocationSection> result = <AllocationSection>[];
    for (final InputSection section in data.sections) {
      final SectionFeatures features = SectionFeatures.of(
        title: section.title,
        text: section.text,
      );
      final AllocationSection base = AllocationSection.fromFeatures(
        id: section.id,
        title: section.title,
        features: features,
      );
      result.add(
        AllocationSection(
          id: base.id,
          title: base.title,
          weight: CardAllocator.weightedForWishes(
            base.weight,
            section.title,
            keywords,
          ),
          capacity: base.capacity,
          kind: base.kind,
          meaningfulTokens: base.meaningfulTokens,
          density: base.density,
        ),
      );
    }
    return result;
  }

  List<String> _wishKeywords(String? wishes) {
    final String text = wishes?.trim() ?? '';
    if (text.isEmpty) return const <String>[];
    return <String>[
      for (final Match match in RegExp(
        r'[A-Za-zА-Яа-яЁё0-9]{4,}',
        unicode: true,
      ).allMatches(text))
        match.group(0)!.toLowerCase(),
    ];
  }

  // -- фрагменты ------------------------------------------------------------

  PlannedChunk _chunkFor({
    required int index,
    required int partIndex,
    required int partCount,
    required List<String> focusSectionIds,
    required int limit,
    required InputPart part,
    required _InventoryData data,
    required List<GenerationAttachment> attachments,
    required GenerationChunkPlannerConfig config,
    required List<InputImage> batchImages,
    required List<InputImage> catalogImages,
    int fixedBytes = 0,
  }) {
    final RenderedMaterials rendered = renderInputMaterials(part.sections);
    final List<UnitSpan> units = <UnitSpan>[];
    for (final InputSection section in part.sections) {
      final int base = rendered.sectionStarts[section.id] ?? 0;
      final List<_PieceInfo> pieces =
          data.piecesBySection[section.id] ?? const <_PieceInfo>[];
      if (pieces.isEmpty && section.text.isNotEmpty) {
        units.add(
          UnitSpan(
            unitId: section.id,
            start: base,
            end: base + section.text.length,
            tokens: section.tokens,
          ),
        );
        continue;
      }
      for (final _PieceInfo piece in pieces) {
        units.add(
          UnitSpan(
            unitId: piece.unitId,
            start: base + piece.startRel,
            end: base + piece.startRel + piece.length,
            tokens: piece.tokens,
          ),
        );
      }
    }
    final List<DocumentImage> imageParts = <DocumentImage>[
      for (final InputImage image in batchImages) _documentImageOf(image),
    ];
    final List<DocumentImage> catalogPart = <DocumentImage>[
      for (final InputImage image in catalogImages) _documentImageOf(image),
    ];
    final int imageTokens = batchImages.fold<int>(
      0,
      (int sum, InputImage image) => sum + image.tokens,
    );
    final int catalogBytes =
        batchImages.fold<int>(
          0,
          (int sum, InputImage image) => sum + image.catalogLineBytes,
        ) +
        catalogImages.fold<int>(
          0,
          (int sum, InputImage image) => sum + image.catalogLineBytes,
        );
    final int bodyBytes =
        utf8.encode(rendered.text).length +
        catalogBytes +
        _base64Bytes(batchImages) +
        fixedBytes +
        config.jsonBodyOverheadBytes;
    final bool hasText = rendered.text.trim().isNotEmpty;
    final bool hasParts = imageParts.isNotEmpty || attachments.isNotEmpty;
    final ChunkKind kind = hasText && hasParts
        ? ChunkKind.mixed
        : hasText
        ? ChunkKind.text
        : hasParts
        ? ChunkKind.images
        : ChunkKind.catalog;
    return PlannedChunk(
      index: index,
      kind: kind,
      units: units,
      imageParts: imageParts,
      catalogOnly: catalogPart,
      imagePartIds: <String>[
        for (final InputImage image in batchImages) image.id,
      ],
      catalogOnlyIds: <String>[
        for (final InputImage image in catalogImages) image.id,
      ],
      attachments: attachments,
      textTokens: part.tokens,
      imageTokens: imageTokens,
      bodyBytes: bodyBytes,
      limit: limit,
      materialsText: rendered.text,
      focusSectionIds: focusSectionIds,
      partIndex: partIndex,
      partCount: partCount,
    );
  }

  /// Фрагмент для инвентаря без текста: вложения (PDF/сканы) целиком.
  PlannedChunk _attachmentChunk({
    required PlannedBatch batch,
    required int index,
    required int partCount,
    required _InventoryData data,
    required GenerationChunkPlannerConfig config,
    int fixedBytes = 0,
  }) {
    final List<GenerationAttachment> attachments = data.allAttachmentPages;
    final bool first = batch.index == 0;
    return PlannedChunk(
      index: index,
      kind: ChunkKind.images,
      imageParts: const <DocumentImage>[],
      imagePartIds: const <String>[],
      catalogOnly: const <DocumentImage>[],
      catalogOnlyIds: const <String>[],
      attachments: first ? attachments : const <GenerationAttachment>[],
      units: const <UnitSpan>[],
      textTokens: 0,
      imageTokens: data.attachmentPageTokens,
      bodyBytes:
          data.attachmentPageBytes + fixedBytes + config.jsonBodyOverheadBytes,
      limit: batch.limit,
      materialsText: '',
      partIndex: 0,
      partCount: partCount,
    );
  }

  /// Все изображения части (по разделам части + orphan в первой части).
  List<InputImage> _imagesOfPart(_InventoryData data, InputPart part) {
    final List<InputImage> images = <InputImage>[];
    final Set<String> seen = <String>{};
    for (final InputSection section in part.sections) {
      for (final InputImage image in section.images) {
        if (seen.add(image.id)) images.add(image);
      }
    }
    if (part.index == 0) {
      for (final InputImage image in data.orphanImages) {
        if (seen.add(image.id)) images.add(image);
      }
    }
    return images;
  }

  /// Раскладывает изображения по запросам по лимитам image-частей и байтов.
  List<List<InputImage>> _imageBins(
    List<InputImage> images,
    ModelLimits limits,
  ) {
    if (images.isEmpty) return const <List<InputImage>>[];
    final int? maxCount = limits.maxImagesPerRequest.value;
    final int? maxBytes = limits.maxImageBytesPerRequest.value;
    final List<List<InputImage>> bins = <List<InputImage>>[];
    List<InputImage> current = <InputImage>[];
    var currentBytes = 0;
    for (final InputImage image in images) {
      final bool countFull =
          maxCount != null && current.length >= math.max(1, maxCount);
      final bool bytesFull =
          maxBytes != null &&
          current.isNotEmpty &&
          currentBytes + image.bytes.length > maxBytes;
      if (current.isNotEmpty && (countFull || bytesFull)) {
        bins.add(current);
        current = <InputImage>[];
        currentBytes = 0;
      }
      current.add(image);
      currentBytes += image.bytes.length;
    }
    if (current.isNotEmpty) bins.add(current);
    return bins;
  }

  /// Сбалансированные размеры партий (∑ = [total], каждая ≥ 1).
  List<int> _balancedSizes(int total, int count) {
    final int safeCount = math.max(1, math.min(count, total));
    final int base = total ~/ safeCount;
    final int remainder = total % safeCount;
    return <int>[
      for (var index = 0; index < safeCount; index++)
        math.max(1, base + (index < remainder ? 1 : 0)),
    ];
  }

  DocumentImage _documentImageOf(InputImage image) => DocumentImage(
    fileName: image.fileName,
    bytes: image.bytes,
    mediaType:
        attachmentMediaTypeForFileName(image.fileName) ??
        AttachmentMediaType.png,
    id: image.id,
    page: image.page,
  );

  int _base64Bytes(Iterable<InputImage> images) {
    var total = 0;
    for (final InputImage image in images) {
      total += ((image.bytes.length + 2) ~/ 3) * 4;
    }
    return total;
  }

  List<GenerationAttachment> _attachmentsForPart({
    required _InventoryData data,
    required InputPart part,
    required bool firstBatchOfPart,
  }) {
    if (!firstBatchOfPart || data.attachments.isEmpty) {
      return const <GenerationAttachment>[];
    }
    final Set<String> files = <String>{
      for (final InputSection section in part.sections) section.documentName,
    };
    final List<GenerationAttachment> result = <GenerationAttachment>[];
    for (final AttachmentUnit unit in data.attachments) {
      final bool fits = files.isEmpty || files.contains(unit.fileName);
      if (!fits) continue;
      for (final PageUnit page in unit.pages) {
        result.add(
          GenerationAttachment(
            fileName: unit.fileName,
            mediaType: unit.mediaType,
            bytes: page.bytes,
            pageNumber: page.pageNumber,
            groupKey: unit.groupKey,
          ),
        );
      }
    }
    return List<GenerationAttachment>.unmodifiable(result);
  }

  // -- служебное ------------------------------------------------------------

  CardAllocation _syntheticAllocation({
    required int? requestedCards,
    required int batchCap,
  }) {
    final int safeCap = math.max(1, batchCap);
    final int achievable = requestedCards ?? safeCap;
    return CardAllocation(
      planned: const <String, int>{},
      requested: requestedCards,
      achievable: achievable,
      belowRequested: false,
    );
  }

  List<PlannedBatch> _batchesWithoutSections({
    required InputPlan inputPlan,
    required CardAllocation allocation,
    required GenerationPlanningConfig planning,
    required int reasoningReserveTokens,
  }) {
    final int budget = inputPlan.maxTokens - reasoningReserveTokens;
    final int perBatch = math.max(
      1,
      math.min(
        planning.batchCardsCeiling,
        planning.cardsFor(budget < 0 ? 0 : budget),
      ),
    );
    final int total = allocation.achievable;
    if (total <= 0 || inputPlan.parts.isEmpty) return const <PlannedBatch>[];
    final int count = (total / perBatch).ceil();
    final int base = total ~/ count;
    final int remainder = total % count;
    return <PlannedBatch>[
      for (var index = 0; index < count; index++)
        PlannedBatch(
          index: index,
          partIndex: 0,
          partCount: inputPlan.partCount,
          focusSectionIds: const <String>[],
          limit: math.max(1, base + (index < remainder ? 1 : 0)),
        ),
    ];
  }

  bool _hasUnplaceableUnit(_InventoryData data, InputPlan inputPlan) {
    final int? budget = inputPlan.materialBudgetPerPart;
    if (budget == null) return false;
    for (final InputSection section in data.sections) {
      if (section.tokens > budget) return true;
    }
    return false;
  }

  bool _assumedImageLimits(ModelCapabilities capabilities) {
    return capabilities.maxImagesPerRequest == null ||
        capabilities.maxImageBytesPerImage == null ||
        capabilities.maxRequestBytes == null;
  }

  List<String> _unknownFields(ModelLimits limits, InputPlan inputPlan) {
    final Set<String> fields = <String>{
      if (!limits.contextTokens.isKnown) 'context_window',
      if (!limits.maxOutputTokens.isKnown) 'max_output_tokens',
    };
    if (inputPlan.images.isNotEmpty &&
        limits.supportsImageInput.source != CapabilitySource.providerApi) {
      fields.add('image_limits');
    }
    return List<String>.unmodifiable(fields);
  }

  GenerationEstimate _estimate({
    required List<PlannedChunk> chunks,
    required InputPlan inputPlan,
    required ModelLimits limits,
    required GenerationOverheadTokens overhead,
    required GenerationChunkPlannerConfig config,
  }) {
    final GenerationPlanningConfig planning = config.planning;
    final bool promptOnly = inputPlan.isPromptOnly;
    final int inputText = promptOnly
        ? chunks.fold<int>(
            0,
            (int sum, PlannedChunk chunk) => sum + chunk.textTokens,
          )
        : inputPlan.parts.fold<int>(
            0,
            (int sum, InputPart part) => sum + part.tokens,
          );
    final int imageTokens = inputPlan.parts.fold<int>(
      0,
      (int sum, InputPart part) =>
          sum +
          part.images.fold<int>(
            0,
            (int inner, InputImage image) => inner + image.tokens,
          ),
    );
    // §3.4: каталог `<images>` — часть `D`, поэтому входит в оценку входа.
    final int catalogTokens = inputPlan.parts.fold<int>(
      0,
      (int sum, InputPart part) => sum + part.catalogTokens,
    );
    final int requests = math.max(1, chunks.length);
    final int outputCap = planning.outputCapFor(limits);
    final int reserved;
    if (promptOnly) {
      // Партии prompt-only не делят материал: резерв вывода — сумма по партиям,
      // а не «на партию × число запросов» (иначе оценка растёт вдвое).
      reserved = chunks.fold<int>(
        0,
        (int sum, PlannedChunk chunk) =>
            sum + math.min(outputCap, planning.tokensFor(chunk.limit)),
      );
    } else {
      reserved = planning.tokensFor(
        math.min(
          planning.batchCardsCeiling,
          chunks.isEmpty
              ? planning.minBatchCards
              : chunks.fold<int>(0, (int sum, PlannedChunk c) => sum + c.limit),
        ),
      );
    }
    final int batchInput = promptOnly
        ? inputPlan.inputTokens * requests
        : inputPlan.parts.isEmpty
        ? inputPlan.inputTokens
        : inputPlan.parts.fold<int>(
            0,
            (int sum, InputPart part) =>
                sum +
                RequestBudget.compute(
                  limits: limits,
                  fixedTokens: overhead.fixedTokens + overhead.outlineTokens,
                  materialTokens:
                      part.tokens +
                      part.catalogTokens +
                      part.images.fold<int>(
                        0,
                        (int inner, InputImage image) => inner + image.tokens,
                      ),
                  desiredOutputTokens: inputPlan.maxTokens,
                  config: planning,
                ).inputTokens,
          );
    final int outputTotal = promptOnly ? reserved : reserved * requests;
    final int totalTokens = batchInput + outputTotal;
    // Сводка продолжения prompt-only: второй и следующие запросы несут блок
    // уже созданных карточек; его резерв виден в оценке как часть обвязки.
    final int continuation = promptOnly && requests > 1
        ? math.max(
            0,
            inputPlan.fixedTokens -
                overhead.fixedTokens -
                (chunks.isEmpty ? 0 : chunks.first.textTokens),
          )
        : 0;
    GenerationCost? cost;
    final GenerationPricing? pricing = limits.pricing.value;
    if (pricing != null) {
      cost = pricing.costFor(
        inputTokens: batchInput,
        outputTokens: outputTotal,
      );
    }
    return GenerationEstimate(
      inputTextTokens: inputText,
      imageTokens: imageTokens,
      fixedPromptTokens: promptOnly
          ? overhead.systemPromptTokens * requests
          : overhead.systemPromptTokens,
      wrapperTokens: promptOnly
          ? (overhead.wrapperTokens + overhead.taskTailTokens) * requests +
                continuation * (requests - 1)
          : overhead.wrapperTokens + overhead.taskTailTokens,
      schemaTokens: promptOnly
          ? overhead.schemaTokens * requests
          : overhead.schemaTokens,
      catalogTokens: catalogTokens,
      reservedOutputTokens: outputTotal,
      expectedOutputTokens: outputTotal,
      totalTokens: totalTokens,
      plannedChunks: promptOnly ? chunks.length : inputPlan.partCount,
      plannedRequests: chunks.length,
      retryAllowanceRequests: config.retryAllowanceRequests,
      pricingState: limits.pricing.value?.state ?? PricingState.unknown,
      estimatorVersion: estimator.version,
      inputCost: cost?.input,
      outputCost: cost?.output,
      totalCost: cost?.total,
      currency: cost?.currency,
      unknownFields: _unknownFields(limits, inputPlan),
      confidence: inputPlan.accuracy == InputAccuracy.exact ? 1 : 0.6,
      continuationReserveTokens: promptOnly
          ? continuation * math.max(0, requests - 1)
          : 0,
    );
  }

  GenerationPlan _invalidPlan(
    PlanInvalidReason reason, {
    required InputPlan inputPlan,
    required ModelLimits limits,
    required GenerationOverheadTokens overhead,
    required int? requestedCards,
    GenerationMode mode = GenerationMode.materials,
    String? promptText,
  }) {
    return GenerationPlan(
      validity: PlanValidity.invalid(
        reason,
        neededTokens: inputPlan.materialBudgetPerPart,
        availableTokens: inputPlan.budget.contextTokens,
      ),
      estimate: _estimate(
        chunks: const <PlannedChunk>[],
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        config: config,
      ),
      budget: _trace(
        inputPlan: inputPlan,
        limits: limits,
        overhead: overhead,
        unknownFields: _unknownFields(limits, inputPlan),
        outputTokens: inputPlan.maxTokens,
      ),
      chunks: const <PlannedChunk>[],
      requestedCards: requestedCards ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
      mode: mode,
      promptOnlyPrompt: mode == GenerationMode.promptOnly
          ? (promptText ?? 'план по теме')
          : null,
      inputPlan: inputPlan,
      unknownFields: _unknownFields(limits, inputPlan),
      reasoningReserveTokens: limits.isReasoningModel.value == true
          ? config.planning.reasoningReserveTokens
          : 0,
    );
  }

  /// Трассировка бюджета для плана/диагностики (старые поля сохранены).
  BudgetTrace _trace({
    required InputPlan inputPlan,
    required ModelLimits limits,
    required GenerationOverheadTokens overhead,
    required List<String> unknownFields,
    required int outputTokens,
  }) {
    final int imageTokens = inputPlan.parts.fold<int>(
      0,
      (int sum, InputPart part) =>
          sum +
          part.images.fold<int>(
            0,
            (int inner, InputImage image) => inner + image.tokens,
          ),
    );
    final int catalogTokens = inputPlan.parts.fold<int>(
      0,
      (int sum, InputPart part) => sum + part.catalogTokens,
    );
    return BudgetTrace(
      formula: inputPlan.contextTokens == null
          ? GenerationBudget.formulaUnknownContext
          : GenerationBudget.formulaKnownContext,
      source: inputPlan.contextTokens == null
          ? BudgetSource.assumption
          : BudgetSource.capabilities,
      contextWindowTokens: inputPlan.contextTokens,
      contextSource: limits.contextTokens.source,
      outputCapTokens: config.planning.outputCapFor(limits),
      outputCapAssumed: !limits.maxOutputTokens.isKnown,
      expectedOutputTokens: outputTokens,
      reservedOutputTokens: inputPlan.maxTokens,
      fixedOverheadTokens: overhead.fixedTokens,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens + overhead.taskTailTokens,
      catalogTokens: catalogTokens,
      imageTokens: imageTokens,
      safetyMarginTokens: inputPlan.budget.marginTokens,
      minWorkableInputTokens: 0,
      maxInputTokensLimit: inputPlan.budget.maxInputTokensLimit,
      maxRequestBytesLimit: inputPlan.budget.maxRequestBytesLimit,
      inputBudget: inputPlan.inputTokens,
      unknownFields: unknownFields,
    );
  }
}

/// Покрытие плана: все исходные единицы учтены ровно один раз на часть.
final class GenerationPlanCoverage {
  const GenerationPlanCoverage._({
    required this.missingUnits,
    required this.duplicatedUnits,
    required this.uncoveredImages,
  });

  /// Проверяет покрытие [plan] для [inventory].
  static GenerationPlanCoverage check({
    required ContentInventory inventory,
    required GenerationPlan plan,
  }) {
    final List<String> expectedPieces = <String>[
      for (final DocumentUnit document in inventory.documents)
        for (final SectionUnit section in document.sections)
          for (final TextPiece piece in section.pieces) piece.id,
    ];
    final Set<String> expectedPieceSet = expectedPieces.toSet();
    final Map<String, Set<int>> unitParts = <String, Set<int>>{};
    final Set<String> coveredPieces = <String>{};
    for (final PlannedChunk chunk in plan.chunks) {
      for (final UnitSpan span in chunk.units) {
        (unitParts[span.unitId] ??= <int>{}).add(chunk.partIndex);
        final String? root = _rootPieceId(span.unitId, expectedPieceSet);
        if (root != null) coveredPieces.add(root);
      }
    }
    final List<String> missingText = <String>[
      for (final String id in expectedPieces)
        if (!coveredPieces.contains(id)) id,
    ];
    final List<String> duplicatedUnits = <String>[
      for (final MapEntry<String, Set<int>> entry in unitParts.entries)
        if (entry.value.length > 1) entry.key,
    ];
    final List<String> expectedImages = <String>[
      for (final ImageRef image in inventory.allImages) image.id,
    ];
    final Set<String> plannedImages = <String>{
      for (final PlannedChunk chunk in plan.chunks) ...chunk.imagePartIds,
      for (final PlannedChunk chunk in plan.chunks) ...chunk.catalogOnlyIds,
      for (final OmittedUnit omitted in plan.omitted) omitted.unitId,
    };
    final List<String> uncoveredImages = <String>[
      for (final String id in expectedImages)
        if (!plannedImages.contains(id)) id,
    ];
    return GenerationPlanCoverage._(
      missingUnits: List<String>.unmodifiable(missingText),
      duplicatedUnits: List<String>.unmodifiable(duplicatedUnits),
      uncoveredImages: List<String>.unmodifiable(uncoveredImages),
    );
  }

  /// Единицы текста/страницы вложений, которых нет ни в одном фрагменте.
  final List<String> missingUnits;

  /// Единицы, попавшие больше одного раза в одну часть.
  final List<String> duplicatedUnits;

  /// Изображения, не попавшие ни в части, ни в каталог, ни в `omitted`.
  final List<String> uncoveredImages;

  /// true, если потери нет.
  bool get isComplete =>
      missingUnits.isEmpty &&
      duplicatedUnits.isEmpty &&
      uncoveredImages.isEmpty;

  @override
  String toString() =>
      'GenerationPlanCoverage(missing: ${missingUnits.length}, '
      'duplicated: ${duplicatedUnits.length}, '
      'uncoveredImages: ${uncoveredImages.length})';
}

String? _rootPieceId(String spanId, Set<String> expectedPieces) {
  if (expectedPieces.contains(spanId)) return spanId;
  for (
    int index = spanId.indexOf('~');
    index >= 0;
    index = spanId.indexOf('~', index + 1)
  ) {
    final String prefix = spanId.substring(0, index);
    if (expectedPieces.contains(prefix)) return prefix;
  }
  return null;
}

/// Данные инвентаря, подготовленные для трёх планировщиков.
final class _InventoryData {
  const _InventoryData({
    required this.sections,
    required this.piecesBySection,
    required this.orphanImages,
    required this.attachments,
  });

  final List<InputSection> sections;
  final Map<String, List<_PieceInfo>> piecesBySection;
  final List<InputImage> orphanImages;
  final List<AttachmentUnit> attachments;

  /// true, если модели нужно передавать изображения/сканы.
  bool get hasVisionPayload =>
      attachments.isNotEmpty || orphanImages.isNotEmpty;

  /// Все страницы вложений как [GenerationAttachment] (порядок инвентаря).
  List<GenerationAttachment> get allAttachmentPages => <GenerationAttachment>[
    for (final AttachmentUnit unit in attachments)
      for (final PageUnit page in unit.pages)
        GenerationAttachment(
          fileName: unit.fileName,
          mediaType: unit.mediaType,
          bytes: page.bytes,
          pageNumber: page.pageNumber,
          groupKey: unit.groupKey,
        ),
  ];

  int get attachmentPageTokens => attachments.fold<int>(
    0,
    (int sum, AttachmentUnit unit) =>
        sum +
        unit.pages.fold<int>(
          0,
          (int inner, PageUnit page) => inner + page.tokens,
        ),
  );

  int get attachmentPageBytes => attachments.fold<int>(
    0,
    (int sum, AttachmentUnit unit) =>
        sum +
        unit.pages.fold<int>(
          0,
          (int inner, PageUnit page) =>
              inner + ((page.bytes.length + 2) ~/ 3) * 4,
        ),
  );
}

/// Смещение единицы текста внутри раздела.
final class _PieceInfo {
  const _PieceInfo({
    required this.unitId,
    required this.startRel,
    required this.length,
    required this.tokens,
  });

  final String unitId;
  final int startRel;
  final int length;
  final int tokens;
}
