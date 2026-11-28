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

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/api/generation/generation_plan_entry.dart';
import 'package:cardflow/api/generation/source_anchor.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generated_card_image_side.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_continuity.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_metrics.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/generation_plan_splitter.dart';
import 'package:cardflow/domain/generation/generation_recovery_budget.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/image_query.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/output_batch_planner.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';
import 'package:cardflow/domain/generation/storage_failure.dart';

import 'package:cardflow/api/generation/exact_token_cache.dart';
import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/request_token_counter.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/text/text_sanitizer.dart';

/// Коды ошибок, после которых повторять следующие фрагменты бессмысленно.
const Set<GenerationErrorCode> _fatalCodes = <GenerationErrorCode>{
  GenerationErrorCode.missingApiKey,
  GenerationErrorCode.providerNotConfigured,
  GenerationErrorCode.invalidApiKey,
  GenerationErrorCode.insufficientBalance,
  GenerationErrorCode.noMaterials,
  GenerationErrorCode.storageUnavailable,
};

/// Код в `generation_jobs.error_code` для непредвиденного сбоя пайплайна/БД.
const String _unexpectedErrorCode = 'unexpected';

/// Строитель плана для тестов/встраивания (production использует
/// [GenerationPlanBuilder] и [PromptOnlyPlanner]).
typedef GenerationPlanFactory = GenerationPlan Function(
  GenerationRunRequest request,
  ModelCapabilities capabilities,
);

