import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:cardflow/api/generation/generation_images.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/prompts/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

/// ADR-040 §7–8: производственная проводка плана, focus/партии, исчерпание,
/// почти-дубли и калибровка.
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
        ),
    ],
    usage: TokenUsage(completionTokens: completionTokens),
    sourceExhausted: sourceExhausted,
  );

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late FakeGenerationCardStore store;

  GenerationPipeline pipeline({
    TokenCalibrationStore? calibration,
    int maxTopUpRounds = 4,
    int maxOperationRequests = 0,
  }) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      now: () => DateTime.utc(2026, 11, 20, 10),
      jobIdFactory: () => 'job-v8',
      calibrationStore: calibration,
      maxTopUpRounds: maxTopUpRounds,
      maxOperationRequests: maxOperationRequests,
    );
  }

  GenerationRunRequest requestFor(
    ParsedDocument document, {
    int? requestedCards,
  }) => GenerationRunRequest(
    documents: <ParsedDocument>[document],
    account: testProviderAccount(modelId: 'deepseek-chat'),
    deckName: 'Колода',
    requestedCards: requestedCards,
  );

  test('whole-режим: focus/part/alreadyCreated и стабильный префикс', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>[
          for (var index = 0; index < request.limit; index++)
            'Вопрос $call-$index',
        ]);
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(200, 100), requestedCards: 50),
    );
    expect(result.status, GenerationJobStatus.done);
    final GenerationPlan plan = result.plan!;
    expect(plan.inputStrategy, InputStrategy.wholeDocument);
    expect(plan.chunks.length, greaterThan(1));
    expect(caller.calls, plan.chunks.length);
    expect(jobs.saved.last.chunkCount, plan.partCount);

    final List<GenerationRequest> requests = caller.requests;
    final String materials = requests.first.materialsText;
    for (final GenerationRequest request in requests) {
      expect(request.materialsText, materials);
      expect(request.focusSectionIds, isNotEmpty);
      expect(request.partIndexHint, 1);
      expect(request.partCountHint, 1);
      expect(request.wishes, isNull);
    }
    expect(requests.first.alreadyCreated, isNull);
    for (final GenerationRequest request in requests.skip(1)) {
      expect(request.alreadyCreated, isNotNull);
      expect(request.alreadyCreated, contains('Вопрос 1'));
    }
    final List<String> prefixes = <String>[
      for (final GenerationRequest request in requests)
        generationUserContentPrefix(
          buildGenerationUserContent(
            materialsText: request.materialsText,
            wishes: request.wishes,
            limit: request.limit,
            focusSectionIds: request.focusSectionIds,
            partIndexHint: request.partIndexHint,
            partCountHint: request.partCountHint,
            outline: request.outline,
            alreadyCreated: request.alreadyCreated,
          ),
        ),
    ];
    expect(prefixes.toSet(), hasLength(1), reason: 'кэш префикса');
  });

  test('изображения: id и каталог стабильны между партиями', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>[
          for (var index = 0; index < request.limit; index++)
            'Вопрос $call-$index',
        ]);
    final List<DocumentImage> images = <DocumentImage>[
      for (var index = 0; index < 3; index++)
        DocumentImage(
          fileName: 'scan$index.png',
          bytes: Uint8List.fromList(<int>[index + 1, index + 2, 10]),
          mediaType: AttachmentMediaType.png,
          caption: 'Рис. $index',
          sectionIndex: 0,
          page: 1,
        ),
    ];
    final GenerationRunResult result = await runner.run(
      GenerationRunRequest(
        documents: <ParsedDocument>[docOf(200, 100)],
        documentImages: images,
        account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
        deckName: 'Колода',
        requestedCards: 40,
      ),
    );
    expect(result.status, GenerationJobStatus.done);
    expect(caller.calls, greaterThan(1));
    final String catalog = buildImageCatalog(
      caller.requests.first.documentImages,
    );
    expect(catalog, contains('img1'));
    for (final GenerationRequest request in caller.requests) {
      expect(
        request.documentImages.map((DocumentImage image) => image.id).toList(),
        <String>['img1', 'img2', 'img3'],
        reason: 'id назначаются один раз по плану, а не по порядку партии',
      );
      expect(buildImageCatalog(request.documentImages), catalog);
    }
    final Set<String> prefixes = <String>{
      for (final GenerationRequest request in caller.requests)
        generationUserContentPrefix(
          buildGenerationUserContent(
            materialsText: request.materialsText,
            wishes: request.wishes,
            limit: request.limit,
            imagesCatalog: buildImageCatalog(request.documentImages),
            focusSectionIds: request.focusSectionIds,
            partIndexHint: request.partIndexHint,
            partCountHint: request.partCountHint,
            outline: request.outline,
            alreadyCreated: request.alreadyCreated,
          ),
        ),
    };
    expect(prefixes, hasLength(1), reason: 'кэш префикса с изображениями');
  });
  test(
    'source_exhausted: остаток разделов не запрашивается, недостача видна',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async {
        if (call == 1) {
          return resultOf(<String>['Первый'], sourceExhausted: true);
        }
        return resultOf(<String>[
          for (var index = 0; index < request.limit; index++)
            'Вопрос $call-$index',
        ]);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(docOf(200, 100), requestedCards: 40),
      );
      expect(result.status, GenerationJobStatus.done);
      expect(result.exhaustedSectionIds, isNotEmpty);
      expect(result.shortfallCards, greaterThan(0));
      expect(
        caller.calls,
        3,
        reason: 'две партии + однократное перераспределение',
      );
      // Последняя (дополнительная) партия не просит исчерпанные разделы.
      final GenerationRequest last = caller.requests.last;
      for (final String section in result.exhaustedSectionIds) {
        expect(last.focusSectionIds, isNot(contains(section)));
      }
      expect(
        jobs.saved.last.chunkCount,
        result.plan!.partCount,
        reason: 'chunk_count — части входа (ADR-040 §8)',
      );
    },
  );

  test('почти-дубли (триграммы ≥ 0.85) не принимаются повторно', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async => resultOf(
      <String>['Что такое FSRS?', 'что такое fsrs', 'Чем отличается интервал?'],
    );
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(3, 400), requestedCards: 3),
    );
    expect(result.cards, hasLength(2));
    expect(result.duplicatesRemoved, greaterThanOrEqualTo(1));
  });

  test('калибровка: наблюдаемые tpc пишутся в store после прогонов', () async {
    final _FakeCalibrationStore calibration = _FakeCalibrationStore();
    final GenerationPipeline runner = pipeline(calibration: calibration);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>['Вопрос $call', 'Ещё $call'], completionTokens: 600);
    await runner.run(requestFor(docOf(3, 400), requestedCards: 2));
    await runner.run(requestFor(docOf(3, 400), requestedCards: 2));
    expect(calibration.observed, hasLength(2));
    expect(calibration.observed.first, closeTo(300, 1e-9));
    expect(calibration.observed.last, closeTo(300, 1e-9));
  });

  test(
    'добор: недобор партий компенсируется раундами top-up до цели',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async {
        final int count = request.limit > 2 ? request.limit - 2 : request.limit;
        return resultOf(<String>[
          for (var index = 0; index < count; index++) 'Вопрос $call-$index',
        ]);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(docOf(3, 400), requestedCards: 10),
      );
      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, hasLength(10));
      expect(caller.calls, greaterThan(1));
    },
  );

  test('бюджет операции: лимит запросов останавливает добор', () async {
    final GenerationPipeline runner = pipeline(maxOperationRequests: 2);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>['Вопрос $call']);
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(3, 400), requestedCards: 5),
    );
    expect(result.status, GenerationJobStatus.partial);
    expect(caller.calls, 2);
  });
  test('статус partial: цель не достигнута без добора', () async {
    final GenerationPipeline runner = pipeline(maxTopUpRounds: 0);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultOf(<String>['Вопрос $call']);
    final GenerationRunResult result = await runner.run(
      requestFor(docOf(3, 400), requestedCards: 5),
    );
    expect(result.status, GenerationJobStatus.partial);
    expect(result.cards.length, lessThan(5));
  });

  for (final int count in <int>[10, 20, 32, 40, 80, 150]) {
    test('цель $count карточек достигается при полной отдаче модели', () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultOf(<String>[
            for (var index = 0; index < request.limit; index++)
              'Вопрос $call-$index',
          ]);
      final GenerationRunResult result = await runner.run(
        requestFor(docOf(40, 1000), requestedCards: count),
      );
      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, hasLength(count));
    });
  }
}

class _FakeCalibrationStore implements TokenCalibrationStore {
  final List<double> observed = <double>[];

  @override
  Future<List<TokenCalibration>> readAll() async => const <TokenCalibration>[];

  @override
  Future<TokenCalibration?> read({
    required String accountId,
    required String model,
  }) async => null;

  @override
  Future<TokenCalibration> record({
    required String accountId,
    required String model,
    required double observedTokensPerCard,
    DateTime? at,
  }) async {
    observed.add(observedTokensPerCard);
    return TokenCalibration(
      accountId: accountId,
      model: model,
      tokensPerCard: observedTokensPerCard,
      samples: observed.length,
      updatedAt: at ?? DateTime.utc(2026, 11, 20),
    );
  }
}
