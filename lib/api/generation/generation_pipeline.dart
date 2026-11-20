/// Пайплайн генерации карточек: адаптивный план, последовательные вызовы,
/// восстановление, дедупликация, прогресс/отмена и `generation_jobs`
/// (SPEC A8.5, ADR-015, разделы D–F аудита TASK 01).
///
/// Порядок работы с итерации TASK 02B-FINAL:
/// `GenerationRunRequest` → `ContentInventory`/`PromptOnlyRequest` →
/// `GenerationPlan` (бюджет, фрагменты, изображения, лимиты карточек) →
/// `CardGenerationService` по фрагментам плана → карточки/ошибки →
/// предпросмотр/импорт. План строится **до** первого API-запроса; старый
/// `GenerationChunker` в production-путь не вызывается и не переограничивает
/// план.
library;

import 'dart:math' as math;

import 'package:uuid/uuid.dart';

import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_continuity.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_plan_splitter.dart';
import 'package:cardflow/domain/generation/generation_recovery_budget.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/image_query.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

/// Коды ошибок, после которых повторять следующие фрагменты бессмысленно.
const Set<GenerationErrorCode> _fatalCodes = <GenerationErrorCode>{
  GenerationErrorCode.missingApiKey,
  GenerationErrorCode.providerNotConfigured,
  GenerationErrorCode.invalidApiKey,
  GenerationErrorCode.noMaterials,
};

/// Код в `generation_jobs.error_code` для непредвиденного сбоя пайплайна/БД.
const String _unexpectedErrorCode = 'unexpected';

/// Строитель плана для тестов/встраивания (production использует
/// [GenerationPlanBuilder] и [PromptOnlyPlanner]).
typedef GenerationPlanFactory = GenerationPlan Function(
  GenerationRunRequest request,
  ModelCapabilities capabilities,
);

/// Оркестратор генерации (контракт для UI).
abstract interface class GenerationRunner {
  /// Запускает генерацию.
  Future<GenerationRunResult> run(
    GenerationRunRequest request, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  });

  /// Повторяет только упавшие фрагменты предыдущего результата.
  Future<GenerationRunResult> retryFailed(
    GenerationRunRequest request,
    GenerationRunResult previous, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  });
}

/// Оркестратор генерации по адаптивному плану.
class GenerationPipeline implements GenerationRunner {
  /// Создаёт пайплайн.
  GenerationPipeline({
    required this.caller,
    required this.jobRepository,
    required this.cardStore,
    this.planBuilder = const GenerationPlanBuilder(),
    this.capabilityCache,
    this.calibrationStore,
    this.planFactory,
    this.splitter = const GenerationPlanSplitter(),
    this.imageFinder,
    this.placeholderGenerator,
    this.imageSearchBudget = const Duration(seconds: 90),
    this.diagnostics = const GenerationDiagnostics(),
    this.now = _defaultNow,
    this.jobIdFactory = _defaultJobId,
    this.maxRecoveryRequests = 12,
  }) : assert(maxRecoveryRequests >= 0);

  /// Вызов модели на фрагмент.
  final GenerationCaller caller;

  /// Хранилище заданий.
  final GenerationJobRepository jobRepository;

  /// Дедупликация/импорт.
  final GenerationCardStore cardStore;

  /// Сборщик плана по материалам и по теме (production-путь).
  final GenerationPlanBuilder planBuilder;

  /// Кэш характеристик модели (ADR-039); `null` — только каталог/аккаунт.
  final ModelCapabilityCache? capabilityCache;

  /// Калибровка `tokensPerCard` (ADR-040 §9); `null` — значение по умолчанию.
  final TokenCalibrationStore? calibrationStore;

  /// Подмена плана (тесты/встраивание); `null` — production-путь.
  final GenerationPlanFactory? planFactory;

  /// Дробление проблемного фрагмента при восстановлении (F.3).
  final GenerationPlanSplitter splitter;

  /// Поиск иллюстраций по `image` (итерации 7.9/7.14); `null` — без поиска.
  final CardImageFinder? imageFinder;

  /// Детерминированная заглушка, если картинку не нашли/не скачали (7.14,
  /// шаг 3); `null` — заглушки не создаются (старое поведение).
  final PlaceholderImageGenerator? placeholderGenerator;

  /// Бюджет **суммарного времени поиска** иллюстраций за один запуск (7.11).
  ///
  /// Считается только время внутри `CardImageFinder.findImage` — ожидание
  /// ответа модели бюджет не расходует. Недоступный/медленный источник не
  /// задерживает импорт: после бюджета оставшиеся карточки получают
  /// `image == null`, а генерация завершается (диагностика ADR-024 фиксирует
  /// пропуск). С итерации 7.12 бюджет увеличен до 90 с: цепочка источников
  /// (Commons → Wikipedia → Openverse) на неудачном русском запросе тратит
  /// больше времени, и 45 с обрезали карточки, которые ещё можно было найти.
  final Duration imageSearchBudget;

  /// Debug-диагностика (ADR-024).
  final GenerationDiagnostics diagnostics;

  /// Технический предохранитель восстановления: сколько дополнительных
  /// запросов (дроблений/сокращений вывода) допускается за запуск (F.2/F.3).
  final int maxRecoveryRequests;

  /// Кэш картинок по запросу в рамках одного запуска/повтора.
  final Map<String, Future<GeneratedCardImage?>> _imageCache =
      <String, Future<GeneratedCardImage?>>{};

  /// Сколько времени уже потрачено на поиск иллюстраций в этом запуске.
  Duration _imageSearchSpent = Duration.zero;

  /// URL картинок, уже занятых карточками этого запуска: один и тот же URL
  /// не должен попасть в колоду дважды (правило 7.14).
  final Set<String> _usedImageUrls = <String>{};

  /// Бюджет поиска включён (есть источник и положительный лимит).
  bool get _imageSearchBudgeted =>
      imageFinder != null && imageSearchBudget > Duration.zero;

  /// Часы (инжектируются в тестах).
  final DateTime Function() now;

  /// Генератор id задания (инжектируется в тестах).
  final String Function() jobIdFactory;

