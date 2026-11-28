import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

/// Срез 11, часть 3, п. 8: флаг `generationPipelineV3` действительно переключает
/// путь — включённый вызывает production-проводку фасада, выключенный оставляет
/// legacy без изменений. Оба прогона в одном тесте на одной проводке.
void main() {
  ParsedDocument docOf(String text) => ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'лекция.txt',
    text: text,
    sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
  );

  GenerationRunRequest requestFor(ParsedDocument document) =>
      GenerationRunRequest(
        documents: <ParsedDocument>[document],
        account: testProviderAccount(modelId: 'deepseek-chat'),
        deckName: 'Колода',
        requestedCards: 3,
      );

  GenerationRunResult pathResult(String jobId) => GenerationRunResult(
    jobId: jobId,
    status: GenerationJobStatus.partial,
    cards: <GeneratedCard>[
      const GeneratedCard(
        front: 'Вопрос из фасада v3',
        back: 'Ответ из фасада v3',
        cardType: CardType.basic,
      ),
    ],
    failures: const <GenerationChunkFailure>[],
    tokensUsed: 7,
    estimatedTokens: 0,
    duplicatesRemoved: 0,
    chunkCount: 1,
    cancelled: false,
  );

  test('флаг включён: вызывается путь v3, legacy не зовёт модель', () async {
    final FakeGenerationCaller caller = FakeGenerationCaller();
    final List<String> pathCalls = <String>[];
    final GenerationPipeline pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: FakeGenerationJobRepository(),
      cardStore: FakeGenerationCardStore(),
      now: () => DateTime.utc(2026, 11, 28, 10),
      jobIdFactory: () => 'job-v3-path',
      pipelineV3: true,
      v3Path:
          (
            GenerationRunRequest request, {
            required String runId,
            GenerationProgressCallback? onProgress,
            GenerationCancellation? cancellation,
          }) async {
            pathCalls.add(runId);
            return pathResult(runId);
          },
    );

    final GenerationRunResult result = await pipeline.run(
      requestFor(docOf('Интервальное повторение — метод обучения.')),
    );

    expect(pathCalls, <String>['job-v3-path']);
    expect(result.jobId, 'job-v3-path');
    expect(result.cards.single.front, 'Вопрос из фасада v3');
    expect(caller.requests, isEmpty, reason: 'legacy-вызовов быть не должно');
  });

  test('флаг выключен: путь v3 не вызывается, работает legacy', () async {
    final FakeGenerationCaller caller = FakeGenerationCaller();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        GenerationResult(
          provider: GenerationProvider.openai,
          model: 'test',
          promptVersion: 'gen-ru-v9',
          cards: <GeneratedCard>[
            const GeneratedCard(
              front: 'Вопрос legacy',
              back: 'Ответ legacy',
              cardType: CardType.basic,
            ),
          ],
          usage: const TokenUsage(promptTokens: 10, completionTokens: 5),
        );
    var pathCalls = 0;
    final GenerationPipeline pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: FakeGenerationJobRepository(),
      cardStore: FakeGenerationCardStore(),
      now: () => DateTime.utc(2026, 11, 28, 10),
      jobIdFactory: () => 'job-legacy',
      pipelineV3: false,
      v3Path:
          (
            GenerationRunRequest request, {
            required String runId,
            GenerationProgressCallback? onProgress,
            GenerationCancellation? cancellation,
          }) async {
            pathCalls++;
            return pathResult(runId);
          },
    );

    final GenerationRunResult result = await pipeline.run(
      requestFor(docOf('Интервальное повторение — метод обучения.')),
    );

    expect(pathCalls, 0, reason: 'выключенный флаг не включает фасад');
    expect(caller.requests, isNotEmpty, reason: 'legacy-путь работает');
    expect(result.jobId, 'job-legacy');
    expect(
      result.cards.any((GeneratedCard card) => card.front == 'Вопрос legacy'),
      isTrue,
    );
  });
}
