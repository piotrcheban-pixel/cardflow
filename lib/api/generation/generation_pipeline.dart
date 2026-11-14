/// Пайплайн генерации карточек: оценка, чанкинг, последовательные вызовы,
/// дедупликация, прогресс/отмена и `generation_jobs` (SPEC A8.5, ADR-015).
library;

import 'package:uuid/uuid.dart';

import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';

/// Оркестратор генерации.
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

  /// Запускает генерацию.
  @override
  Future<GenerationRunResult> run(
    GenerationRunRequest request, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) {
    throw UnimplementedError('GenerationPipeline.run');
  }

  /// Повторяет только упавшие фрагменты предыдущего результата.
  @override
  Future<GenerationRunResult> retryFailed(
    GenerationRunRequest request,
    GenerationRunResult previous, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) {
    throw UnimplementedError('GenerationPipeline.retryFailed');
  }
}

DateTime _defaultNow() => DateTime.now();

String _defaultJobId() => const Uuid().v4();