  @override
  Future<GenerationRunResult> run(
    GenerationRunRequest request, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) async {
    _imageCache.clear();
    _usedImageUrls.clear();
    _resetImageBudget();
    final String jobId = jobIdFactory();
    final DateTime createdAt = now();
    final GenerationJob initialJob = GenerationJob(
      id: jobId,
      status: GenerationJobStatus.running,
      createdAt: createdAt,
      provider: request.account.id,
      model: request.account.modelId,
      promptVersion: systemPromptVersion,
      chunkCount: 0,
      cardsCount: 0,
      files: _fileNames(request),
    );
    await jobRepository.save(initialJob);

    try {
      onProgress?.call(
        const GenerationProgress(phase: GenerationProgressPhase.chunking),
      );
      final bool hasMaterials =
          request.documents.isNotEmpty ||
          request.images.isNotEmpty ||
          request.documentImages.isNotEmpty;
      final String? topic = _topicOf(request.wishes);
      if (!hasMaterials && topic == null) {
        await jobRepository.save(
          initialJob.copyWith(
            status: GenerationJobStatus.error,
            errorCode: GenerationErrorCode.noMaterials.name,
          ),
        );
        throw const GenerationException(GenerationErrorCode.noMaterials);
      }

      final ModelCapabilities capabilities = await _capabilitiesFor(
        request.account,
      );
      final TokenCalibration? calibration = await _calibrationFor(
        request.account,
      );
      final GenerationPlanBuilder effectiveBuilder = _calibratedBuilder(
        calibration,
      );
      final GenerationPlan plan = _buildPlan(
        request,
        capabilities,
        hasMaterials: hasMaterials,
        topic: topic,
        builder: effectiveBuilder,
      );
      // План проверяется до первого API-запроса (D.8): невалидный план не
      // тратит токены и не маскируется частичным успехом.
      if (!plan.validity.isValid) {
        final GenerationException error = _planError(plan);
        await jobRepository.save(
          initialJob.copyWith(
            status: GenerationJobStatus.error,
            errorCode: error.code.name,
          ),
        );
        throw error;
      }
      if (plan.chunks.isEmpty) {
        await jobRepository.save(
          initialJob.copyWith(
            status: GenerationJobStatus.error,
            errorCode: GenerationErrorCode.noMaterials.name,
          ),
        );
        throw const GenerationException(GenerationErrorCode.noMaterials);
      }

      diagnostics.planSummary(
        strategy: plan.inputStrategy?.name ?? 'legacy',
        parts: plan.partCount,
        batches: plan.chunks.length,
        requestedCards: plan.requestedCards,
        achievableCards: plan.achievableCards,
        calibrated: calibration != null,
      );
      final Set<String> seen = <String>{
        ...?await _existingHashes(request.targetDeckId),
      };
      final GenerationRunResult result = await _process(
        request: request,
        job: initialJob,
        plan: plan,
        chunks: plan.chunks,
        seen: seen,
        estimate: plan.estimate.totalTokens,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return result;
    } on Object {
      await _markUnexpected(jobId, initialJob);
      rethrow;
    }
  }

  /// Строит план: prompt-only по теме или по материалам (D.5/D.7).
  GenerationPlan _buildPlan(
    GenerationRunRequest request,
    ModelCapabilities capabilities, {
    required bool hasMaterials,
    required String? topic,
    GenerationPlanBuilder? builder,
  }) {
    final GenerationPlanFactory? factory = planFactory;
    if (factory != null) return factory(request, capabilities);
    final GenerationPlanBuilder effective = builder ?? planBuilder;
    final int? requested =
        request.requestedCards ?? requestedCardCount(request.wishes);
    if (!hasMaterials) {
      // Prompt-only план строится тем же builder-ом, что и материаловый: он
      // считает системный промпт, схему и обёртку (TASK 03, D1/D2). Прямой
      // вызов планировщика без `overhead` занижал бюджет на тысячи токенов.
      return effective.buildPromptOnly(
        request: PromptOnlyRequest(prompt: topic!, requestedCards: requested),
        capabilities: capabilities,
      );
    }
    return effective.build(
      documents: request.documents,
      capabilities: capabilities,
      attachments: request.images,
      documentImages: request.documentImages,
      wishes: request.wishes,
      requestedCards: requested,
    );
  }

  /// Калибровка `tokensPerCard` аккаунта (применяется только после ≥2 замеров).
  Future<TokenCalibration?> _calibrationFor(ProviderAccount account) async {
    final TokenCalibrationStore? store = calibrationStore;
    if (store == null) return null;
    try {
      final TokenCalibration? calibration = await store.read(
        accountId: account.id,
        model: account.modelId,
      );
      if (calibration == null || !calibration.isApplicable) return null;
      return calibration;
    } on Object {
      return null;
    }
  }

  /// Builder с калиброванным `tokensPerCard` или исходный.
  GenerationPlanBuilder _calibratedBuilder(TokenCalibration? calibration) {
    if (calibration == null) return planBuilder;
    final GenerationPlanningConfig planning = const GenerationPlanningConfig()
        .copyWith(
          tokensPerCard: calibration.tokensPerCard.round().clamp(50, 5000),
        );
    return GenerationPlanBuilder(
      planner: GenerationChunkPlanner(
        estimator: planBuilder.estimator,
        config: GenerationChunkPlannerConfig(
          planning: planning,
          retryAllowanceRequests:
              planBuilder.planner.config.retryAllowanceRequests,
        ),
        catalogLineBuilder: planBuilder.planner.catalogLineBuilder,
      ),
    );
  }

  /// Тема/пожелания для prompt-only; `null` — пусто.
  String? _topicOf(String? wishes) {
    final String text = wishes?.trim() ?? '';
    return text.isEmpty ? null : text;
  }

  /// Невалидный план → доменная ошибка (ARB-сообщение в UI).
  GenerationException _planError(GenerationPlan plan) {
    final String details = 'plan invalid: ${plan.validity.reason?.name}';
    return switch (plan.validity.reason) {
      PlanInvalidReason.contextWindowTooSmall ||
      PlanInvalidReason.unitTooLarge ||
      PlanInvalidReason.tooManyChunks => GenerationException(
        GenerationErrorCode.contextOverflow,
        details: details,
        failureReason: GenerationFailureReason.contextOverflow,
      ),
      PlanInvalidReason.payloadTooLarge => GenerationException(
        GenerationErrorCode.payloadTooLarge,
        details: details,
        failureReason: GenerationFailureReason.payloadTooLarge,
      ),
      PlanInvalidReason.imagesWithoutVision => GenerationException(
        GenerationErrorCode.visionUnsupported,
        details: details,
        failureReason: GenerationFailureReason.unsupportedModality,
      ),
      null => GenerationException(
        GenerationErrorCode.badRequest,
        details: details,
      ),
    };
  }

  @override
  Future<GenerationRunResult> retryFailed(
    GenerationRunRequest request,
    GenerationRunResult previous, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) async {
    final List<GenerationChunkFailure> retryable = previous.failures
        .where((failure) => failure.retryable)
        .toList(growable: false);
    if (retryable.isEmpty) return previous;
    _imageCache.clear();
    _usedImageUrls.clear();
    _resetImageBudget();

    final GenerationJob job =
        await jobRepository.jobById(previous.jobId) ??
        GenerationJob(
          id: previous.jobId,
          status: GenerationJobStatus.partial,
          createdAt: now(),
          provider: request.account.id,
          model: request.account.modelId,
          promptVersion: systemPromptVersion,
          files: _fileNames(request),
        );
    final Set<String> seen = <String>{
      ..._hashesOfCards(previous.cards),
      ...?await _existingHashes(request.targetDeckId),
    };
    final List<PlannedChunk> chunks = <PlannedChunk>[
      for (final GenerationChunkFailure failure in retryable)
        failure.plannedChunk ?? _plannedFromFailure(failure),
    ];

    try {
      return await _process(
        request: request,
        job: job.copyWith(
          status: GenerationJobStatus.running,
          clearErrorCode: true,
        ),
        plan: previous.plan,
        chunks: chunks,
        seen: seen,
        estimate: previous.estimatedTokens,
        initialCards: previous.cards,
        initialTokens: previous.tokensUsed,
        initialProcessed: previous.chunkCount,
        initialDuplicates: previous.duplicatesRemoved,
        initialRejected: previous.rejectedCards,
        onProgress: onProgress,
        cancellation: cancellation,
      );
    } on Object {
      await _markUnexpected(previous.jobId, job);
      rethrow;
    }
  }

  /// Общий цикл обработки фрагментов плана (первый запуск и повтор упавших).
  Future<GenerationRunResult> _process({
    required GenerationRunRequest request,
    required GenerationJob job,
    required GenerationPlan? plan,
    required List<PlannedChunk> chunks,
    required Set<String> seen,
    required int estimate,
    required GenerationProgressCallback? onProgress,
    required GenerationCancellation? cancellation,
    List<GeneratedCard> initialCards = const <GeneratedCard>[],
    int initialTokens = 0,
    int initialProcessed = 0,
    int initialDuplicates = 0,
    int initialRejected = 0,
  }) async {
    final List<_QueueItem> queue = <_QueueItem>[
      for (final PlannedChunk chunk in chunks) _QueueItem(chunk),
    ];
    _renumber(queue);
    final List<GeneratedCard> cards = List<GeneratedCard>.of(initialCards);
    final List<GenerationChunkFailure> failures = <GenerationChunkFailure>[];
    var tokensUsed = initialTokens;
    var processed = initialProcessed;
    var duplicates = initialDuplicates;
    var rejected = initialRejected;
    var recoveryRequests = 0;
    var failedRequests = 0;
    final int recoveryBudget = _recoveryBudgetFor(plan);
    final List<TokenCalibrationSample> calibrationSamples =
        <TokenCalibrationSample>[];
    final Set<String> sentDocumentImageIds = <String>{};
    var cancelled = false;
    GenerationException? fatal;
    // Компактное состояние prompt-only: исходные карточки (при повторе) и всё
    // принятое в этом запуске. Для материаловых планов не используется.
    final bool promptOnly = plan?.isPromptOnly ?? false;
    final ModelCapabilities capabilities = await _capabilitiesFor(
      request.account,
    );
    final GenerationContinuityState continuity = GenerationContinuityState(
      estimator: planBuilder.estimator,
    );
    if (promptOnly && initialCards.isNotEmpty) continuity.addAll(initialCards);

    var index = 0;
    // ADR-040 §8: исчерпание материала и однократное перераспределение.
    final Set<String> exhaustedSections = <String>{};
    final List<_BatchTokenFact> batchFacts = <_BatchTokenFact>[];
    var shortfall = 0;
    var skippedBatches = 0;
    var redistributed = false;
    while (index < queue.length) {
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      final _QueueItem item = queue[index];
      PlannedChunk chunk = item.chunk;
      final List<String> allSections = _sectionsOf(plan, chunk);
      // Исчерпанные разделы не запрашиваются; партия с новыми разделами
      // продолжает работу с сокращённым focus (ADR-040 §8).
      final List<String> chunkSections = <String>[
        for (final String section in allSections)
          if (!exhaustedSections.contains(section)) section,
      ];
      if (chunkSections.isEmpty && allSections.isNotEmpty) {
        skippedBatches++;
        shortfall += chunk.limit;
        queue.removeAt(index);
        _renumber(queue);
        await _saveProgress(job, processed, cards.length, tokensUsed);
        continue;
      }
      if (chunkSections.length != allSections.length) {
        chunk = chunk.copyWith(
          focusSectionIds: List<String>.unmodifiable(chunkSections),
        );
      }
      // id изображений назначаются один раз по порядку плана: повторная
      // нумерация по порядку партии ломала бы стабильность `<images>` и
      // `image_id` между запросами. Порядок каталога — по id.
      final Map<String, String> imageIds = _imageIdsFor(plan);
      final List<DocumentImage> documentImages = <DocumentImage>[
        for (final DocumentImage image in <DocumentImage>[
          ...chunk.imageParts,
          ...chunk.catalogOnly,
        ])
          image.withId(imageIds[_imageKey(image)] ?? image.id),
      ]..sort(_compareImageIds);
      // Контракт сервиса: `documentImageParts` — явный список отправляемых
      // image-частей, а не префикс каталога (v8, ADR-040 §7).
      final List<DocumentImage> documentImageParts = chunk.imageParts.isEmpty
          ? const <DocumentImage>[]
          : List<DocumentImage>.unmodifiable(<DocumentImage>[
              for (final DocumentImage image in chunk.imageParts)
                image.withId(imageIds[_imageKey(image)] ?? image.id),
            ]);
      onProgress?.call(
        GenerationProgress(
          phase: GenerationProgressPhase.sending,
          chunkIndex: index + 1,
          chunkCount: queue.length,
        ),
      );

      GenerationResult result;
      try {
        result = await caller.generate(
          GenerationRequest(
            account: request.account,
            materialsText: chunk.materialsText,
            wishes: request.wishes,
            limit: chunk.limit,
            images: chunk.attachments,
            documentImages: documentImages,
            documentImageParts: documentImageParts,
            // v8: дайджест уже принятых карточек уходит в <already_created>,
            // а не в <wishes>; continuation оставлен как legacy-канал.
            continuation: null,
            alreadyCreated: promptOnly
                ? continuity.block
                : _digestOf(cards, chunkSections),
            outline: _outlineOf(plan, chunk),
            focusSectionIds: chunk.focusSectionIds,
            partIndexHint: plan == null ? null : chunk.partIndex + 1,
            partCountHint: plan == null ? null : chunk.partCount,
            contextOnly: null,
            maxOutputTokens: _maxOutputTokensFor(
              plan,
              chunk,
              outputBoosted: item.outputBoosted,
            ),
          ),
          cancelToken: cancellation?.token,
        );
      } on GenerationException catch (error) {
        if (error.code == GenerationErrorCode.cancelled ||
            (cancellation?.isCancelled ?? false)) {
          cancelled = true;
          break;
        }
        if (_fatalCodes.contains(error.code)) {
          fatal = error;
          break;
        }
        failedRequests++;
        // Восстановление: дробим только проблемную часть плана. Rate limit,
        // сеть, auth и прочие ошибки не дробят материалы (F.2).
        final _Recovery? recovery = _recoveryFor(
          chunk,
          item,
          error,
          plan,
          capabilities,
        );
        if (recovery != null) {
          final int extra = recovery.chunks.length == 1
              ? 1
              : recovery.chunks.length - 1;
          if (recoveryRequests + extra <= recoveryBudget) {
            recoveryRequests += extra;
            queue.replaceRange(index, index + 1, <_QueueItem>[
              for (final PlannedChunk planned in recovery.chunks)
                _QueueItem(
                  planned,
                  attempts: item.attempts + 1,
                  limitReduced: item.limitReduced || recovery.limitReduced,
                  outputBoosted: recovery.outputBoosted,
                ),
            ]);
            _renumber(queue);
            continue;
          }
        }
        processed++;
        failures.add(
          _failureOf(
            chunk,
            error.code,
            providerReason: error.providerReason,
            reason: error.reason,
            chunkCount: queue.length,
            retryAfter: error.retryAfter,
            attempts: item.attempts + 1,
          ),
        );
        await _saveProgress(job, processed, cards.length, tokensUsed);
        index++;
        continue;
      } on Object {
        // Непредвиденная ошибка адаптера: карточки фрагмента не принимаются,
        // остальные фрагменты продолжаются (A6.8 «частичный успех»).
        failedRequests++;
        processed++;
        failures.add(
          _failureOf(
            chunk,
            GenerationErrorCode.invalidResponse,
            reason: GenerationFailureReason.unknown,
            chunkCount: queue.length,
            attempts: item.attempts + 1,
          ),
        );
        await _saveProgress(job, processed, cards.length, tokensUsed);
        index++;
        continue;
      }

      rejected += result.rejectedCards;
      tokensUsed += result.usage.totalTokens ?? 0;
      processed++;
      sentDocumentImageIds.addAll(result.sentDocumentImageIds);
      calibrationSamples.add(
        _calibrationSample(
          plan: plan,
          chunk: chunk,
          item: item,
          result: result,
        ),
      );
      if (result.skippedDocumentImageIds.isNotEmpty) {
        diagnostics.imageParticipation(
          outcome:
              'сервис исключил image-части: '
              '${result.skippedDocumentImageIds.join(', ')}',
        );
      }
      // 7.14: карточки попадают в результат сразу после ответа модели, а
      // картинки догружаются следом. UI получает снимок на каждом шаге, поэтому
      // показ колоды не ждёт сетевого поиска.
      final int imageStart = cards.length;
      for (final GeneratedCard card in result.cards) {
        if (_acceptCard(card, seen, cards)) {
          cards.add(card);
        } else {
          duplicates++;
        }
      }
      final int acceptedInChunk = cards.length - imageStart;
      if (result.usage.completionTokens != null && acceptedInChunk > 0) {
        batchFacts.add(
          _BatchTokenFact(
            completionTokens: result.usage.completionTokens!,
            acceptedCards: acceptedInChunk,
          ),
        );
      }
      // Исчерпание: явный флаг модели или недобор меньше половины партии.
      final bool exhausted =
          result.sourceExhausted ||
          (chunk.limit >= 2 && acceptedInChunk * 2 < chunk.limit);
      if (exhausted && chunkSections.isNotEmpty) {
        exhaustedSections.addAll(chunkSections);
        final int deficit = chunk.limit - acceptedInChunk;
        if (deficit > 0) shortfall += deficit;
      }
      // Состояние продолжения prompt-only: только принятые карточки, чтобы
      // сводка не включала дубли и не раздувалась.
      if (promptOnly && imageStart < cards.length) {
        continuity.addAll(cards.sublist(imageStart));
      }
      onProgress?.call(
        GenerationProgress(
          phase: GenerationProgressPhase.receiving,
          chunkIndex: index + 1,
          chunkCount: queue.length,
          cards: List<GeneratedCard>.unmodifiable(cards),
          imagesPending: imageStart < cards.length,
        ),
      );
      for (
        var imageIndex = imageStart;
        imageIndex < cards.length;
        imageIndex++
      ) {
        cards[imageIndex] = await _withCardImage(
          cards[imageIndex],
          documentImages,
          cancellation,
          wishes: request.wishes,
        );
        onProgress?.call(
          GenerationProgress(
            phase: GenerationProgressPhase.receiving,
            chunkIndex: index + 1,
            chunkCount: queue.length,
            cards: List<GeneratedCard>.unmodifiable(cards),
            imagesPending: imageIndex + 1 < cards.length,
          ),
        );
      }
      await _saveProgress(job, processed, cards.length, tokensUsed);
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      index++;
      // Однократное перераспределение недостачи на разделы с оставшейся
      // ёмкостью (ADR-040 §8): не больше одной дополнительной партии.
      if (index >= queue.length &&
          !redistributed &&
          shortfall > 0 &&
          !cancelled &&
          fatal == null &&
          plan != null &&
          initialCards.isEmpty) {
        final PlannedChunk? topUp = _topUpChunk(
          plan,
          exhaustedSections,
          shortfall,
          queue.length + 1,
          maxLimit: capabilities.maxCardsPerRequest,
        );
        if (topUp != null && recoveryRequests < recoveryBudget) {
          recoveryRequests++;
          redistributed = true;
          queue.add(_QueueItem(topUp));
          diagnostics.imageParticipation(
            outcome:
                'перераспределение недостачи: +${topUp.limit} карточек '
                '(focus: ${topUp.focusSectionIds.join(', ')})',
          );
        }
      }
    }

    final bool hasCards = cards.isNotEmpty;
    final GenerationJobStatus status;
    if (cancelled) {
      status = GenerationJobStatus.cancelled;
    } else if (fatal != null) {
      status = hasCards
          ? GenerationJobStatus.partial
          : GenerationJobStatus.error;
    } else if (failures.isEmpty) {
      status = GenerationJobStatus.done;
    } else if (!hasCards) {
      status = GenerationJobStatus.error;
    } else {
      status = GenerationJobStatus.partial;
    }
    final String? errorCode = fatal != null
        ? fatal.code.name
        : failures.isEmpty
        ? null
        : _failureCodesOf(failures);
    await jobRepository.save(
      job.copyWith(
        status: status,
        // ADR-040 §8: chunk_count — число частей входа, tokens_used — факт.
        chunkCount: plan?.partCount ?? processed,
        cardsCount: cards.length,
        tokensUsed: tokensUsed,
        errorCode: errorCode,
        clearErrorCode: errorCode == null,
      ),
    );
    await _recordCalibration(request.account, batchFacts);
    // Fatal без карточек — ошибка целиком; с карточками возвращаем результат,
    // чтобы пользователь мог открыть предпросмотр и сохранить полученное.
    if (fatal != null && !hasCards) throw fatal;

    final TokenCalibrationReport calibration = TokenCalibrationReport(
      samples: List<TokenCalibrationSample>.unmodifiable(calibrationSamples),
      failedRequests: failedRequests,
    );
    diagnostics.tokenCalibration(calibration);
    return GenerationRunResult(
      jobId: job.id,
      status: status,
      cards: List<GeneratedCard>.unmodifiable(cards),
      failures: List<GenerationChunkFailure>.unmodifiable(failures),
      tokensUsed: tokensUsed,
      estimatedTokens: estimate,
      duplicatesRemoved: duplicates,
      chunkCount: processed,
      cancelled: cancelled,
      rejectedCards: rejected,
      fatalErrorCode: fatal?.code,
      fatalProviderReason: fatal?.providerReason,
      plan: plan,
      calibration: calibration,
      recoveryRequestsUsed: recoveryRequests,
      recoveryBudget: recoveryBudget,
      sentDocumentImageIds: List<String>.unmodifiable(sentDocumentImageIds),
      shortfallCards: shortfall,
      skippedBatches: skippedBatches,
      exhaustedSectionIds: List<String>.unmodifiable(exhaustedSections),
    );
  }

  /// Действующий бюджет восстановления (F.2, L128).
  ///
  /// `maxRecoveryRequests` — явный предохранитель, но фиксированные 12 на
  /// план из сотен фрагментов — скрытое ограничение. Стратегия: не меньше
  /// конфигурационного значения и не меньше `plannedRequests / 8` (типичная
  /// доля фрагментов, требующих восстановления), верхняя граница 64. Ноль
  /// отключает восстановление явно.
  int _recoveryBudgetFor(GenerationPlan? plan) {
    return generationRecoveryBudget(
      plannedRequests: plan?.plannedRequests ?? 0,
      configured: maxRecoveryRequests,
    );
  }

  /// Сэмпл калибровки одного ответа: план vs собранный запрос vs `usage`.
  TokenCalibrationSample _calibrationSample({
    required GenerationPlan? plan,
    required PlannedChunk chunk,
    required _QueueItem item,
    required GenerationResult result,
  }) {
    final BudgetTrace? trace = plan?.budget;
    final int fixed =
        (trace?.systemPromptTokens ?? 0) +
        (trace?.schemaTokens ?? 0) +
        (trace?.wrapperTokens ?? 0);
    final TokenValue plannedInput = plan == null
        ? const TokenValue.unknown(source: 'plan')
        : TokenValue.estimate(
            fixed + chunk.textTokens + chunk.imageTokens,
            source: 'plan/${plan.estimate.estimatorVersion}',
          );
    final TokenValue requestInput = result.estimatedInputTokens == null
        ? const TokenValue.unknown(source: 'request-estimate-absent')
        : TokenValue.estimate(
            result.estimatedInputTokens!,
            source: result.estimatorVersion ?? 'request',
          );
    final TokenValue actualInput = result.usage.promptTokens == null
        ? const TokenValue.unknown(source: 'usage.prompt_tokens')
        : TokenValue.exact(
            result.usage.promptTokens!,
            source: 'usage.prompt_tokens',
          );
    final TokenValue actualOutput = result.usage.completionTokens == null
        ? const TokenValue.unknown(source: 'usage.completion_tokens')
        : TokenValue.exact(
            result.usage.completionTokens!,
            source: 'usage.completion_tokens',
          );
    final TokenValue reservedOutput = result.estimatedOutputTokens == null
        ? const TokenValue.unknown(source: 'request.maxOutputTokens')
        : TokenValue.reserve(
            result.estimatedOutputTokens!,
            source: 'request.maxOutputTokens',
          );
    return TokenCalibrationSample(
      chunkIndex: chunk.index,
      attempt: item.attempts + 1,
      recovered: item.attempts > 0,
      plannedInput: plannedInput,
      requestInput: requestInput,
      actualInput: actualInput,
      actualOutput: actualOutput,
      reservedOutput: reservedOutput,
      estimatorVersion:
          result.estimatorVersion ??
          plan?.estimate.estimatorVersion ??
          'unknown',
    );
  }

  /// Верхняя граница ответа для фрагмента: ожидаемый вывод плана (D.2).
  ///
  /// Резерв не может превышать `outputCap` плана; для старых результатов без
  /// плана — `null` (лимит аккаунта/сервиса). [outputBoosted] — вторая попытка
  /// после `truncated`: резерв поднимается до полного `outputCap` (F.4 шаг 2),
  /// а не остаётся уменьшенным ожиданием.
  int? _maxOutputTokensFor(
    GenerationPlan? plan,
    PlannedChunk chunk, {
    bool outputBoosted = false,
  }) {
    if (plan == null || plan.budget.outputCapTokens < 1) return null;
    if (outputBoosted) return plan.budget.outputCapTokens;
    final int expected =
        chunk.limit * kBudgetPerCardOutputTokens + kBudgetJsonEnvelopeTokens;
    return math.min(plan.budget.outputCapTokens, expected);
  }

  /// Дробление проблемного фрагмента (F.2/F.3/F.4, TASK 03).
  ///
  /// Порядок для `truncated` соответствует F.4: сначала уменьшается ожидаемый
  /// вывод (не вход!), затем поднимается резерв вывода, и только потом вход
  /// делится по единицам. `contextOverflow`/`payloadTooLarge` делят вход сразу;
  /// `rateLimited`, сеть, auth, невалидный JSON — не дробятся. Дети получают
  /// тот же оценщик и `imageTokenModel`, что и план (L129).
  _Recovery? _recoveryFor(
    PlannedChunk chunk,
    _QueueItem item,
    GenerationException error,
    GenerationPlan? plan,
    ModelCapabilities capabilities,
  ) {
    final GenerationPlanSplitter prepared = splitter.withContext(
      estimator: planBuilder.estimator,
      imageTokenModel: capabilities.imageTokens,
    );
    switch (error.code) {
      case GenerationErrorCode.truncated:
        // F.4.1: уменьшить ожидаемый вывод вдвое, вход не дробить.
        if (!item.limitReduced && chunk.limit > 1) {
          return _Recovery(<PlannedChunk>[
            chunk.copyWith(limit: math.max(1, chunk.limit ~/ 2)),
          ], limitReduced: true);
        }
        // F.4.2: поднять резерв вывода до потолка модели (одна попытка).
        if (!item.outputBoosted) {
          return _Recovery(
            <PlannedChunk>[chunk],
            limitReduced: item.limitReduced,
            outputBoosted: true,
          );
        }
        // F.4.3: последняя попытка — разделить вход; при `limit == 1` дети
        // получают по 1 карточке (осознанное исключение только для recovery).
        final List<PlannedChunk>? halves = prepared.split(
          chunk,
          allowLimitOverflow: true,
        );
        return halves == null ? null : _Recovery(halves);
      case GenerationErrorCode.contextOverflow:
      case GenerationErrorCode.payloadTooLarge:
        final List<PlannedChunk>? halves = prepared.split(
          chunk,
          allowLimitOverflow: true,
        );
        return halves == null ? null : _Recovery(halves);
      case GenerationErrorCode.missingApiKey:
      case GenerationErrorCode.providerNotConfigured:
      case GenerationErrorCode.invalidApiKey:
      case GenerationErrorCode.badRequest:
      case GenerationErrorCode.rateLimited:
      case GenerationErrorCode.serverUnavailable:
      case GenerationErrorCode.timeout:
      case GenerationErrorCode.network:
      case GenerationErrorCode.cancelled:
      case GenerationErrorCode.emptyResponse:
      case GenerationErrorCode.refused:
      case GenerationErrorCode.invalidResponse:
      case GenerationErrorCode.noMaterials:
      case GenerationErrorCode.visionUnsupported:
      case GenerationErrorCode.fileWithoutTextAndVision:
      case GenerationErrorCode.pdfScanUnsupported:
      case GenerationErrorCode.pdfScanVisionRequired:
      case GenerationErrorCode.attachmentTooLarge:
        return null;
    }
  }

  /// Перенумеровывает очередь после дробления (прогресс «фрагмент K из M»).
  void _renumber(List<_QueueItem> queue) {
    for (var index = 0; index < queue.length; index++) {
      final PlannedChunk chunk = queue[index].chunk;
      if (chunk.index != index + 1) {
        queue[index] = queue[index].withChunk(chunk.copyWith(index: index + 1));
      }
    }
  }

  /// Можно ли повторять фрагмент кнопкой «Повторить неудавшиеся» (F.5).
  ///
  /// Детерминированные ошибки (ключ, модальность, размер вложения, отказ
  /// модели, исчерпанные варианты дробления) не повторяются без изменений.
  bool _isRetryable(GenerationErrorCode code) {
    return switch (code) {
      GenerationErrorCode.missingApiKey ||
      GenerationErrorCode.providerNotConfigured ||
      GenerationErrorCode.invalidApiKey ||
      GenerationErrorCode.noMaterials ||
      GenerationErrorCode.visionUnsupported ||
      GenerationErrorCode.fileWithoutTextAndVision ||
      GenerationErrorCode.pdfScanUnsupported ||
      GenerationErrorCode.pdfScanVisionRequired ||
      GenerationErrorCode.attachmentTooLarge ||
      GenerationErrorCode.refused ||
      GenerationErrorCode.contextOverflow ||
      GenerationErrorCode.payloadTooLarge => false,
      GenerationErrorCode.badRequest ||
      GenerationErrorCode.rateLimited ||
      GenerationErrorCode.serverUnavailable ||
      GenerationErrorCode.timeout ||
      GenerationErrorCode.network ||
      GenerationErrorCode.cancelled ||
      GenerationErrorCode.emptyResponse ||
      GenerationErrorCode.truncated ||
      GenerationErrorCode.invalidResponse => true,
    };
  }

  /// Восстанавливает фрагмент из старого результата (без `plannedChunk`).
  PlannedChunk _plannedFromFailure(GenerationChunkFailure failure) {
    final String text = failure.materialsText;
    final bool hasText = text.trim().isNotEmpty;
    final bool hasParts =
        failure.documentImages.isNotEmpty || failure.images.isNotEmpty;
    final ChunkKind kind = hasText
        ? (hasParts ? ChunkKind.mixed : ChunkKind.text)
        : hasParts
        ? ChunkKind.images
        : ChunkKind.promptOnly;
    final List<UnitSpan> units = hasText
        ? <UnitSpan>[
            UnitSpan(
              unitId: 'retry:${failure.chunkIndex}',
              start: 0,
              end: text.length,
              tokens: 0,
            ),
          ]
        : const <UnitSpan>[];
    return PlannedChunk(
      index: math.max(1, failure.chunkIndex),
      kind: kind,
      units: units,
      imageParts: failure.documentImages,
      attachments: failure.images,
      textTokens: 0,
      imageTokens: 0,
      bodyBytes: 0,
      limit: math.max(1, failure.limit),
      splitDepth: failure.splitAttempted ? 1 : 0,
      materialsText: text,
    );
  }

  /// Машинные коды причин упавших фрагментов через запятую (fix-gen, Д6):
  /// `generation_jobs.error_code` = перечень причин, отладочный лог — по одной
  /// строке на фрагмент.
  String _failureCodesOf(List<GenerationChunkFailure> failures) {
    final List<String> codes = <String>[];
    for (final GenerationChunkFailure failure in failures) {
      final String code =
          (failure.reason ?? GenerationFailureReason.forErrorCode(failure.code))
              .code;
      if (!codes.contains(code)) codes.add(code);
    }
    return codes.join(',');
  }

  /// Привязывает картинку к карточке (fix-gen, Д2/Д3; 7.14 — картинка у каждой).
  ///
  /// Приоритет 1 — изображение из прикреплённого файла по `image_id`; байты
  /// берутся из каталога фрагмента, внешний поиск не вызывается. Приоритет 2 —
  /// внешний поиск по `image.query` → `image.fallback_query`. Если не помог
  /// никто, для обычной карточки создаётся детерминированная заглушка (шаг 3);
  /// occlusion без реальной картинки остаётся без иллюстрации (маска на
  /// заглушке бессмысленна) — карточка становится обычной с пометкой.
  Future<GeneratedCard> _withCardImage(
    GeneratedCard card,
    List<DocumentImage> documentImages,
    GenerationCancellation? cancellation, {
    required String? wishes,
  }) async {
    if (card.image != null) return card;
    if (wishesForbidImages(wishes)) {
      return _withoutImage(card.clearedImageSelection());
    }
    final String? imageId = card.imageId?.trim();
    if (imageId != null && imageId.isNotEmpty) {
      final DocumentImage? documentImage = _documentImageById(
        documentImages,
        imageId,
      );
      if (documentImage != null) {
        diagnostics.imageSearch(
          query: 'image_id:$imageId',
          outcome:
              'изображение из файла ${documentImage.fileName} '
              '(${documentImage.bytes.length} Б)',
        );
        return card.copyWith(
          image: GeneratedCardImage(
            bytes: documentImage.bytes,
            mediaType: documentImage.mediaType,
            query: card.imageQuery ?? '',
            kind: card.imageKind,
            fallbackQuery: card.imageFallbackQuery,
            provider: 'file',
            attribution: documentImage.caption ?? documentImage.fileName,
          ),
          occlusionJson: card.isOcclusion
              ? card.occlusionJson ?? defaultOcclusionDocumentJson()
              : card.occlusionJson,
        );
      }
    }
    final String? query = card.imageQuery?.trim();
    if (query == null ||
        query.isEmpty ||
        imageFinder == null ||
        (cancellation?.isCancelled ?? false)) {
      return _placeholderOrNothing(card);
    }
    final DateTime? searchStartedAt = _imageSearchBudgeted ? now() : null;
    final bool budgetExhausted =
        _imageSearchBudgeted && _imageSearchSpent >= imageSearchBudget;
    if (budgetExhausted) {
      diagnostics.imageSearch(
        query: query,
        outcome: 'пропущен: бюджет времени поиска исчерпан',
      );
      return _placeholderOrNothing(card, imageNotFound: true);
    }
    GeneratedCardImage? image;
    try {
      image = await _imageCache.putIfAbsent(
        query,
        () => imageFinder!.findImage(
          query,
          fallbackQuery: card.imageFallbackQuery,
          kind: card.imageKind,
          excludedSourceUrls: _usedImageUrls,
        ),
      );
    } on Object {
      _imageCache.remove(query);
      image = null;
    }
    if (searchStartedAt != null) {
      _imageSearchSpent += now().difference(searchStartedAt);
    }
    if (image == null) {
      _imageCache.remove(query);
      return _placeholderOrNothing(card, imageNotFound: true);
    }
    final String? sourceUrl = image.sourceUrl;
    // Один и тот же URL не должен попасть в колоду дважды (7.14): кэш по
    // запросу может вернуть картинку, уже занятую другой карточкой.
    if (sourceUrl != null && !_usedImageUrls.add(sourceUrl)) {
      _imageCache.remove(query);
      return _placeholderOrNothing(card, imageNotFound: true);
    }
    return card.copyWith(
      image: image,
      occlusionJson: card.isOcclusion
          ? card.occlusionJson ?? defaultOcclusionDocumentJson()
          : card.occlusionJson,
    );
  }

  /// Заглушка вместо не найденной картинки; occlusion остаётся без иллюстрации.
  GeneratedCard _placeholderOrNothing(
    GeneratedCard card, {
    bool imageNotFound = false,
  }) {
    if (card.isOcclusion) {
      return _withoutImage(card, imageNotFound: imageNotFound);
    }
    final PlaceholderImageGenerator? generator = placeholderGenerator;
    if (generator == null) {
      return _withoutImage(card, imageNotFound: imageNotFound);
    }
    final GeneratedCardImage placeholder = generator.generate(
      // Seed — хэш содержимого: одна и та же карточка всегда получает одну и
      // ту же заглушку (id появляется только при импорте в БД).
      seed: contentHashOf(front: card.front, back: card.back),
      kind: card.imageKind,
      query: card.imageQuery,
      fallbackQuery: card.imageFallbackQuery,
    );
    return card.copyWith(
      image: placeholder,
      issues: List<CardIssueCode>.unmodifiable(<CardIssueCode>[
        ...card.issues,
        if (imageNotFound && !card.issues.contains(CardIssueCode.imageNotFound))
          CardIssueCode.imageNotFound,
      ]),
    );
  }

  /// Изображение фрагмента по идентификатору каталога; `null` — нет такого.
  DocumentImage? _documentImageById(List<DocumentImage> images, String id) {
    for (final DocumentImage image in images) {
      if (image.id == id) return image;
    }
    return null;
  }

  /// Сбрасывает счётчик бюджета поиска иллюстраций (начало запуска/повтора).
  void _resetImageBudget() {
    _imageSearchSpent = Duration.zero;
  }

  /// Карточка без картинки: occlusion без иллюстрации становится обычной,
  /// неудачный поиск оставляет пометку для предупреждения в UI (ADR-028).
  GeneratedCard _withoutImage(
    GeneratedCard card, {
    bool imageNotFound = false,
  }) {
    var result = card;
    if (card.isOcclusion) {
      result = result.copyWith(
        isOcclusion: false,
        issues: List<CardIssueCode>.unmodifiable(<CardIssueCode>[
          ...result.issues,
          if (!result.issues.contains(CardIssueCode.occlusionImageMissing))
            CardIssueCode.occlusionImageMissing,
        ]),
      );
    }
    if (imageNotFound && !result.issues.contains(CardIssueCode.imageNotFound)) {
      result = result.copyWith(
        issues: List<CardIssueCode>.unmodifiable(<CardIssueCode>[
          ...result.issues,
          CardIssueCode.imageNotFound,
        ]),
      );
    }
    return result;
  }

  /// Сохраняет пошаговый прогресс задания (`generation_jobs` A8.5 шаг 12).
  Future<void> _saveProgress(
    GenerationJob job,
    int processed,
    int cardsCount,
    int tokensUsed,
  ) {
    return jobRepository.save(
      job.copyWith(
        status: GenerationJobStatus.running,
        chunkCount: processed,
        cardsCount: cardsCount,
        tokensUsed: tokensUsed,
      ),
    );
  }

  /// Помечает задание `error`, если оно осталось `running` после сбоя.
  Future<void> _markUnexpected(String jobId, GenerationJob initialJob) async {
    try {
      final GenerationJob? current = await jobRepository.jobById(jobId);
      if (current != null && current.status != GenerationJobStatus.running) {
        return;
      }
      await jobRepository.save(
        initialJob.copyWith(
          status: GenerationJobStatus.error,
          errorCode: _unexpectedErrorCode,
        ),
      );
    } on Object {
      // Best-effort: исходная ошибка важнее состояния журнала.
    }
  }

  /// Хеши карточек целевой колоды; без колоды — пусто.
  Future<Set<String>?> _existingHashes(String? deckId) async {
    if (deckId == null) return null;
    return cardStore.existingContentHashes(deckId);
  }

  /// Описание упавшего фрагмента для повтора plus запись причины в лог.
  GenerationChunkFailure _failureOf(
    PlannedChunk chunk,
    GenerationErrorCode code, {
    String? providerReason,
    GenerationFailureReason? reason,
    int? chunkCount,
    Duration? retryAfter,
    int attempts = 1,
  }) {
    final GenerationFailureReason effective =
        reason ?? GenerationFailureReason.forErrorCode(code);
    diagnostics.fragmentFailure(
      chunkIndex: chunk.index,
      chunkCount: chunkCount ?? 1,
      errorCode: code.name,
      reason: effective.code,
    );
    return GenerationChunkFailure(
      chunkIndex: chunk.index,
      code: code,
      materialsText: chunk.materialsText,
      limit: chunk.limit,
      sourceFiles: _sourceFilesOf(chunk),
      splitAttempted: chunk.splitDepth > 0,
      providerReason: providerReason,
      images: chunk.attachments,
      documentImages: List<DocumentImage>.unmodifiable(<DocumentImage>[
        ...chunk.imageParts,
        ...chunk.catalogOnly,
      ]),
      reason: effective,
      retryable: _isRetryable(code),
      plannedChunk: chunk,
      retryAfter: retryAfter,
      attempts: attempts,
    );
  }

  /// Имена файлов фрагмента для журнала/повтора.
  List<String> _sourceFilesOf(PlannedChunk chunk) {
    final List<String> names = <String>[];
    void add(String name) {
      if (name.isEmpty || names.contains(name)) return;
      names.add(name);
    }

    for (final UnitSpan span in chunk.units) {
      final String id = span.unitId;
      if (!id.startsWith('doc:')) continue;
      final int hash = id.indexOf('#');
      if (hash > 4) add(id.substring(4, hash));
    }
    for (final DocumentImage image in chunk.imageParts) {
      add(image.fileName);
    }
    for (final DocumentImage image in chunk.catalogOnly) {
      add(image.fileName);
    }
    for (final GenerationAttachment attachment in chunk.attachments) {
      add(attachment.fileName);
    }
    return List<String>.unmodifiable(names);
  }

  /// Принимает карточку, если её хеш новый и нет почти-дубля (ADR-040 §8).
  ///
  /// Точный дубль — по `content_hash` (и обратному для reversed); почти-дубль —
  /// сходство триграмм `front` ≥ 0.85 в пределах запуска.
  bool _acceptCard(
    GeneratedCard card,
    Set<String> seen,
    List<GeneratedCard> accepted,
  ) {
    final String hash = contentHashOf(front: card.front, back: card.back);
    final String? reversed = card.cardType == CardType.basicReversed
        ? contentHashOf(front: card.back, back: card.front)
        : null;
    if (seen.contains(hash) || (reversed != null && seen.contains(reversed))) {
      return false;
    }
    for (final GeneratedCard other in accepted) {
      if (_frontSimilarity(card.front, other.front) >= 0.85) return false;
    }
    seen.add(hash);
    if (reversed != null) seen.add(reversed);
    return true;
  }

  /// Сходство `front` по триграммам (Jaccard, 0..1).
  ///
  /// Для очень коротких сторон (< 12 букв) почти-дубль не определяется: у
  /// «Вопрос 1»/«Вопрос 2» триграммы совпадают естественно, а точный хеш уже
  /// проверен отдельно.
  static double _frontSimilarity(String a, String b) {
    if (_lettersCount(a) < 12 || _lettersCount(b) < 12) return 0;
    final Set<String> first = _trigramsOf(a);
    final Set<String> second = _trigramsOf(b);
    if (first.isEmpty || second.isEmpty) {
      return first.isEmpty && second.isEmpty ? 1 : 0;
    }
    final Set<String> union = <String>{...first, ...second};
    final int intersection = first.where(second.contains).length;
    return intersection / union.length;
  }

  static int _lettersCount(String value) =>
      RegExp(r'\p{L}', unicode: true).allMatches(value).length;

  static Set<String> _trigramsOf(String value) {
    final String normalized = value
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\p{L}\p{N} ]+', unicode: true), '')
        .trim();
    if (normalized.length < 3) return <String>{normalized};
    return <String>{
      for (var index = 0; index + 3 <= normalized.length; index++)
        normalized.substring(index, index + 3),
    };
  }

