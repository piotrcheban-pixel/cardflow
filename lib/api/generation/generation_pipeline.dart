/// Пайплайн генерации карточек: оценка, чанкинг, последовательные вызовы,
/// дедупликация, прогресс/отмена и `generation_jobs` (SPEC A8.5, ADR-015).
library;

import 'package:uuid/uuid.dart';

import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_model.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/image_query.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';

/// Коды ошибок, после которых повторять следующие фрагменты бессмысленно.
const Set<GenerationErrorCode> _fatalCodes = <GenerationErrorCode>{
  GenerationErrorCode.missingApiKey,
  GenerationErrorCode.providerNotConfigured,
  GenerationErrorCode.invalidApiKey,
  GenerationErrorCode.noMaterials,
};

/// Код в `generation_jobs.error_code` для непредвиденного сбоя пайплайна/БД.
const String _unexpectedErrorCode = 'unexpected';

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

/// Оркестратор генерации.
class GenerationPipeline implements GenerationRunner {
  /// Создаёт пайплайн.
  GenerationPipeline({
    required this.caller,
    required this.jobRepository,
    required this.cardStore,
    this.estimator = const TokenEstimator(),
    this.chunker = const GenerationChunker(),
    this.imageFinder,
    this.imageSearchBudget = const Duration(seconds: 90),
    this.diagnostics = const GenerationDiagnostics(),
    this.now = _defaultNow,
    this.jobIdFactory = _defaultJobId,
  });

  /// Вызов модели на фрагмент.
  final GenerationCaller caller;

  /// Хранилище заданий.
  final GenerationJobRepository jobRepository;

  /// Дедупликация/импорт.
  final GenerationCardStore cardStore;

  /// Оценщик токенов.
  final TokenEstimator estimator;

  /// Чанкер.
  final GenerationChunker chunker;

  /// Поиск иллюстраций по `image_query` (итерация 7.9); `null` — без картинок.
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

  /// Кэш картинок по запросу в рамках одного запуска/повтора.
  final Map<String, Future<GeneratedCardImage?>> _imageCache =
      <String, Future<GeneratedCardImage?>>{};

  /// Сколько времени уже потрачено на поиск иллюстраций в этом запуске.
  Duration _imageSearchSpent = Duration.zero;

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
    _resetImageBudget();
    final String jobId = jobIdFactory();
    final DateTime createdAt = now();
    final int systemPromptTokens = estimator.estimate(systemPromptGenRuV5);
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
      final int budget = inputTokenBudget(
        contextTokens: request.account.contextTokens,
        systemPromptTokens: systemPromptTokens,
      );
      final List<GenerationChunk> chunks = _withCardLimits(
        _chunksFor(request, budget),
        request.wishes,
      );
      if (chunks.isEmpty) {
        await jobRepository.save(
          initialJob.copyWith(
            status: GenerationJobStatus.error,
            errorCode: GenerationErrorCode.noMaterials.name,
          ),
        );
        throw const GenerationException(GenerationErrorCode.noMaterials);
      }

      final int estimatedTokens =
          estimator.estimateAll(<String>[
            for (final document in request.documents) document.text,
          ]) +
          estimator.estimate(request.wishes ?? '') +
          request.images.length * kImageTokenEstimate +
          chunks.length * (systemPromptTokens + kPromptWrapperTokenReserve);
      final Set<String> seen = <String>{
        ...?await _existingHashes(request.targetDeckId),
      };

