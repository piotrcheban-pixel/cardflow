/// Пайплайн генерации карточек: оценка, чанкинг, последовательные вызовы,
/// дедупликация, прогресс/отмена и `generation_jobs` (SPEC A8.5, ADR-015).
library;

import 'package:uuid/uuid.dart';

import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_model.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
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
    final String jobId = jobIdFactory();
    final DateTime createdAt = now();
    final int systemPromptTokens = estimator.estimate(systemPromptGenRuV2);
    final GenerationJob initialJob = GenerationJob(
      id: jobId,
      status: GenerationJobStatus.running,
      createdAt: createdAt,
      provider: request.provider.wireName,
      model: request.modelId,
      promptVersion: systemPromptVersion,
      chunkCount: 0,
      cardsCount: 0,
      files: <String>[
        for (final document in request.documents) document.fileName,
      ],
    );
    await jobRepository.save(initialJob);

    try {
      onProgress?.call(
        const GenerationProgress(phase: GenerationProgressPhase.chunking),
      );
      final int budget = inputTokenBudget(
        provider: request.provider,
        modelId: request.modelId,
        systemPromptTokens: systemPromptTokens,
      );
      final List<GenerationChunk> chunks = chunker.chunkDocuments(
        request.documents,
        maxInputTokens: budget,
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

    final GenerationJob job =
        await jobRepository.jobById(previous.jobId) ??
        GenerationJob(
          id: previous.jobId,
          status: GenerationJobStatus.partial,
          createdAt: now(),
          provider: request.provider.wireName,
          model: request.modelId,
          promptVersion: systemPromptVersion,
          files: <String>[
            for (final document in request.documents) document.fileName,
          ],
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
  }) async {
    final List<GenerationChunk> queue = List<GenerationChunk>.of(chunks);
    final List<GeneratedCard> cards = List<GeneratedCard>.of(initialCards);
    final List<GenerationChunkFailure> failures = <GenerationChunkFailure>[];
    var tokensUsed = initialTokens;
    var processed = initialProcessed;
    var duplicates = initialDuplicates;
    var cancelled = false;
    GenerationException? fatal;

    var index = 0;
    while (index < queue.length) {
      if (cancellation?.isCancelled ?? false) {
        cancelled = true;
        break;
      }
      final GenerationChunk chunk = queue[index];
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
            provider: request.provider,
            model: request.modelId,
            materialsText: chunk.materialsText,
            wishes: request.wishes,
            limit: chunk.limit,
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
        failures.add(_failureOf(chunk, error.code));
        await _saveProgress(job, processed, cards.length, tokensUsed);
        index++;
        continue;
      } on Object {
        // Непредвиденная ошибка адаптера: карточки фрагмента не принимаются,
        // остальные фрагменты продолжаются (A6.8 «частичный успех»).
        processed++;
        failures.add(_failureOf(chunk, GenerationErrorCode.invalidResponse));
        await _saveProgress(job, processed, cards.length, tokensUsed);
        index++;
        continue;
      }

      tokensUsed += result.usage.totalTokens ?? 0;
      processed++;
      for (final GeneratedCard card in result.cards) {
        if (_acceptCard(card, seen)) {
          cards.add(card);
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
        : failures.first.code.name;
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
      fatalErrorCode: fatal?.code,
    );
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

  /// Описание упавшего фрагмента для повтора.
  GenerationChunkFailure _failureOf(
    GenerationChunk chunk,
    GenerationErrorCode code,
  ) {
    return GenerationChunkFailure(
      chunkIndex: chunk.index,
      code: code,
      materialsText: chunk.materialsText,
      limit: chunk.limit,
      sourceFiles: chunk.sourceFiles,
      splitAttempted: chunk.splitAttempted,
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

String _defaultJobId() => const Uuid().v4();