  /// Устойчивый ключ изображения в плане.
  static String _imageKey(DocumentImage image) =>
      '${image.fileName}|${image.page ?? ''}|${image.caption}|'
      '${image.bytes.length}';

  /// Стабильные display-id (`img1…`) по порядку плана (ADR-040 §7).
  static Map<String, String> _imageIdsFor(GenerationPlan? plan) {
    if (plan == null) return const <String, String>{};
    final Map<String, String> ids = <String, String>{};
    for (final PlannedChunk chunk in plan.chunks) {
      for (final DocumentImage image in <DocumentImage>[
        ...chunk.imageParts,
        ...chunk.catalogOnly,
      ]) {
        ids.putIfAbsent(_imageKey(image), () => 'img${ids.length + 1}');
      }
    }
    return ids;
  }

  /// Порядок изображений по числовому id (`img2` < `img10`).
  static int _compareImageIds(DocumentImage a, DocumentImage b) {
    int numeric(String id) {
      final String digits = id.replaceAll(RegExp(r'[^0-9]'), '');
      return int.tryParse(digits) ?? 0;
    }

    return numeric(a.id).compareTo(numeric(b.id));
  }

  /// Разделы запроса: `focus` или все разделы части (для исчерпания).
  List<String> _sectionsOf(GenerationPlan? plan, PlannedChunk chunk) {
    if (plan == null ||
        chunk.partIndex < 0 ||
        chunk.partIndex >= plan.parts.length) {
      return const <String>[];
    }
    if (chunk.focusSectionIds.isNotEmpty) {
      return List<String>.unmodifiable(chunk.focusSectionIds);
    }
    final InputPart part = plan.parts[chunk.partIndex];
    return List<String>.unmodifiable(
      part.sections.map((InputSection section) => section.promptId),
    );
  }

