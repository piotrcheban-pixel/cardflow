import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generated_card_image_side.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

/// TASK 04, части 4–5: заказ карточек не «схлопывается», сбои партий и поиска
/// картинок не теряют уже созданное.
void main() {
  ParsedDocument docOf(int sections, int charsEach) {
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> parsed = <ParsedSection>[];
    for (var index = 0; index < sections; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      final StringBuffer text = StringBuffer();
      var word = 0;
      while (text.length < charsEach) {
        text.write('слово${word++} ');
      }
      buffer.write(text.toString().substring(0, charsEach));
      parsed.add(ParsedSection(start: start, end: buffer.length));
    }
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'лекция.txt',
      text: buffer.toString(),
      sections: parsed,
    );
  }

  GenerationResult resultOf(
    List<String> fronts, {
    int completionTokens = 600,
    bool sourceExhausted = false,
    bool truncated = false,
    int salvaged = 0,
    String? imageQuery,
  }) => GenerationResult(
    provider: GenerationProvider.openai,
    model: 'test',
    promptVersion: systemPromptVersion,
    cards: <GeneratedCard>[
      for (final String front in fronts)
        GeneratedCard(
          front: front,
          back: 'Ответ на $front',
          cardType: CardType.basic,
          imageQuery: imageQuery,
          imageSide: imageQuery == null
              ? GeneratedCardImageSide.none
              : GeneratedCardImageSide.question,
        ),
    ],
    usage: TokenUsage(completionTokens: completionTokens),
    sourceExhausted: sourceExhausted,
    truncated: truncated,
    salvagedCards: salvaged,
  );

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late List<String> diagnosticsLines;

  GenerationPipeline pipeline({CardImageFinder? imageFinder}) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    diagnosticsLines = <String>[];
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: FakeGenerationCardStore(),
      now: () => DateTime.utc(2026, 11, 27, 10),
      jobIdFactory: () => 'job-task04',
      imageFinder: imageFinder,
      diagnostics: GenerationDiagnostics(sink: diagnosticsLines.add),
    );
  }

  GenerationRunRequest requestFor(ParsedDocument document, int requested) =>
      GenerationRunRequest(
        documents: <ParsedDocument>[document],
        account: testProviderAccount(modelId: 'deepseek-chat'),
        deckName: 'Колода',
        requestedCards: requested,
      );

  test('заказ 10: ровно 10 карточек', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>[
          for (var index = 0; index < request.limit; index++)
            'Вопрос $call-$index',
        ]);
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(6, 300), 10),
    );
    expect(result.cards, hasLength(10));
    expect(result.status, GenerationJobStatus.done);
  });

  test('заказ 50 при сбоях и обрывах партий: цель добирается, карточки не теряются', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async {
      if (call == 1) {
        // Первая партия падает сетью — остальные должны продолжить работу.
        throw const GenerationException(GenerationErrorCode.network);
      }
      // Модель отдаёт на две карточки меньше лимита и обрывает ответ по
      // лимиту вывода: полные карточки спасаются, недостача добирается.
      final int count = request.limit > 2 ? request.limit - 2 : request.limit;
      return resultOf(
        <String>[
          for (var index = 0; index < count; index++) 'Вопрос $call-$index',
        ],
        truncated: true,
        salvaged: count,
      );
    };
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(200, 100), 50),
    );

    expect(
      result.cards,
      hasLength(50),
      reason: 'недобор партий компенсируется добором, заказ не срезается',
    );
    expect(result.status, GenerationJobStatus.done);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.code, GenerationErrorCode.network);
    expect(result.truncatedChunks, greaterThan(0));
    expect(result.salvagedCards, greaterThan(0));
    expect(caller.calls, greaterThan(result.plan!.chunks.length));
    expect(
      diagnosticsLines.join('\n'),
      contains('итог: запрошено=50'),
      reason: 'диагностика фиксирует заказ и факт',
    );
  });

  test('заказ 100: ровно 100 карточек за партии', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>[
          for (var index = 0; index < request.limit; index++)
            'Вопрос $call-$index',
        ]);
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(400, 200), 100),
    );
    expect(result.cards, hasLength(100));
    expect(result.status, GenerationJobStatus.done);
  });

  test(
    'картинка не нашлась: карточка сохраняется без изображения (best effort)',
    () async {
      final _FailingImageFinder finder = _FailingImageFinder();
      final GenerationPipeline runner = pipeline(imageFinder: finder);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultOf(<String>[
            for (var index = 0; index < request.limit; index++)
              'Вопрос $call-$index',
          ], imageQuery: 'схема фотосинтеза');

      final GenerationRunResult result = await runner.run(
        requestFor(docOf(6, 300), 10),
      );

      expect(result.cards, hasLength(10));
      expect(result.status, GenerationJobStatus.done);
      expect(finder.calls, greaterThan(0));
      for (final GeneratedCard card in result.cards) {
        expect(card.questionImages, isEmpty);
        expect(card.answerImages, isEmpty);
        expect(
          card.issues,
          contains(CardIssueCode.imageNotFound),
          reason: 'неудачный поиск — пометка, а не потеря карточки',
        );
      }
    },
  );

  test(
    'сбой поиска картинки не обрывает партию: следующие карточки создаются',
    () async {
      final _ThrowingImageFinder finder = _ThrowingImageFinder();
      final GenerationPipeline runner = pipeline(imageFinder: finder);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultOf(<String>[
            for (var index = 0; index < request.limit; index++)
              'Вопрос $call-$index',
          ], imageQuery: 'схема');

      final GenerationRunResult result = await runner.run(
        requestFor(docOf(6, 300), 10),
      );

      expect(result.cards, hasLength(10));
      expect(result.status, GenerationJobStatus.done);
      expect(result.imageResolveFailures, 0);
    },
  );

  test(
    'материал исчерпан: честный недобор (запрошено 20, создано меньше)',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async {
        if (call == 1) {
          return resultOf(<String>['Первый'], sourceExhausted: true);
        }
        return resultOf(<String>[]);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(docOf(200, 100), 20),
      );

      expect(result.requestedCards, 20);
      expect(result.cards.length, lessThan(20));
      expect(result.shortfallCards, greaterThan(0));
      expect(result.exhaustedSectionIds, isNotEmpty);
    },
  );
}

/// Поиск, который ничего не находит (но и не падает).
class _FailingImageFinder implements CardImageFinder {
  int calls = 0;

  @override
  Future<GeneratedCardImage?> findImage(
    String query, {
    String? fallbackQuery,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    Set<String>? excludedSourceUrls,
  }) async {
    calls++;
    return null;
  }
}

/// Поиск, который бросает исключение: best effort не должен ронять партию.
class _ThrowingImageFinder implements CardImageFinder {
  int calls = 0;

  @override
  Future<GeneratedCardImage?> findImage(
    String query, {
    String? fallbackQuery,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    Set<String>? excludedSourceUrls,
  }) async {
    calls++;
    throw StateError('провайдер картинок упал');
  }
}