      final GenerationRunResult result = await _process(
        request: request,
        job: initialJob,
        chunks: chunks,
        seen: seen,
        estimate: estimatedTokens,
        onProgress: onProgress,
        cancellation: cancellation,
      );
      return result;
    } on Object {
      await _markUnexpected(jobId, initialJob);
      rethrow;
    }
  }

  /// Фрагменты запуска: обычная нарезка или prompt-only фрагмент по теме.
  ///
  /// Если файлов нет, а пожелания задают тему, создаётся один фрагмент с пустым
  /// `materialsText` (итерация 7.10, ADR-024): тема уходит в `<wishes>`.
  /// Пустая нарезка при наличии файлов — прежний `noMaterials`.
  List<GenerationChunk> _chunksFor(GenerationRunRequest request, int budget) {
    final List<GenerationChunk> chunks = chunker.chunkAll(
      request.documents,
      request.images,
      maxInputTokens: budget,
    );
    if (chunks.isNotEmpty ||
        request.documents.isNotEmpty ||
        request.images.isNotEmpty) {
      return chunks;
    }
    if ((request.wishes ?? '').trim().isEmpty) return chunks;
    return <GenerationChunk>[
      const GenerationChunk(
        index: 1,
        materialsText: '',
        sourceFiles: <String>[],
        limit: kMaxCardsPerChunk,
      ),
    ];
  }

  /// Распределяет общее число карточек из пожеланий по фрагментам (fix-gen).
  ///
  /// «20 карточек» в пожеланиях → каждый фрагмент получает долю,
  /// пропорциональную объёму (сумма = 20, не больше [kMaxCardsPerChunk] на
  /// фрагмент). Число не указано — остаются лимиты фрагментов.
  List<GenerationChunk> _withCardLimits(
    List<GenerationChunk> chunks,
    String? wishes,
  ) {
    final int? requested = requestedCardCount(wishes);
    if (requested == null || chunks.isEmpty) return chunks;
    final List<int> volumes = <int>[
      for (final GenerationChunk chunk in chunks)
        chunk.materialsText.trim().isEmpty
            ? 1
            : estimator.estimate(chunk.materialsText),
    ];
    final List<int> limits = distributeCardLimits(
      volumes: volumes,
      total: requested,
    );
    return <GenerationChunk>[
      for (var index = 0; index < chunks.length; index++)
        chunks[index].copyWith(limit: limits[index]),
    ];
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
    final List<GenerationChunk> chunks = <GenerationChunk>[
      for (final failure in retryable)
        GenerationChunk(
          index: failure.chunkIndex,
          materialsText: failure.materialsText,
          sourceFiles: failure.sourceFiles,
          limit: failure.limit,
          splitAttempted: failure.splitAttempted,
          images: failure.images,
          documentImages: failure.documentImages,
        ),
    ];

    try {
      return await _process(
        request: request,
        job: job.copyWith(
          status: GenerationJobStatus.running,
          clearErrorCode: true,
        ),
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

  /// Общий цикл обработки фрагментов (первый запуск и повтор упавших).
  Future<GenerationRunResult> _process({
    required GenerationRunRequest request,
    required GenerationJob job,
    required List<GenerationChunk> chunks,
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
    final List<GenerationChunk> queue = List<GenerationChunk>.of(chunks);
    final List<GeneratedCard> cards = List<GeneratedCard>.of(initialCards);
    final List<GenerationChunkFailure> failures = <GenerationChunkFailure>[];
    var tokensUsed = initialTokens;
    var processed = initialProcessed;
    var duplicates = initialDuplicates;
    var rejected = initialRejected;
    var cancelled = false;
    GenerationException? fatal;

    var index = 0;
    while (index < queue.length) {
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      final GenerationChunk chunk = queue[index];
      // Фрагмент без доли общего лимита (например, «1 карточка» на три
      // фрагмента) моделью не обрабатывается: иначе карточек будет больше,
      // чем просил пользователь.
      if (chunk.limit < 1) {
        index++;
        continue;
      }
      final List<DocumentImage> documentImages = withCatalogIds(
        chunk.documentImages,
      );
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
            images: chunk.images,
            documentImages: documentImages,
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
        if (error.code == GenerationErrorCode.truncated &&
            !chunk.splitAttempted) {
          final List<GenerationChunk>? halves = chunker.splitInHalf(chunk);
          if (halves != null) {
            queue.replaceRange(index, index + 1, halves);
            for (var i = 0; i < queue.length; i++) {
              queue[i] = queue[i].copyWith(index: i + 1);
            }
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
          ),
        );
        await _saveProgress(job, processed, cards.length, tokensUsed);
        index++;
        continue;
      } on Object {
        // Непредвиденная ошибка адаптера: карточки фрагмента не принимаются,
        // остальные фрагменты продолжаются (A6.8 «частичный успех»).
        processed++;
        failures.add(
          _failureOf(
            chunk,
            GenerationErrorCode.invalidResponse,
            reason: GenerationFailureReason.unknown,
            chunkCount: queue.length,
          ),
        );
        await _saveProgress(job, processed, cards.length, tokensUsed);
        index++;
        continue;
      }

      rejected += result.rejectedCards;
      tokensUsed += result.usage.totalTokens ?? 0;
      processed++;
      for (final GeneratedCard card in result.cards) {
        if (_acceptCard(card, seen)) {
          cards.add(
            await _withCardImage(
              card,
              documentImages,
              cancellation,
              wishes: request.wishes,
            ),
          );
        } else {
          duplicates++;
        }
      }
      onProgress?.call(
        GenerationProgress(
          phase: GenerationProgressPhase.receiving,
          chunkIndex: index + 1,
          chunkCount: queue.length,
        ),
      );
      await _saveProgress(job, processed, cards.length, tokensUsed);
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      index++;
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
        chunkCount: processed,
        cardsCount: cards.length,
        tokensUsed: tokensUsed,
        errorCode: errorCode,
        clearErrorCode: errorCode == null,
      ),
    );
    // Fatal без карточек — ошибка целиком; с карточками возвращаем результат,
    // чтобы пользователь мог открыть предпросмотр и сохранить полученное.
    if (fatal != null && !hasCards) throw fatal;

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

  /// Привязывает картинку к карточке (fix-gen, Д2/Д3).
  ///
  /// Приоритет 1 — изображение из прикреплённого файла по `image_id`; байты
  /// берутся из каталога фрагмента, внешний поиск не вызывается. Приоритет 2 —
  /// внешний поиск по `image_query` модели, только если `image_id` нет.
  /// Производных запросов из текста вопроса больше нет: неподходящая картинка
  /// хуже, чем её отсутствие (Д2).
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
            query: imageId,
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
      return _withoutImage(card);
    }
    final DateTime? searchStartedAt = _imageSearchBudgeted ? now() : null;
    final bool budgetExhausted =
        _imageSearchBudgeted && _imageSearchSpent >= imageSearchBudget;
    if (budgetExhausted) {
      diagnostics.imageSearch(
        query: query,
        outcome: 'пропущен: бюджет времени поиска исчерпан',
      );
      return _withoutImage(card, imageNotFound: true);
    }
    GeneratedCardImage? image;
    try {
      image = await _imageCache.putIfAbsent(
        query,
        () => imageFinder!.findImage(query),
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
      return _withoutImage(card, imageNotFound: true);
    }
    return card.copyWith(
      image: image,
      occlusionJson: card.isOcclusion
          ? card.occlusionJson ?? defaultOcclusionDocumentJson()
          : card.occlusionJson,
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
    GenerationChunk chunk,
    GenerationErrorCode code, {
    String? providerReason,
    GenerationFailureReason? reason,
    int? chunkCount,
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
      sourceFiles: chunk.sourceFiles,
      splitAttempted: chunk.splitAttempted,
      providerReason: providerReason,
      images: chunk.images,
      documentImages: chunk.documentImages,
      reason: effective,
    );
  }

  /// Принимает карточку, если её хеш (и обратный для reversed) новый.
  bool _acceptCard(GeneratedCard card, Set<String> seen) {
    final String hash = contentHashOf(front: card.front, back: card.back);
    if (card.cardType == CardType.basicReversed) {
      final String reversed = contentHashOf(front: card.back, back: card.front);
      if (seen.contains(hash) || seen.contains(reversed)) return false;
      seen
        ..add(hash)
        ..add(reversed);
      return true;
    }
    return seen.add(hash);
  }
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
  return List<String>.unmodifiable(names);
}

String _defaultJobId() => const Uuid().v4();