  /// Оглавление части (v8) для текущей партии.
  String? _outlineOf(GenerationPlan? plan, PlannedChunk chunk) {
    if (plan == null ||
        chunk.partIndex < 0 ||
        chunk.partIndex >= plan.parts.length) {
      return null;
    }
    final String outline = plan.parts[chunk.partIndex].outlineText.trim();
    return outline.isEmpty ? null : outline;
  }

  /// Компактный дайджест принятых карточек для `<already_created>` (≤5 %).
  String? _digestOf(List<GeneratedCard> cards, List<String> focusSections) {
    if (cards.isEmpty) return null;
    final Set<String> focus = focusSections.toSet();
    final List<GeneratedCard> sorted = <GeneratedCard>[
      for (final GeneratedCard card in cards)
        if (card.sectionId != null && focus.contains(card.sectionId)) card,
      ...cards.where(
        (GeneratedCard card) =>
            card.sectionId == null || !focus.contains(card.sectionId),
      ),
    ];
    final Set<String> seenFronts = <String>{};
    final StringBuffer buffer = StringBuffer();
    for (final GeneratedCard card in sorted) {
      final String front = card.front.trim();
      if (front.isEmpty || !seenFronts.add(front)) continue;
      final String line =
          '- ${front.length > 80 ? '${front.substring(0, 80)}…' : front}';
      if (buffer.length + line.length + 1 > 1200) break;
      if (buffer.isNotEmpty) buffer.write('\n');
      buffer.write(line);
      if (seenFronts.length >= 20) break;
    }
    return buffer.isEmpty ? null : buffer.toString();
  }

