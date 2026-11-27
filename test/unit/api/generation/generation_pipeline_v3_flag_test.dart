import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

/// Срез 9: флаг `pipelineV3` переключает путь без пересборки.
///
/// На пути v3 почти-дубль помечается и остаётся (ARCH §3.4), статус задания
/// берётся из вердикта по журналу (ARCH §3.2), «Почему?» показывает блок
/// источника, а метрики прогона собираются числами.
void main() {
  ParsedDocument docOf(String text) {
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'лекция.txt',
      text: text,
      sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
    );
  }

  GenerationResult resultOf(
    List<GeneratedCard> cards, {
    int promptTokens = 1000,
    int completionTokens = 500,
  }) => GenerationResult(
    provider: GenerationProvider.openai,
    model: 'test',
    promptVersion: systemPromptVersion,
    cards: cards,
    usage: TokenUsage(
      promptTokens: promptTokens,
      completionTokens: completionTokens,
      totalTokens: promptTokens + completionTokens,
    ),
  );

  const GeneratedCard first = GeneratedCard(
    front: 'Что такое интервальное повторение карточек',
    back: 'Метод повторения с возрастающими интервалами',
    cardType: CardType.basic,
  );
  const GeneratedCard nearDuplicate = GeneratedCard(
    front: 'Что такое интервальное повторение карточек',
    back: 'Повторение по расписанию с растущими промежутками',
    cardType: CardType.basic,
  );

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late FakeGenerationCardStore store;

  GenerationPipeline pipeline({required bool pipelineV3}) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      now: () => DateTime.utc(2026, 11, 28, 10),
      jobIdFactory: () => 'job-v3',
      pipelineV3: pipelineV3,
    );
  }

  GenerationRunRequest requestFor(ParsedDocument document) {
    return GenerationRunRequest(
      documents: <ParsedDocument>[document],
      account: testProviderAccount(modelId: 'deepseek-chat'),
      deckName: 'Колода',
      requestedCards: 10,
    );
  }

  test('флаг выключен: почти-дубль отбрасывается, как раньше', () async {
    final GenerationPipeline runner = pipeline(pipelineV3: false);
    caller.onGenerate = (GenerationRequest request, int call) async => call == 1
        ? resultOf(<GeneratedCard>[first, nearDuplicate])
        : resultOf(const <GeneratedCard>[]);

    final GenerationRunResult result = await runner.run(
      requestFor(docOf('Интервальное повторение — метод обучения.')),
    );

    expect(result.cards.length, 1);
    expect(result.duplicatesRemoved, 1);
    expect(result.possibleDuplicates, 0);
    expect(
      result.cards.single.issues.contains(CardIssueCode.possibleDuplicate),
      isFalse,
    );
    // Вердикт считается для обоих путей, но старый статус не меняется.
    expect(result.verdict, isNotNull);
    expect(result.verdict!.isDone, isFalse);
  });

  test('флаг включён: почти-дубль помечен и оставлен (ARCH §3.4)', () async {
    final GenerationPipeline runner = pipeline(pipelineV3: true);
    caller.onGenerate = (GenerationRequest request, int call) async => call == 1
        ? resultOf(<GeneratedCard>[first, nearDuplicate])
        : resultOf(const <GeneratedCard>[]);

    final GenerationRunResult result = await runner.run(
      requestFor(docOf('Интервальное повторение — метод обучения.')),
    );

    expect(result.cards.length, 2);
    expect(result.duplicatesRemoved, 0);
    expect(result.possibleDuplicates, 1);
    expect(
      result.cards.last.issues.contains(CardIssueCode.possibleDuplicate),
      isTrue,
    );
    expect(result.metrics.duplicatesByLevel[DedupLevel.semantic], 1);
    expect(result.metrics.duplicateRate, greaterThan(0));
  });

  test('флаг включён: недобор — partial по журналу с причиной', () async {
    final GenerationPipeline runner = pipeline(pipelineV3: true);
    caller.onGenerate = (GenerationRequest request, int call) async => call == 1
        ? resultOf(<GeneratedCard>[first])
        : resultOf(const <GeneratedCard>[]);

    final GenerationRunResult result = await runner.run(
      requestFor(docOf('Интервальное повторение — метод обучения.')),
    );

    expect(result.status, GenerationJobStatus.partial);
    expect(result.verdict, isNotNull);
    expect(result.verdict!.outcome, CompletionOutcome.partial);
    expect(result.verdict!.requested, 10);
    expect(result.verdict!.accepted, 1);
    expect(result.verdict!.reasons, contains(ShortfallKind.exhaustedMaterial));
    expect(result.metrics.yieldPerThousandInputTokens, greaterThan(0));
    expect(result.metrics.acceptanceRate, 1);
    expect(result.metrics.requests, greaterThan(0));
    expect(result.metrics.p50BatchDuration, isNotNull);
  });

  test(
    'флаг включён: «Почему?» получает блок источника, а не склейку',
    () async {
      final GenerationPipeline runner = pipeline(pipelineV3: true);
      const GeneratedCard anchored = GeneratedCard(
        front: 'Что такое интервальное повторение?',
        back: 'Метод с возрастающими интервалами',
        cardType: CardType.basic,
        sourceExcerpt: 'Вторая строка материала',
      );
      caller.onGenerate = (GenerationRequest request, int call) async =>
          call == 1
          ? resultOf(<GeneratedCard>[anchored])
          : resultOf(const <GeneratedCard>[]);

      final GenerationRunResult result = await runner.run(
        requestFor(
          docOf('Первая строка материала\nВторая строка материала целиком'),
        ),
      );

      expect(
        result.cards.single.sourceAnchorText,
        'Вторая строка материала целиком',
      );
      expect(result.cards.single.sourceAnchorText!.contains('\n'), isFalse);
    },
  );
}