/// Путь генерации v3 (TASK «Срез 11», п. 8): тонкий фасад этапов, собранный
/// production-проводкой (`GenerationV3PathRunner`).
///
/// Раннер выбирает его **только** при включённом флаге `generationPipelineV3`;
/// выключенный флаг — прежний legacy-путь без изменений (протокол §9).
typedef GenerationV3Path = Future<GenerationRunResult> Function(
  GenerationRunRequest request, {
  required String runId,
  GenerationProgressCallback? onProgress,
  GenerationCancellation? cancellation,
});

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
  final int maxTopUpRounds;
  final int maxOperationRequests;
  final int maxOperationTokens;
  final int maxOperationSeconds;

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
    this.imageSearchBudget = const Duration(seconds: 90),
    this.diagnostics = const GenerationDiagnostics(),
    this.tokenCounter,
    this.tokenCountCache,
    this.now = _defaultNow,
    this.jobIdFactory = _defaultJobId,
    this.maxRecoveryRequests = 12,
    this.maxTopUpRounds = 4,
    this.maxOperationRequests = 0,
    this.maxOperationTokens = 0,
    this.maxOperationSeconds = 0,
    this.pipelineV3 = false,
    this.v3Path,
  }) : assert(maxRecoveryRequests >= 0);

  /// Путь генерации v3 (TASK «Срез 9», флаг `generationPipelineV3` в
  /// `app_settings`): пометка возможных дублей вместо удаления, вердикт
  /// завершения по журналу и метрики прогона. **Выключен** — прежнее поведение
  /// не меняется (протокол §9).
  final bool pipelineV3;

  /// production-путь v3 (срез 11): фасад этапов и отчёт прогона.
  ///
  /// Работает только при включённом [pipelineV3]; `null` — флаг не включает
  /// проводку, путь остаётся legacy (совместимость тестов среза 9).
  final GenerationV3Path? v3Path;

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

  /// Нативный подсчёт токенов входа (ADR-040 §3.5.1); `null` — без сети,
  /// только консервативная оценка. Вызывается **один раз на план**, результат
  /// кэшируется по хэшу содержимого запроса.
  final RequestTokenCounter? tokenCounter;

  /// Кэш нативного подсчёта; `null` — создаётся лениво на экземпляр пайплайна.
  final ExactTokenCountCache? tokenCountCache;

  /// Ленивый кэш нативного подсчёта (живёт вместе с пайплайном).
  ExactTokenCountCache? _tokenCache;

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
    // Путь v3: фасад этапов вместо монолита, только при включённом флаге и
    // наличии production-проводки (п. 8 среза 11). Выключен — legacy ниже.
    final GenerationV3Path? v3 = v3Path;
    if (pipelineV3 && v3 != null) {
      return v3(
        request,
        runId: jobId,
        onProgress: onProgress,
        cancellation: cancellation,
      );
    }
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

    try {
      // Запись задания — часть защищённого участка: сбой локального хранилища
      // (права на каталог данных, диск, блокировка БД) должен дойти до UI
      // конкретной причиной, а не общей строкой «Не удалось получить карточки».
      await jobRepository.save(initialJob);
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
      // Один нативный подсчёт входа на план (§3.5.1): точность запроса вместо
      // оценки, если провайдер её поддерживает. Сеть — только здесь, до
      // первого запроса генерации и без тела в диагностике.
      final GenerationPlan effectivePlan = await _withExactInput(
        plan: plan,
        request: request,
        capabilities: capabilities,
        hasMaterials: hasMaterials,
        topic: topic,
        builder: effectiveBuilder,
      );

      diagnostics.planSummary(
        strategy: effectivePlan.inputStrategy?.name ?? 'legacy',
        parts: effectivePlan.partCount,
        batches: effectivePlan.chunks.length,
        requestedCards: effectivePlan.requestedCards,
        achievableCards: effectivePlan.achievableCards,
        calibrated: calibration != null,
      );
      final Set<String> seen = <String>{
        ...?await _existingHashes(request.targetDeckId),
      };
      final GenerationRunResult result = await _process(
        request: request,
        job: initialJob,
        plan: effectivePlan,
        chunks: effectivePlan.chunks,
        seen: seen,
        estimate: effectivePlan.estimate.totalTokens,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return result;
    } on Object catch (error) {
      await _markUnexpected(jobId, initialJob);
      throw _unexpectedAsGeneration(error);
    }
  }

  /// Сбой вне вызова модели → доменный код, если это локальное хранилище.
  ///
  /// Сырые `SqliteException`/`DriftRemoteException`/`FileSystemException`
  /// (например, `SQLITE_READONLY` на каталоге данных) раньше доходили до экрана
  /// как произвольные исключения и показывались общей строкой. Теперь UI видит
  /// `storageUnavailable` и говорит, что именно недоступно. Прочие
  /// непредвиденные ошибки остаются как есть (их текст не подменяется).
  Object _unexpectedAsGeneration(Object error) {
    if (error is GenerationException) return error;
    if (!isStorageFailure(error)) return error;
    return GenerationException(
      GenerationErrorCode.storageUnavailable,
      details: 'pipeline storage failure: ${error.runtimeType}',
      failureReason: GenerationFailureReason.storage,
    );
  }

  /// Строит план: prompt-only по теме или по материалам (D.5/D.7).
  GenerationPlan _buildPlan(
    GenerationRunRequest request,
    ModelCapabilities capabilities, {
    required bool hasMaterials,
    required String? topic,
    GenerationPlanBuilder? builder,
    NativeInputCount? nativeCount,
    String? inputTokenSource,
  }) {
    final GenerationPlanFactory? factory = planFactory;
    if (factory != null) return factory(request, capabilities);
    final GenerationPlan? plan = buildRunPlan(
      builder: builder ?? planBuilder,
      request: request,
      capabilities: capabilities,
      nativeCount: nativeCount,
      inputTokenSource: inputTokenSource,
    );
    if (plan == null) {
      throw const GenerationException(GenerationErrorCode.noMaterials);
    }
    return plan;
  }

  /// Один нативный подсчёт входа на план (§2.2/§3.5.1).
  ///
  /// - счётчик выбирается по протоколу (`supports`), иначе — оценка;
  /// - для fragmented плана точный подсчёт целого запроса неприменим к части,
  ///   поэтому остаётся оценка;
  /// - результат кэшируется по хэшу содержимого запроса: повторный запуск с
  ///   тем же материалом не делает лишних сетевых обращений;
  /// - при ошибке — консервативная оценка и код ошибки в диагностике (без тела
  ///   запроса и ключей).
  Future<GenerationPlan> _withExactInput({
    required GenerationPlan plan,
    required GenerationRunRequest request,
    required ModelCapabilities capabilities,
    required bool hasMaterials,
    required String? topic,
    required GenerationPlanBuilder builder,
  }) async {
    final RequestTokenCounter? counter = tokenCounter;
    final InputPlan? inputPlan = plan.inputPlan;
    if (counter == null || inputPlan == null || !plan.isExecutable) {
      return plan;
    }
    if (inputPlan.accuracy == InputAccuracy.exact) return plan;
    if (!counter.supports(request.account)) {
      diagnostics.tokenCount(source: 'estimate', errorCode: 'unsupported');
      return plan;
    }
    if (inputPlan.strategy == InputStrategy.fragmented) {
      diagnostics.tokenCount(source: 'estimate', errorCode: 'fragmented');
      return plan;
    }
    final _CountedRequest? counted = _countedRequest(plan, request);
    if (counted == null) return plan;
    final ExactTokenCountCache cache =
        tokenCountCache ?? (_tokenCache ??= ExactTokenCountCache());
    final String key = exactTokenCacheKey(
      account: request.account,
      systemPrompt: systemPromptGenRuV9,
      userContent: counted.userContent,
      attachments: counted.attachments,
    );
    final ExactTokenCount count = await cache.countOrLoad(
      key: key,
      load: () => counter.count(
        request.account,
        systemPrompt: systemPromptGenRuV9,
        userContent: counted.userContent,
        attachments: counted.attachments,
      ),
    );
    if (!count.isExact) {
      diagnostics.tokenCount(source: 'estimate', errorCode: count.errorCode);
      return plan;
    }
    // §3: exact — только если нативно посчитаны **все** учитываемые части.
    // Изображения/PDF теперь уходят в count_tokens base64-блоками и входят в
    // число провайдера: повторно оценку изображений не прибавляем.
    final List<String> estimatedComponents = <String>[];
    var estimatedExtra = 0;
    if (request.account.protocol == ProviderProtocol.geminiGenerateContent) {
      // §7: вхождение generationConfig.responseSchema в `totalTokens` не
      // подтверждено документацией. Схема оценивается отдельно тем же
      // оценщиком плана, а не выдаётся за нативно посчитанную часть.
      final int schemaTokens = plan.estimate.schemaTokens;
      if (schemaTokens > 0) {
        estimatedExtra = schemaTokens;
        estimatedComponents.add(NativeInputCount.schemaComponent);
      }
    }
    final NativeInputCount nativeCount = NativeInputCount(
      tokens: count.tokens!,
      estimatedExtraTokens: estimatedExtra,
      estimatedComponents: List<String>.unmodifiable(estimatedComponents),
      source: 'count_tokens:${request.account.protocol.wireName}',
    );
    diagnostics.tokenCount(
      source: nativeCount.isFullyNative
          ? nativeCount.source
          : '${nativeCount.source}+estimate',
      tokens: nativeCount.tokens + nativeCount.estimatedExtraTokens,
    );
    return _buildPlan(
      request,
      capabilities,
      hasMaterials: hasMaterials,
      topic: topic,
      builder: builder,
      nativeCount: nativeCount,
    );
  }

  /// Запрос подсчёта ровно в том виде, в каком его увидит провайдер.
  ///
  /// Пользовательское сообщение собирается тем же `buildGenerationUserContent`
  /// (материалы + каталог + пожелания + хвост `<task>`), мультимодальные части —
  /// те же, что уйдут в production: вложения первого фрагмента части и все
  /// image-части плана с id и подписями каталога. В whole-режиме партии делят
  /// изображения между собой, поэтому подсчёт целого запроса покрывает все
  /// отправляемые части — бюджет другой партии не окажется занижен.
  _CountedRequest? _countedRequest(
    GenerationPlan plan,
    GenerationRunRequest request,
  ) {
    if (plan.chunks.isEmpty) return null;
    final String? userContent = _countedUserContent(plan, request);
    if (userContent == null) return null;
    final Map<String, String> imageIds = _imageIdsFor(plan);
    final List<GenerationAttachment> attachments = <GenerationAttachment>[
      for (final PlannedChunk chunk in plan.chunks) ...chunk.attachments,
      for (final PlannedChunk chunk in plan.chunks)
        for (final DocumentImage image in chunk.imageParts)
          if (image.bytes.isNotEmpty)
            GenerationAttachment(
              fileName: image.fileName,
              mediaType: image.mediaType,
              bytes: image.bytes,
              pageNumber: image.page,
              label: imageCatalogLine(
                image.withId(imageIds[_imageKey(image)] ?? image.id),
              ),
            ),
    ];
    return _CountedRequest(
      userContent: userContent,
      attachments: List<GenerationAttachment>.unmodifiable(attachments),
    );
  }

  /// Пользовательское сообщение первого запроса плана — ровно в том виде,
  /// в каком его соберёт `CardGenerationService` (материалы + каталог +
  /// пожелания + хвост `<task>`). Тело наружу не отдаётся: только число.
  String? _countedUserContent(
    GenerationPlan plan,
    GenerationRunRequest request,
  ) {
    if (plan.chunks.isEmpty) return null;
    final PlannedChunk chunk = plan.chunks.first;
    const TextSanitizer sanitizer = TextSanitizer();
    String materials = sanitizer.sanitize(chunk.materialsText);
    if (materials.isEmpty && chunk.attachments.isNotEmpty) {
      // Ровно как `CardGenerationService`: запрос только из вложений несёт
      // строки «Файл: <имя>» в материалах, иначе подсчёт видит меньше текста,
      // чем production-запрос.
      final List<String> names = <String>[];
      for (final GenerationAttachment attachment in chunk.attachments) {
        if (!names.contains(attachment.fileName)) {
          names.add(attachment.fileName);
        }
      }
      materials = names.map((String name) => 'Файл: $name').join('\n');
    }
    final String wishes = sanitizer.sanitize(request.wishes ?? '');
    final Map<String, String> imageIds = _imageIdsFor(plan);
    final List<DocumentImage> documentImages = <DocumentImage>[
      for (final DocumentImage image in <DocumentImage>[
        ...chunk.imageParts,
        ...chunk.catalogOnly,
      ])
        image.withId(imageIds[_imageKey(image)] ?? image.id),
    ]..sort(_compareImageIds);
    return buildGenerationUserContent(
      materialsText: materials,
      wishes: wishes.isEmpty ? null : wishes,
      limit: chunk.limit,
      imagesCatalog: documentImages.isEmpty
          ? null
          : buildImageCatalog(documentImages),
      partIndexHint: chunk.partCount < 1 ? null : chunk.partIndex + 1,
      partCountHint: chunk.partCount < 1 ? null : chunk.partCount,
      focusSectionIds: chunk.focusSectionIds,
      outline: _outlineOf(plan, chunk),
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
  GenerationPlanBuilder _calibratedBuilder(TokenCalibration? calibration) =>
      generationPlanBuilderFor(calibration, base: planBuilder);

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

    final GenerationJob job;
    try {
      job =
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
    } on Object catch (error) {
      // Чтение журнала — тоже локальное хранилище: UI должен увидеть причину.
      throw _unexpectedAsGeneration(error);
    }
    final Set<String> seenHashes = _hashesOfCards(previous.cards);
    final List<PlannedChunk> chunks = <PlannedChunk>[
      for (final GenerationChunkFailure failure in retryable)
        failure.plannedChunk ?? _plannedFromFailure(failure),
    ];

    try {
      final Set<String> seen = <String>{
        ...seenHashes,
        ...?await _existingHashes(request.targetDeckId),
      };
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
    } on Object catch (error) {
      await _markUnexpected(previous.jobId, job);
      throw _unexpectedAsGeneration(error);
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
    // После перепланирования (overflow/413) дальнейшие запросы идут по
    // обновлённому плану: стратегия wholeDocument → fragmented, части делятся
    // с бюджетом ×0.8 (ADR-040 §8, 7.18.1 §2.3).
    GenerationPlan? activePlan = plan;
    final List<GeneratedCard> cards = List<GeneratedCard>.of(initialCards);
    final List<GenerationChunkFailure> failures = <GenerationChunkFailure>[];
    var tokensUsed = initialTokens;
    var processed = initialProcessed;
    var duplicates = initialDuplicates;
    var rejected = initialRejected;
    var trimmed = 0;
    final Map<String, int> producedBySection = <String, int>{};
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
    final bool promptOnly = activePlan?.isPromptOnly ?? false;
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
    // Страйки секций: один недобор не делает раздел исчерпанным, два подряд — делают.
    final Map<String, int> sectionStrikes = <String, int>{};
    final List<_BatchTokenFact> batchFacts = <_BatchTokenFact>[];
    var shortfall = 0;
    var skippedBatches = 0;
    var topUpRounds = 0;
    // TASK 04: диагностика честного недобора и best-effort изображений.
    var truncatedChunks = 0;
    var salvagedCards = 0;
    var imageResolveFailures = 0;
    // Срез 9: метрики прогона — длительности успешных батчей, помеченные
    // возможные дубли и факт расхода по слагаемым.
    final List<Duration> batchDurations = <Duration>[];
    var possibleDuplicates = 0;
    var promptTokens = 0;
    var completionTokens = 0;
    // Стоп добора, если предыдущий раунд не дал ни одной новой карточки.
    var topUpBaseline = -1;
    var requestsSent = 0;
    final Stopwatch operationWatch = Stopwatch()..start();
    while (index < queue.length) {
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      if ((maxOperationRequests > 0 && requestsSent >= maxOperationRequests) ||
          (maxOperationTokens > 0 && tokensUsed >= maxOperationTokens) ||
          (maxOperationSeconds > 0 &&
              operationWatch.elapsed.inSeconds >= maxOperationSeconds)) {
        break;
      }
      final _QueueItem item = queue[index];
      PlannedChunk chunk = item.chunk;
      final List<String> allSections = _sectionsOf(activePlan, chunk);
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
      final Map<String, String> imageIds = _imageIdsFor(activePlan);
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
          requestedCards: activePlan?.requestedCards,
        ),
      );

      GenerationResult result;
      final Stopwatch callWatch = Stopwatch()..start();
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
            outline: _outlineOf(activePlan, chunk),
            focusSectionIds: chunk.focusSectionIds,
            // Prompt-only не имеет частей материала (`partCount == 0`):
            // блок <part> не пишется, иначе модель видит «1 из 0».
            partIndexHint: plan == null || chunk.partCount < 1
                ? null
                : chunk.partIndex + 1,
            partCountHint: plan == null || chunk.partCount < 1
                ? null
                : chunk.partCount,
            contextOnly: null,
            maxOutputTokens: _maxOutputTokensFor(
              activePlan,
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
          activePlan,
          capabilities,
        );
        if (recovery != null) {
          // Перепланирование с бюджетом ×0.8 затрагивает не только текущую
          // партию: остальные партии той же части тоже делятся, иначе они
          // упрутся в тот же предел и потратят лишний запрос.
          final List<_QueueItem> replacement = <_QueueItem>[
            for (final PlannedChunk planned in recovery.chunks)
              _QueueItem(
                planned,
                attempts: item.attempts + 1,
                limitReduced: item.limitReduced || recovery.limitReduced,
                outputBoosted: recovery.outputBoosted,
              ),
          ];
          var replaceEnd = index + 1;
          _ReplannedPart? pendingReplan;
          final int? replanBudget = recovery.replanBudgetTokens;
          if (replanBudget != null) {
            final GenerationPlanSplitter prepared = splitter.withContext(
              estimator: planBuilder.estimator,
              imageTokenModel: capabilities.imageTokens,
            );
            while (replaceEnd < queue.length &&
                queue[replaceEnd].chunk.partIndex == chunk.partIndex) {
              final _QueueItem pendingItem = queue[replaceEnd];
              final PlannedChunk pending = pendingItem.chunk;
              final List<PlannedChunk>? parts = prepared.splitToBudget(
                pending,
                targetTokens: replanBudget,
              );
              replacement.addAll(<_QueueItem>[
                for (final PlannedChunk planned
                    in parts ?? <PlannedChunk>[pending])
                  _QueueItem(
                    planned,
                    attempts: pendingItem.attempts,
                    limitReduced: pendingItem.limitReduced,
                    outputBoosted: pendingItem.outputBoosted,
                  ),
              ]);
              replaceEnd++;
            }
            if (replacement.length > 1 || replaceEnd > index + 1) {
              final _ReplannedPart replanned = _replannedPart(
                plan: activePlan,
                source: chunk,
                budgetTokens: replanBudget,
                children: <PlannedChunk>[
                  for (final _QueueItem item in replacement) item.chunk,
                ],
              );
              pendingReplan = replanned;
              for (var child = 0; child < replacement.length; child++) {
                replacement[child] = replacement[child].withChunk(
                  replanned.chunks[child],
                );
              }
            }
          }
          // Одиночный повтор той же партии тоже расходует одну операцию;
          // при дроблении — число дополнительных запросов.
          final int replacedCount = replaceEnd - index;
          final int extra = replacement.length == 1 && replacedCount == 1
              ? 1
              : replacement.length - replacedCount;
          if (recoveryRequests + extra <= recoveryBudget) {
            if (pendingReplan != null) {
              activePlan = pendingReplan.plan;
            }
            if (replanBudget != null) {
              diagnostics.recovery(
                errorCode: error.code.name,
                parts: replacement.length,
                budgetTokens: replanBudget,
              );
            }
            recoveryRequests += extra < 0 ? 0 : extra;
            queue.replaceRange(index, replaceEnd, replacement);
            _renumber(queue);
            continue;
          }
        }
        shortfall += chunk.limit;
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
        if (cancellation?.isCancelled ?? false) {
          cancelled = true;
          break;
        }
        // Непредвиденная ошибка адаптера: карточки фрагмента не принимаются,
        // остальные фрагменты продолжаются (A6.8 «частичный успех»).
        shortfall += chunk.limit;
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
      callWatch.stop();
      batchDurations.add(callWatch.elapsed);

      rejected += result.rejectedCards;
      // TASK 04: оборванный ответ модели не считается падением партии: полные
      // карточки уже в результате, а недостача добирается следующими партиями.
      if (result.truncated) {
        truncatedChunks++;
        salvagedCards += result.salvagedCards;
      }
      tokensUsed += result.usage.totalTokens ?? 0;
      promptTokens += result.usage.promptTokens ?? 0;
      completionTokens += result.usage.completionTokens ?? 0;
      processed++;
      sentDocumentImageIds.addAll(result.sentDocumentImageIds);
      calibrationSamples.add(
        _calibrationSample(
          plan: activePlan,
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
      final int? requestedTarget = activePlan?.requestedCards;
      for (final GeneratedCard card in result.cards) {
        if (requestedTarget != null &&
            requestedTarget > 0 &&
            cards.length >= requestedTarget) {
          trimmed++;
          continue;
        }
        switch (_acceptCard(card, seen, cards)) {
          case _CardAcceptance.accepted:
            cards.add(card);
          case _CardAcceptance.possibleDuplicate:
            // ARCH §3.4: смысловой дубль помечается, а не удаляется — решение
            // за пользователем в предпросмотре.
            cards.add(
              card.copyWith(
                issues: <CardIssueCode>[
                  ...card.issues,
                  CardIssueCode.possibleDuplicate,
                ],
              ),
            );
            possibleDuplicates++;
          case _CardAcceptance.duplicate:
            duplicates++;
        }
      }
      final int acceptedInChunk = cards.length - imageStart;
      if (acceptedInChunk > 0 && chunkSections.isNotEmpty) {
        final int base = acceptedInChunk ~/ chunkSections.length;
        int remainder = acceptedInChunk % chunkSections.length;
        for (final String section in chunkSections) {
          final int add = base + (remainder > 0 ? 1 : 0);
          if (remainder > 0) remainder--;
          producedBySection[section] = (producedBySection[section] ?? 0) + add;
        }
      }
      if (result.usage.completionTokens != null && acceptedInChunk > 0) {
        batchFacts.add(
          _BatchTokenFact(
            completionTokens: result.usage.completionTokens!,
            acceptedCards: acceptedInChunk,
          ),
        );
      }
      // Исчерпание: явный флаг модели даёт два страйка, слабая отдача — один.
      // Раздел считается исчерпанным только после двух страйков.
      final bool lowYield =
          chunk.limit >= 2 && acceptedInChunk * 2 < chunk.limit;
      if ((result.sourceExhausted || lowYield) && chunkSections.isNotEmpty) {
        for (final String section in chunkSections) {
          final int strikes =
              (sectionStrikes[section] ?? 0) + (result.sourceExhausted ? 2 : 1);
          sectionStrikes[section] = strikes;
          if (strikes >= 2) exhaustedSections.add(section);
        }
      }
      final int deficit = chunk.limit - acceptedInChunk;
      if (deficit > 0) shortfall += deficit;
      onProgress?.call(
        GenerationProgress(
          phase: GenerationProgressPhase.receiving,
          chunkIndex: index + 1,
          chunkCount: queue.length,
          requestedCards: activePlan?.requestedCards,
          cards: List<GeneratedCard>.unmodifiable(cards),
          imagesPending: imageStart < cards.length,
        ),
      );
      for (
        var imageIndex = imageStart;
        imageIndex < cards.length;
        imageIndex++
      ) {
        // TASK 04, часть 5: поиск/разрешение изображений — best effort.
        // Исключение при разрешении картинок раньше могло выбраться из цикла
        // партии и оборвать весь запуск; теперь карточка сохраняется без
        // изображения, а генерация продолжается.
        final GeneratedCard beforeImages = cards[imageIndex];
        try {
          cards[imageIndex] = await _withCardImages(
            beforeImages,
            documentImages,
            cancellation,
            wishes: request.wishes,
          );
        } on Object catch (error) {
          imageResolveFailures++;
          diagnostics.imageSearch(
            query: beforeImages.imageQuery ?? '',
            outcome:
                'разрешение изображений упало (${error.runtimeType}): '
                'карточка сохранена без картинки',
          );
          cards[imageIndex] = _withoutImages(
            beforeImages.clearedImageSelection(),
          );
        }
        onProgress?.call(
          GenerationProgress(
            phase: GenerationProgressPhase.receiving,
            chunkIndex: index + 1,
            chunkCount: queue.length,
            requestedCards: activePlan?.requestedCards,
            cards: List<GeneratedCard>.unmodifiable(cards),
            imagesPending: imageIndex + 1 < cards.length,
          ),
        );
      }
      // Состояние продолжения prompt-only: принятые карточки уже с догруженными
      // картинками (сводка не включает дубли и не раздувается).
      if (promptOnly && imageStart < cards.length) {
        continuity.addAll(cards.sublist(imageStart));
      }
      await _saveProgress(job, processed, cards.length, tokensUsed);
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      index++;
      // Раунды добора недостачи на разделы с оставшейся ёмкостью (ADR-040 §8).
      // Останавливаемся, когда раунд не дал ни одной новой карточки.
      if (index >= queue.length &&
          topUpRounds < maxTopUpRounds &&
          shortfall > 0 &&
          !cancelled &&
          fatal == null &&
          activePlan != null &&
          activePlan.requestedCards > 0 &&
          initialCards.isEmpty &&
          (topUpBaseline < 0 || cards.length > topUpBaseline)) {
        final int remaining = activePlan.requestedCards > 0
            ? activePlan.requestedCards - cards.length
            : shortfall;
        final PlannedChunk? topUp = remaining <= 0
            ? null
            : _topUpChunk(
                activePlan,
                exhaustedSections,
                shortfall < remaining ? shortfall : remaining,
                queue.length + 1,
                maxLimit: capabilities.maxCardsPerRequest,
              );
        if (topUp != null && recoveryRequests < recoveryBudget) {
          recoveryRequests++;
          topUpRounds++;
          topUpBaseline = cards.length;
          queue.add(_QueueItem(topUp));
          diagnostics.imageParticipation(
            outcome:
                'перераспределение недостачи: +${topUp.limit} карточек '
                '(focus: ${topUp.focusSectionIds.join(', ')})',
          );
        }
      }
    }

    // Срез 9: «Почему?» по якорям — блок источника из `ContentModel`, а не
    // склеенная цитата. Только на пути v3 и best effort: сбой разбора не
    // отменяет уже принятые карточки.
    if (pipelineV3 && cards.isNotEmpty) _resolveAnchors(cards, request);

    final GenerationPlan? planForCoverage = activePlan;
    final List<GenerationSectionCoverage> sectionCoverage =
        <GenerationSectionCoverage>[
          if (planForCoverage != null)
            for (final InputPart part in planForCoverage.parts)
              for (final InputSection section in part.sections)
                if ((planForCoverage.allocation?.forSection(section.id) ?? 0) >
                    0)
                  GenerationSectionCoverage(
                    sectionId: section.promptId,
                    allocated:
                        planForCoverage.allocation?.forSection(section.id) ?? 0,
                    produced: producedBySection[section.promptId] ?? 0,
                    exhausted: exhaustedSections.contains(section.promptId),
                  ),
        ];
    final bool hasCards = cards.isNotEmpty;
    final int requestedTotal = activePlan?.requestedCards ?? 0;
    final bool targetReached =
        requestedTotal > 0 && cards.length >= requestedTotal;
    final int producedTotal = cards.length + duplicates + rejected;
    // Срез 9: вердикт считается по журналу (ARCH §3.2), а не по «сколько
    // вернулось сейчас»; на старом пути статус остаётся прежним.
    final GenerationLedger ledgerOfRun = GenerationLedger(
      batches: <GenerationBatchLedger>[
        GenerationBatchLedger(
          batchIndex: 0,
          requested: requestedTotal,
          generated: producedTotal,
          invalid: rejected,
          duplicates: duplicates,
          attempts: processed + recoveryRequests,
          cause: _causeOfRun(fatal: fatal, failures: failures),
        ),
      ],
    );
    final CompletionVerdict verdict = requestedTotal > 0
        ? CompletionVerdict.fromLedger(
            ledgerOfRun,
            cancelled: cancelled,
            failed: fatal != null,
            materialCapacity: activePlan?.materialCapacity ?? 0,
          )
        : CompletionVerdict.auto(
            accepted: cards.length,
            requests: processed + recoveryRequests,
            failedRequests: failedRequests + (fatal != null ? 1 : 0),
            cancelled: cancelled,
            materialCapacity: activePlan?.materialCapacity ?? 0,
          );
    final GenerationJobStatus status;
    if (pipelineV3) {
      status = verdict.jobStatus;
    } else if (cancelled) {
      status = GenerationJobStatus.cancelled;
    } else if (fatal != null) {
      status = hasCards
          ? GenerationJobStatus.partial
          : GenerationJobStatus.error;
    } else if (requestedTotal == 0 ? failures.isEmpty : targetReached) {
      status = GenerationJobStatus.done;
    } else if (!hasCards && duplicates > 0) {
      // Всё, что вернула модель, оказалось дублями: это не ошибка генерации,
      // но и не достижение цели — честный partial без новых карточек.
      status = GenerationJobStatus.partial;
    } else if (!hasCards) {
      status = GenerationJobStatus.error;
    } else {
      status = GenerationJobStatus.partial;
    }
    final GenerationMetrics metrics = GenerationMetrics(
      requested: requestedTotal,
      accepted: cards.length,
      generated: producedTotal,
      invalid: rejected,
      duplicates: duplicates,
      // Факт `usage`; без него — оценка входа плана (иначе yield был бы 0).
      inputTokens: promptTokens > 0 ? promptTokens : estimate,
      outputTokens: completionTokens,
      requests: processed + recoveryRequests,
      batchDurations: List<Duration>.unmodifiable(batchDurations),
      duplicatesByLevel: <DedupLevel, int>{
        if (duplicates > 0) DedupLevel.exact: duplicates,
        if (possibleDuplicates > 0) DedupLevel.semantic: possibleDuplicates,
      },
      coveredUnits: sectionCoverage
          .where((GenerationSectionCoverage c) => c.produced > 0)
          .length,
      totalUnits: sectionCoverage.length,
    );
    final String? errorCode = fatal != null
        ? fatal.code.name
        : failures.isEmpty
        ? null
        : _failureCodesOf(failures);
    await jobRepository.save(
      job.copyWith(
        status: status,
        // ADR-040 §8: chunk_count — число частей входа, tokens_used — факт.
        chunkCount: activePlan?.partCount ?? processed,
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
    // TASK 04: итог «запрошено/создано/почему меньше» — по числам, без текстов.
    diagnostics.runSummary(
      requested: requestedTotal,
      created: cards.length,
      chunks: processed,
      failedChunks: failures.length,
      truncatedChunks: truncatedChunks,
      salvagedCards: salvagedCards,
      imageResolveFailures: imageResolveFailures,
      exhaustedSections: exhaustedSections.length,
    );
    diagnostics.runMetrics(metrics.toJson());
    // TASK «Срез 12», п. 4: отчёт — единственный источник правды и для
    // legacy-пути. Иначе «было → стало» сравнивает отчёт v3 с ручными
    // счётчиками, а cleanRate/coverage у legacy вовсе не считаются.
    final Map<String, int> warningCodes = <String, int>{};
    var acceptedWithWarnings = 0;
    for (final GeneratedCard card in cards) {
      if (card.issues.isEmpty) continue;
      acceptedWithWarnings++;
      for (final CardIssueCode issue in card.issues) {
        warningCodes[issue.name] = (warningCodes[issue.name] ?? 0) + 1;
      }
    }
    final GenerationStage reportStage = switch (status) {
      GenerationJobStatus.done => GenerationStage.ready,
      GenerationJobStatus.cancelled => GenerationStage.cancelled,
      GenerationJobStatus.error => GenerationStage.failed,
      _ => GenerationStage.partial,
    };
    final int remainingCards = requestedTotal > cards.length
        ? requestedTotal - cards.length
        : 0;
    final ShortfallKind? stopKind = verdict.reasons.isEmpty
        ? null
        : verdict.reasons.first;
    final GenerationReport report = GenerationReport(
      requested: requestedTotal,
      accepted: cards.length,
      stage: reportStage,
      reason: switch (reportStage) {
        GenerationStage.ready => ReplenishStopReason.complete,
        GenerationStage.cancelled => ReplenishStopReason.cancelled,
        GenerationStage.failed => ReplenishStopReason.providerError,
        _ =>
          failures.isNotEmpty
              ? ReplenishStopReason.providerError
              : ReplenishStopReason.exhaustedMaterial,
      },
      reasons: <String>[
        for (final ShortfallKind kind in verdict.reasons) kind.wireName,
      ],
      unitCoverage: <UnitCoverage>[
        for (final GenerationSectionCoverage coverage in sectionCoverage)
          UnitCoverage(
            unitId: coverage.sectionId,
            planned: coverage.allocated,
            accepted: coverage.produced,
          ),
      ],
      tokensByStage: <GenerationStage, TokenUsage>{
        GenerationStage.generating: TokenUsage(
          promptTokens: promptTokens,
          completionTokens: completionTokens,
          totalTokens: tokensUsed,
        ),
      },
      promptVersions: <String, String>{'generating': systemPromptVersion},
      duration: operationWatch.elapsed,
      passes: 1 + topUpRounds,
      requests: processed + recoveryRequests,
      invalid: rejected,
      duplicates: duplicates,
      generated: producedTotal,
      acceptedWithWarnings: acceptedWithWarnings,
      warningCodes: warningCodes,
      duplicatesByLevel: metrics.duplicatesByLevel,
      batchDurations: batchDurations,
      materialCapacity: activePlan?.materialCapacity,
      unfilledSlots: remainingCards,
      shortfallReasons: remainingCards > 0
          ? <ShortfallKind, int>{
              stopKind ?? ShortfallKind.exhaustedMaterial: remainingCards,
            }
          : const <ShortfallKind, int>{},
    );
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
      trimmedCards: trimmed,
      fatalErrorCode: fatal?.code,
      fatalProviderReason: fatal?.providerReason,
      plan: activePlan,
      calibration: calibration,
      recoveryRequestsUsed: recoveryRequests,
      recoveryBudget: recoveryBudget,
      sentDocumentImageIds: List<String>.unmodifiable(sentDocumentImageIds),
      shortfallCards: shortfall,
      skippedBatches: skippedBatches,
      exhaustedSectionIds: List<String>.unmodifiable(exhaustedSections),
      sectionCoverage: List<GenerationSectionCoverage>.unmodifiable(
        sectionCoverage,
      ),
      truncatedChunks: truncatedChunks,
      salvagedCards: salvagedCards,
      imageResolveFailures: imageResolveFailures,
      verdict: verdict,
      metrics: metrics,
      possibleDuplicates: possibleDuplicates,
      report: report,
    );
  }

  /// Причина недобора прогона для журнала (ARCH §2): одна на весь прогон.
  static ShortfallKind? _causeOfRun({
    required GenerationException? fatal,
    required List<GenerationChunkFailure> failures,
  }) {
    if (fatal != null || failures.isNotEmpty) {
      return ShortfallKind.providerError;
    }
    return null;
  }

  /// Дописывает карточкам блок источника для «Почему?» (срез 9).
  ///
  /// Best effort: модель не должна падать на разборе документа; карточка без
  /// найденного блока остаётся без «Почему?» (выдуманный текст не подставляется).
  void _resolveAnchors(
    List<GeneratedCard> cards,
    GenerationRunRequest request,
  ) {
    if (request.documents.isEmpty) return;
    final List<Document> documents = <Document>[];
    try {
      const ContentModelBuilder builder = ContentModelBuilder();
      for (final ParsedDocument document in request.documents) {
        documents.add(builder.build(document));
      }
    } on Object {
      return;
    }
    const SourceAnchorResolver resolver = SourceAnchorResolver();
    for (var index = 0; index < cards.length; index++) {
      final GeneratedCard card = cards[index];
      if (card.sourceAnchorText != null) continue;
      final SourceAnchor? anchor = resolver.resolve(
        documents,
        quote: card.quoteRef,
        excerpt: card.sourceExcerpt,
        fileName: card.sourceFile,
      );
      if (anchor == null) continue;
      cards[index] = card.copyWith(
        sourceAnchorText: anchor.text,
        sourceAnchorSection: anchor.sectionTitle,
      );
    }
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
    // §3.9: не больше 3 операций восстановления на запрос. Дальше фрагмент
    // фиксируется ошибкой — без бесконечных повторов и лишних расходов.
    if (item.attempts >= 3) return null;
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
        // §3.9: подтверждённое переполнение → перепланирование с бюджетом
        // ×0.8. Цель — 80 % прежнего бюджета материалов и не больше 80 %
        // самого фрагмента (гарантия прогресса). wholeDocument при этом
        // переходит во fragmented (обновление плана в `_process`).
        final int target = _reducedBudgetTarget(plan, chunk);
        if (target > 0) {
          final List<PlannedChunk>? replanned = prepared.splitToBudget(
            chunk,
            targetTokens: target,
          );
          if (replanned != null) {
            return _Recovery(replanned, replanBudgetTokens: target);
          }
        }
        final List<PlannedChunk>? halves = prepared.split(
          chunk,
          allowLimitOverflow: true,
        );
        return halves == null ? null : _Recovery(halves);
      case GenerationErrorCode.missingApiKey:
      case GenerationErrorCode.providerNotConfigured:
      case GenerationErrorCode.invalidApiKey:
      case GenerationErrorCode.insufficientBalance:
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
      case GenerationErrorCode.storageUnavailable:
        return null;
    }
  }

  /// Цель перепланирования после переполнения: `min(0.8 × бюджет, 0.8 ×
  /// фрагмент)`, чтобы каждая новая часть была меньше и бюджета, и прежней
  /// части. `0` — бюджета нет (план без материалов) и делить нечего.
  int _reducedBudgetTarget(GenerationPlan? plan, PlannedChunk chunk) {
    final int materialTokens =
        chunk.units.fold<int>(
          0,
          (int sum, UnitSpan span) => sum + span.tokens,
        ) +
        chunk.imageTokens;
    if (materialTokens <= 0) return 0;
    final int byChunk = (materialTokens * 0.8).floor();
    final int? budget = plan?.inputPlan?.materialBudgetTokens;
    final int byBudget = budget == null ? byChunk : (budget * 0.8).floor();
    final int target = budget == null ? byChunk : math.min(byBudget, byChunk);
    return math.max(1, target);
  }

  /// Пересобирает части плана после перепланирования восстановления.
  ///
  /// wholeDocument → fragmented: каждая новая часть получает реальные разделы
  /// (по `unitId`), `partIndex/partCount` и `focus`, поэтому запросы
  /// восстановления — настоящие части, а не «часть 1 из 1». Для уже
  /// дроблённого плана части не пересобираются, но дети получают корректные
  /// `partIndex/partCount` и `focus` своей части.
  _ReplannedPart _replannedPart({
    required GenerationPlan? plan,
    required PlannedChunk source,
    required List<PlannedChunk> children,
    required int budgetTokens,
  }) {
    final InputPlan? input = plan?.inputPlan;
    if (plan == null || input == null || input.isPromptOnly) {
      return _ReplannedPart(plan: plan, chunks: children);
    }
    final bool whole = input.strategy == InputStrategy.wholeDocument;
    final int partIndex = whole
        ? 0
        : source.partIndex.clamp(0, input.parts.length - 1);
    final int partCount = whole ? children.length : input.parts.length;
    final List<InputSection> sourceSections =
        partIndex >= 0 && partIndex < input.parts.length
        ? input.parts[partIndex].sections
        : const <InputSection>[];
    final Map<String, InputSection> byId = <String, InputSection>{
      for (final InputSection section in sourceSections) section.id: section,
    };
    final List<PlannedChunk> updated = <PlannedChunk>[];
    final List<InputPart> rebuiltParts = <InputPart>[];
    for (var index = 0; index < children.length; index++) {
      final PlannedChunk child = children[index];
      final Set<String> sectionIds = <String>{
        for (final UnitSpan unit in child.units)
          if (_sectionIdOfUnit(unit.unitId) case final String id
              when byId.containsKey(id))
            id,
      };
      final List<InputSection> sections = <InputSection>[
        for (final InputSection section in sourceSections)
          if (sectionIds.isEmpty || sectionIds.contains(section.id)) section,
      ];
      updated.add(
        child.copyWith(
          partIndex: whole ? index : partIndex,
          partCount: partCount,
          focusSectionIds: <String>[
            for (final InputSection section in sections) section.promptId,
          ],
        ),
      );
      if (whole) {
        rebuiltParts.add(
          InputPart(
            index: index,
            sections: List<InputSection>.unmodifiable(sections),
            materialsText: child.materialsText,
            tokens: child.textTokens,
            bytes: child.bodyBytes,
            images: List<InputImage>.unmodifiable(<InputImage>[
              for (final DocumentImage image in child.imageParts)
                _inputImageOf(image),
            ]),
            catalogImages: List<InputImage>.unmodifiable(<InputImage>[
              for (final DocumentImage image in child.catalogOnly)
                _inputImageOf(image),
            ]),
          ),
        );
      }
    }
    if (!whole) {
      return _ReplannedPart(plan: plan, chunks: updated);
    }
    final InputPlan rebuilt = input.withParts(
      strategy: InputStrategy.fragmented,
      parts: List<InputPart>.unmodifiable(rebuiltParts),
      materialBudgetTokens: budgetTokens,
    );
    return _ReplannedPart(
      plan: plan.withPlanData(inputPlan: rebuilt, chunks: updated),
      chunks: updated,
    );
  }

  /// Разделы, к которым относится единица (`doc:<файл>#<раздел>#<кусок>`).
  String? _sectionIdOfUnit(String unitId) {
    final String base = unitId.split('~').first;
    if (!base.startsWith('doc:')) return null;
    final int last = base.lastIndexOf('#');
    if (last <= 4) return null;
    final int previous = base.lastIndexOf('#', last - 1);
    if (previous <= 4) return null;
    return base.substring(0, last);
  }

  InputImage _inputImageOf(DocumentImage image) => InputImage(
    id: image.id,
    fileName: image.fileName,
    bytes: image.bytes,
    page: image.page,
  );

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
      GenerationErrorCode.insufficientBalance ||
      GenerationErrorCode.noMaterials ||
      GenerationErrorCode.visionUnsupported ||
      GenerationErrorCode.fileWithoutTextAndVision ||
      GenerationErrorCode.pdfScanUnsupported ||
      GenerationErrorCode.pdfScanVisionRequired ||
      GenerationErrorCode.attachmentTooLarge ||
      GenerationErrorCode.storageUnavailable ||
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

  /// Разрешает изображения обеих сторон карточки (7.19, ADR-041/042).
  ///
  /// Приоритет 1 — изображения из прикреплённых файлов по
  /// `question_image_ids`/`answer_image_ids`: только каталог фрагмента и только
  /// своя сторона, внешний поиск не вызывается. Приоритет 2 — внешний поиск
  /// **настоящей** фотографии по `image.query`/`image.fallback_query`, если у
  /// выбранной модели стороны (`image.side`) ещё нет изображений.
  ///
  /// Синтезированных изображений нет: если ничего не нашлось, сторона остаётся
  /// пустой с пометкой `imageNotFound`, а не подменяется нарисованным PNG.
  Future<GeneratedCard> _withCardImages(
    GeneratedCard card,
    List<DocumentImage> documentImages,
    GenerationCancellation? cancellation, {
    required String? wishes,
  }) async {
    if (wishesForbidImages(wishes)) {
      return _withoutImages(card.clearedImageSelection());
    }

    final List<GeneratedCardImage> questionImages = <GeneratedCardImage>[];
    final List<GeneratedCardImage> answerImages = <GeneratedCardImage>[];
    final Set<String> digests = <String>{};
    final List<CardIssueCode> issues = <CardIssueCode>[...card.issues];

    void resolve(List<String> ids, List<GeneratedCardImage> target) {
      for (final String id in ids) {
        final DocumentImage? image = _documentImageById(documentImages, id);
        if (image == null) continue; // уже помечено валидатором как неизвестный
        // Один и тот же файл не должен попасть на обе стороны.
        if (!digests.add(documentImageDigest(image.bytes))) continue;
        target.add(
          GeneratedCardImage(
            bytes: image.bytes,
            mediaType: image.mediaType,
            query: card.imageQuery ?? '',
            kind: card.imageKind,
            fallbackQuery: card.imageFallbackQuery,
            provider: 'file',
            attribution: image.caption ?? image.fileName,
          ),
        );
        diagnostics.imageSearch(
          query: 'image_id:$id',
          outcome:
              'изображение из файла ${image.fileName} '
              '(${image.bytes.length} Б)',
        );
      }
    }

    resolve(card.questionImageIds, questionImages);
    resolve(card.answerImageIds, answerImages);

    final GeneratedCardImageSide side = card.imageSide;
    final String? query = card.imageQuery?.trim();
    final List<GeneratedCardImage> sideImages =
        side == GeneratedCardImageSide.answer ? answerImages : questionImages;
    final bool canSearch =
        side != GeneratedCardImageSide.none &&
        query != null &&
        query.isNotEmpty &&
        sideImages.isEmpty &&
        imageFinder != null &&
        !(cancellation?.isCancelled ?? false);

    if (canSearch) {
      final GeneratedCardImage? found = await _searchCardImage(card, query);
      if (found != null) {
        sideImages.add(found);
      } else if (!issues.contains(CardIssueCode.imageNotFound)) {
        issues.add(CardIssueCode.imageNotFound);
      }
    }

    final bool occlusionWithoutImage =
        card.isOcclusion && questionImages.isEmpty;
    return card.copyWith(
      questionImages: List<GeneratedCardImage>.unmodifiable(questionImages),
      answerImages: List<GeneratedCardImage>.unmodifiable(answerImages),
      issues: List<CardIssueCode>.unmodifiable(<CardIssueCode>[
        ...issues,
        if (occlusionWithoutImage) CardIssueCode.occlusionImageMissing,
      ]),
      isOcclusion: card.isOcclusion && !occlusionWithoutImage,
      occlusionJson: card.isOcclusion && !occlusionWithoutImage
          ? card.occlusionJson ?? defaultOcclusionDocumentJson()
          : card.occlusionJson,
    );
  }

  /// Внешний поиск настоящей картинки; `null` — не нашли/бюджет исчерпан/сбой.
  Future<GeneratedCardImage?> _searchCardImage(
    GeneratedCard card,
    String query,
  ) async {
    final DateTime? startedAt = _imageSearchBudgeted ? now() : null;
    final bool budgetExhausted =
        _imageSearchBudgeted && _imageSearchSpent >= imageSearchBudget;
    if (budgetExhausted) {
      diagnostics.imageSearch(
        query: query,
        outcome: 'пропущен: бюджет времени поиска исчерпан',
      );
      return null;
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
    if (startedAt != null) {
      _imageSearchSpent += now().difference(startedAt);
    }
    if (image == null) {
      _imageCache.remove(query);
      return null;
    }
    final String? sourceUrl = image.sourceUrl;
    // Один и тот же URL не должен попасть в колоду дважды.
    if (sourceUrl != null && !_usedImageUrls.add(sourceUrl)) {
      _imageCache.remove(query);
      return null;
    }
    return image;
  }

  /// Карточка без изображений: occlusion становится обычной с пометкой.
  GeneratedCard _withoutImages(
    GeneratedCard card, {
    bool imageNotFound = false,
  }) {
    return GeneratedCard(
      front: card.front,
      back: card.back,
      cardType: card.cardType,
      hint: card.hint,
      tags: card.tags,
      sourceExcerpt: card.sourceExcerpt,
      sourceFile: card.sourceFile,
      issues: List<CardIssueCode>.unmodifiable(<CardIssueCode>[
        ...card.issues,
        if (card.isOcclusion) CardIssueCode.occlusionImageMissing,
        if (imageNotFound) CardIssueCode.imageNotFound,
      ]),
      imageKind: card.imageKind,
      isOcclusion: false,
      occlusionJson: card.occlusionJson,
      sectionId: card.sectionId,
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

  /// Принимает карточку, если её хеш новый (ADR-040 §8).
  ///
  /// Точный дубль — по `content_hash` (и обратному для reversed). Почти-дубль
  /// (сходство триграмм `front` ≥ 0.85 в пределах запуска) на старом пути
  /// отбрасывается, на пути v3 **помечается и остаётся** (ARCH §3.4).
  _CardAcceptance _acceptCard(
    GeneratedCard card,
    Set<String> seen,
    List<GeneratedCard> accepted,
  ) {
    final String hash = contentHashOf(front: card.front, back: card.back);
    final String? reversed = card.cardType == CardType.basicReversed
        ? contentHashOf(front: card.back, back: card.front)
        : null;
    if (seen.contains(hash) || (reversed != null && seen.contains(reversed))) {
      return _CardAcceptance.duplicate;
    }
    var nearDuplicate = false;
    for (final GeneratedCard other in accepted) {
      if (_frontSimilarity(card.front, other.front) >= 0.85) {
        nearDuplicate = true;
        break;
      }
    }
    if (nearDuplicate && !pipelineV3) return _CardAcceptance.duplicate;
    seen.add(hash);
    if (reversed != null) seen.add(reversed);
    return nearDuplicate
        ? _CardAcceptance.possibleDuplicate
        : _CardAcceptance.accepted;
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
  ///
  /// 7.20: лимит дополнительной партии не больше вместимости одного ответа —
  /// иначе перераспределение просило бы больше, чем помещается в `max_tokens`
  /// партии (и упиралось бы в `truncated`/недобор).
  PlannedChunk? _topUpChunk(
    GenerationPlan plan,
    Set<String> exhausted,
    int shortfall,
    int index, {
    int? maxLimit,
  }) {
    if (shortfall < 1) return null;
    final int? planMaxTokens = plan.inputPlan?.maxTokens;
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
      // Без `inputPlan` (план старого пути/теста) ориентир — лимит базовой
      // партии: просить больше, чем она запрашивала, заведомо нельзя.
      final int cap = planMaxTokens == null
          ? base.limit
          : OutputBatchPlanner(config: planBuilder.planner.config.planning)
                .cardsPerBatch(
                  planMaxTokens,
                  maxCardsPerRequest: maxLimit,
                  reasoningReserveTokens: plan.reasoningReserveTokens,
                );
      return base.copyWith(
        index: index,
        limit: shortfall < cap ? shortfall : cap,
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
/// Запрос нативного подсчёта: сообщение и мультимодальные части (7.18.3 §2).
///
/// Тело запроса наружу не отдаётся: числа идут в план, байты — только в
/// `count_tokens`; в диагностику попадает источник и число, не содержимое.
/// Исход дедупликации карточки (срез 9, ARCH §3.4).
///
/// Точный дубль отбрасывается (не потеря), возможный — помечается и остаётся.
enum _CardAcceptance { accepted, possibleDuplicate, duplicate }

class _CountedRequest {
  const _CountedRequest({required this.userContent, required this.attachments});

  final String userContent;
  final List<GenerationAttachment> attachments;
}

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

/// Результат перепланирования части: обновлённый план и фрагменты.
class _ReplannedPart {
  const _ReplannedPart({required this.plan, required this.chunks});

  final GenerationPlan? plan;
  final List<PlannedChunk> chunks;
}

/// Результат решения о восстановлении: новые фрагменты и флаги попытки.
class _Recovery {
  const _Recovery(
    this.chunks, {
    this.limitReduced = false,
    this.outputBoosted = false,
    this.replanBudgetTokens,
  });

  final List<PlannedChunk> chunks;

  /// Бюджет перепланирования после overflow/413 (×0.8); `null` — обычное
  /// дробление/сокращение без перепланирования остальных партий части.
  final int? replanBudgetTokens;

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