  /// Дополнительная партия для недостачи (одна, ADR-040 §8).
  PlannedChunk? _topUpChunk(
    GenerationPlan plan,
    Set<String> exhausted,
    int shortfall,
    int index, {
    int? maxLimit,
  }) {
    if (shortfall < 1) return null;
    for (final InputPart part in plan.parts) {
      final List<String> allowed = <String>[
        for (final InputSection section in part.sections)
          if (!exhausted.contains(section.promptId) &&
              (plan.allocation?.forSection(section.id) ?? 0) > 0)
            section.promptId,
      ];
      if (allowed.isEmpty) continue;
      PlannedChunk? base;
      for (final PlannedChunk chunk in plan.chunks) {
        if (chunk.partIndex == part.index && chunk.units.isNotEmpty) {
          base = chunk;
          break;
        }
      }
      if (base == null) continue;
      final int limit = shortfall.clamp(1, maxLimit ?? 40).clamp(1, 40).toInt();
      return base.copyWith(
        index: index,
        limit: limit,
        focusSectionIds: List<String>.unmodifiable(allowed),
        imageParts: const <DocumentImage>[],
        imagePartIds: const <String>[],
      );
    }
    return null;
  }

  /// Записывает калибровку партий в `generation.calibration` (ADR-040 §9).
  Future<void> _recordCalibration(
    ProviderAccount account,
    List<_BatchTokenFact> facts,
  ) async {
    final TokenCalibrationStore? store = calibrationStore;
    if (store == null || facts.isEmpty) return;
    var completion = 0;
    var accepted = 0;
    for (final _BatchTokenFact fact in facts) {
      completion += fact.completionTokens;
      accepted += fact.acceptedCards;
    }
    if (accepted <= 0) return;
    try {
      // Один замер на прогон: суммарный usage / принятые карточки — устойчивее
      // покараточных выбросов и меньше записей в app_settings.
      await store.record(
        accountId: account.id,
        model: account.modelId,
        observedTokensPerCard: completion / accepted,
      );
    } on Object {
      // Калибровка не должна ломать генерацию.
    }
  }

