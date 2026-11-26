import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/generation_fakes.dart';

/// Итерация «Диагностика и фикс пайплайна генерации»: сбой локального
/// хранилища (`generation_jobs`) обязан доходить до UI доменным кодом
/// `storageUnavailable`, а не произвольным исключением, которое экран
/// показывает общей строкой «Не удалось получить карточки».
void main() {
  ProviderAccount account() => const ProviderAccount(
    id: 'openai_compatible',
    label: 'DeepSeek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.com',
    modelId: 'deepseek-flash',
    requiresApiKey: true,
  );

  GenerationRunRequest request() => GenerationRunRequest(
    documents: const <Never>[],
    account: account(),
    deckName: 'Диагностика',
    wishes: 'трансформаторы',
    requestedCards: 10,
  );

  test(
    'сбой записи generation_jobs → storageUnavailable и причина storage',
    () async {
      final FakeGenerationJobRepository jobs = FakeGenerationJobRepository(
        saveError: Exception('attempt to write a readonly database'),
      );
      final GenerationPipeline pipeline = GenerationPipeline(
        caller: FakeGenerationCaller(),
        jobRepository: jobs,
        cardStore: FakeGenerationCardStore(),
        diagnostics: const GenerationDiagnostics(enabled: false),
      );

      Object? error;
      try {
        await pipeline.run(request());
      } on Object catch (caught) {
        error = caught;
      }

      expect(error, isA<GenerationException>());
      final GenerationException failure = error! as GenerationException;
      expect(failure.code, GenerationErrorCode.storageUnavailable);
      expect(failure.reason, GenerationFailureReason.storage);
      // Сырое исключение drift/SQLite не пробрасывается: только тип в details.
      expect(failure.details, contains('Exception'));
      expect(failure.details, isNot(contains('sk-')));
      expect(jobs.saved, isEmpty, reason: 'запись не удалась — версии нет');
    },
  );

  test(
    'сбой чтения generation_jobs при повторе → storageUnavailable',
    () async {
      final FakeGenerationJobRepository jobs = FakeGenerationJobRepository(
        readError: Exception('database is locked'),
      );
      final GenerationPipeline pipeline = GenerationPipeline(
        caller: FakeGenerationCaller(),
        jobRepository: jobs,
        cardStore: FakeGenerationCardStore(),
        diagnostics: const GenerationDiagnostics(enabled: false),
      );
      final GenerationRunResult previous = GenerationRunResult(
        jobId: 'job-1',
        status: GenerationJobStatus.partial,
        cards: const <GeneratedCard>[],
        failures: <GenerationChunkFailure>[
          const GenerationChunkFailure(
            chunkIndex: 1,
            code: GenerationErrorCode.network,
            materialsText: 'Материал',
            limit: 2,
          ),
        ],
        tokensUsed: 0,
        estimatedTokens: 0,
        duplicatesRemoved: 0,
        chunkCount: 1,
        cancelled: false,
      );

      Object? error;
      try {
        await pipeline.retryFailed(request(), previous);
      } on Object catch (caught) {
        error = caught;
      }

      expect(error, isA<GenerationException>());
      expect(
        (error! as GenerationException).code,
        GenerationErrorCode.storageUnavailable,
      );
    },
  );

  test('сеть и ответ модели не превращаются в storageUnavailable', () async {
    final FakeGenerationJobRepository jobs = FakeGenerationJobRepository();
    final FakeGenerationCaller caller = FakeGenerationCaller(
      responses: <Object>[
        const GenerationException(
          GenerationErrorCode.network,
          details: 'ошибка соединения',
        ),
      ],
    );
    final GenerationPipeline pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: FakeGenerationCardStore(),
      diagnostics: const GenerationDiagnostics(enabled: false),
    );

    final GenerationRunResult result = await pipeline.run(request());
    expect(result.cards, isEmpty);
    expect(result.failures, isNotEmpty);
    expect(result.failures.first.code, GenerationErrorCode.network);
    expect(
      result.failures.map((GenerationChunkFailure f) => f.code),
      isNot(contains(GenerationErrorCode.storageUnavailable)),
    );
  });
}