  /// Возможности модели: кэш `providerApi` (если есть) → каталог/аккаунт.
  ///
  /// Сеть здесь не вызывается: discovery обновляет кэш отдельно (ADR-039 §4).
  Future<ModelCapabilities> _capabilitiesFor(ProviderAccount account) async {
    ModelCapabilityRecord? cached;
    final ModelCapabilityCache? cache = capabilityCache;
    if (cache != null) {
      try {
        cached = await cache.read(
          accountId: account.id,
          protocol: account.protocol,
          baseUrl: account.baseUrl,
          model: account.modelId,
        );
      } on Object {
        // Повреждённый кэш не блокирует генерацию: план идёт по каталогу.
        cached = null;
      }
    }
    return resolveModelCapabilities(account, cached: cached);
  }
}

/// Элемент очереди выполнения с состоянием восстановления.
class _QueueItem {
  _QueueItem(
    this.chunk, {
    this.attempts = 0,
    this.limitReduced = false,
    this.outputBoosted = false,
  });

  final PlannedChunk chunk;

  /// Сколько раз фрагмент уже дробился/сокращался.
  final int attempts;

  /// Ожидаемый вывод уже сокращался после `truncated`.
  final bool limitReduced;

  /// Резерв вывода уже поднят до `outputCap` после `truncated`.
  final bool outputBoosted;

  _QueueItem withChunk(PlannedChunk value) => _QueueItem(
    value,
    attempts: attempts,
    limitReduced: limitReduced,
    outputBoosted: outputBoosted,
  );
}

/// Результат решения о восстановлении: новые фрагменты и флаги попытки.
class _Recovery {
  const _Recovery(
    this.chunks, {
    this.limitReduced = false,
    this.outputBoosted = false,
  });

  final List<PlannedChunk> chunks;

  /// Эта попытка уменьшила ожидаемый вывод.
  final bool limitReduced;

  /// Эта попытка подняла резерв вывода.
  final bool outputBoosted;
}

/// Хеши карточек результата (для дедупликации при повторе).
Set<String> _hashesOfCards(List<GeneratedCard> cards) {
  final Set<String> hashes = <String>{};
  for (final GeneratedCard card in cards) {
    hashes.add(contentHashOf(front: card.front, back: card.back));
    if (card.cardType == CardType.basicReversed) {
      hashes.add(contentHashOf(front: card.back, back: card.front));
    }
  }
  return hashes;
}

DateTime _defaultNow() => DateTime.now();

/// Имена файлов задания без дублей (страницы одного PDF-скана считаются одним
/// файлом) в порядке появления (итерация 7.9).
List<String> _fileNames(GenerationRunRequest request) {
  final List<String> names = <String>[
    for (final document in request.documents) document.fileName,
  ];
  for (final image in request.images) {
    if (!names.contains(image.fileName)) names.add(image.fileName);
  }
  for (final image in request.documentImages) {
    if (!names.contains(image.fileName)) names.add(image.fileName);
  }
  return List<String>.unmodifiable(names);
}

String _defaultJobId() => const Uuid().v4();

/// Факт вывода одного ответа для калибровки `tokensPerCard`.
final class _BatchTokenFact {
  const _BatchTokenFact({
    required this.completionTokens,
    required this.acceptedCards,
  });

  final int completionTokens;
  final int acceptedCards;
}
