import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

ParsedDocument docOf(String fileName, List<String> sections) {
  final buffer = StringBuffer();
  final parsed = <ParsedSection>[];
  for (var i = 0; i < sections.length; i++) {
    if (i > 0) buffer.write('\n\n');
    final start = buffer.length;
    buffer.write(sections[i]);
    parsed.add(ParsedSection(start: start, end: buffer.length));
  }
  return ParsedDocument(
    format: DocumentFormat.txt,
    fileName: fileName,
    text: buffer.toString(),
    sections: parsed,
  );
}

GenerationResult resultWith(
  List<GeneratedCard> cards, {
  int tokens = 30,
  int? totalTokens,
}) {
  return GenerationResult(
    provider: GenerationProvider.openai,
    model: 'gpt-4o',
    promptVersion: systemPromptVersion,
    cards: cards,
    usage: TokenUsage(
      promptTokens: 10,
      completionTokens: 20,
      totalTokens: totalTokens ?? tokens,
    ),
  );
}

/// Чанкер с заранее заданными фрагментами (проверка пайплайна без нарезки).
class FixedChunker extends GenerationChunker {
  FixedChunker(this.chunks);

  final List<GenerationChunk> chunks;

  @override
  List<GenerationChunk> chunkDocuments(
    List<ParsedDocument> documents, {
    required int maxInputTokens,
  }) {
    return chunks;
  }
}

GenerationChunk chunkOf(int index, String text, {int limit = 10}) {
  return GenerationChunk(
    index: index,
    materialsText: text,
    sourceFiles: const <String>['материал.txt'],
    limit: limit,
  );
}

void main() {
  GenerationRunRequest requestWith(
    List<ParsedDocument> documents, {
    String? targetDeckId,
    List<GenerationAttachment> images = const <GenerationAttachment>[],
  }) {
    return GenerationRunRequest(
      documents: documents,
      images: images,
      account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
      deckName: 'Новая колода',
      wishes: 'Покороче',
      targetDeckId: targetDeckId,
    );
  }

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late FakeGenerationCardStore store;

  GenerationPipeline pipelineWith(List<GenerationChunk> chunks) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      chunker: FixedChunker(chunks),
      now: () => DateTime.utc(2026, 11, 14, 10),
      jobIdFactory: () => 'job-1',
    );
  }

  test('успех: один фрагмент → карточки, токены, задание done', () async {
    final pipeline = pipelineWith(<GenerationChunk>[
      chunkOf(1, 'материал лекции'),
    ]);
    caller.onGenerate = (GenerationRequest request, int call) async {
      expect(request.materialsText, 'материал лекции');
      expect(request.limit, 10);
      expect(
        request.account.protocol.adapterProvider,
        GenerationProvider.openai,
      );
      expect(request.account.modelId, 'gpt-4o');
      expect(request.wishes, 'Покороче');
      return resultWith(<GeneratedCard>[makeGeneratedCard()], tokens: 30);
    };

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['материал лекции']),
      ]),
    );

    expect(result.status, GenerationJobStatus.done);
    expect(result.cancelled, isFalse);
    expect(result.cards, hasLength(1));
    expect(result.failures, isEmpty);
    expect(result.tokensUsed, 30);
    expect(result.estimatedTokens, greaterThan(0));
    expect(result.chunkCount, 1);
    expect(result.jobId, 'job-1');

    expect(jobs.saved, isNotEmpty);
    expect(jobs.saved.first.status, GenerationJobStatus.running);
    expect(jobs.saved.first.files, <String>['a.txt']);
    expect(jobs.saved.first.promptVersion, systemPromptVersion);
    final finalJob = jobs.saved.last;
    expect(finalJob.status, GenerationJobStatus.done);
    expect(finalJob.cardsCount, 1);
    expect(finalJob.chunkCount, 1);
    expect(finalJob.tokensUsed, 30);
    expect(finalJob.provider, 'openai');
    expect(finalJob.model, 'gpt-4o');
  });

  test('несколько фрагментов обрабатываются последовательно', () async {
    final pipeline = pipelineWith(<GenerationChunk>[
      chunkOf(1, 'первый'),
      chunkOf(2, 'второй'),
    ]);
    caller.onGenerate = (GenerationRequest request, int call) async {
      return resultWith(<GeneratedCard>[
        makeGeneratedCard(front: 'Вопрос $call', back: 'Ответ $call'),
      ]);
    };

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['первый второй']),
      ]),
    );

    expect(caller.calls, 2);
    expect(caller.requests[0].materialsText, 'первый');
    expect(caller.requests[1].materialsText, 'второй');
    expect(result.cards, hasLength(2));
    expect(result.tokensUsed, 60);
    expect(result.chunkCount, 2);
    expect(jobs.saved.last.chunkCount, 2);
  });

  test('дедупликация между фрагментами: первый выигрывает', () async {
    final pipeline = pipelineWith(<GenerationChunk>[
      chunkOf(1, 'первый'),
      chunkOf(2, 'второй'),
    ]);
    final card = makeGeneratedCard();
    caller.onGenerate = (request, call) async => call == 1
        ? resultWith(<GeneratedCard>[card])
        : resultWith(<GeneratedCard>[
            card,
            makeGeneratedCard(front: 'Другой', back: 'Ответ'),
          ]);

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['первый второй']),
      ]),
    );

    expect(
      result.cards.where((item) => item.front == card.front),
      hasLength(1),
    );
    expect(result.cards, hasLength(2));
    expect(result.duplicatesRemoved, 1);
  });

  test('дедупликация с существующей колодой (content_hash)', () async {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    final existing = makeGeneratedCard();
    store = FakeGenerationCardStore(
      existingByDeck: <String, Set<String>>{
        'deck-1': <String>{
          contentHashOf(front: existing.front, back: existing.back),
        },
      },
    );
    final pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      chunker: FixedChunker(<GenerationChunk>[chunkOf(1, 'материал')]),
      now: () => DateTime.utc(2026),
      jobIdFactory: () => 'job-1',
    );
    caller.onGenerate = (request, call) async => resultWith(<GeneratedCard>[
      existing,
      makeGeneratedCard(front: 'Новый', back: 'Ответ'),
    ]);

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['материал']),
      ], targetDeckId: 'deck-1'),
    );

    expect(result.cards, hasLength(1));
    expect(result.cards.single.front, 'Новый');
    expect(result.duplicatesRemoved, 1);
  });

  test('дедупликация basic_reversed учитывает обе стороны', () async {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    final reversed = makeGeneratedCard(
      front: 'Термин',
      back: 'Определение',
      cardType: CardType.basicReversed,
    );
    store = FakeGenerationCardStore(
      existingByDeck: <String, Set<String>>{
        'deck-1': <String>{
          contentHashOf(front: reversed.back, back: reversed.front),
        },
      },
    );
    final pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      chunker: FixedChunker(<GenerationChunk>[chunkOf(1, 'материал')]),
      now: () => DateTime.utc(2026),
      jobIdFactory: () => 'job-1',
    );
    caller.onGenerate = (request, call) async =>
        resultWith(<GeneratedCard>[reversed]);

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['материал']),
      ], targetDeckId: 'deck-1'),
    );

    expect(result.cards, isEmpty);
    expect(result.duplicatesRemoved, 1);
  });

  test(
    'fatal-ошибка invalidApiKey останавливает пайплайн и job = error',
    () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        chunkOf(1, 'первый'),
        chunkOf(2, 'второй'),
      ]);
      caller.onGenerate = (request, call) async {
        throw const GenerationException(GenerationErrorCode.invalidApiKey);
      };

      await expectLater(
        pipeline.run(
          requestWith(<ParsedDocument>[
            docOf('a.txt', <String>['первый второй']),
          ]),
        ),
        throwsA(
          isA<GenerationException>().having(
            (error) => error.code,
            'code',
            GenerationErrorCode.invalidApiKey,
          ),
        ),
      );

      expect(caller.calls, 1, reason: 'второй фрагмент не должен вызываться');
      expect(jobs.saved.last.status, GenerationJobStatus.error);
      expect(jobs.saved.last.errorCode, 'invalidApiKey');
    },
  );

  test('частичный успех: ошибка фрагмента не теряет остальные', () async {
    final pipeline = pipelineWith(<GenerationChunk>[
      chunkOf(1, 'первый'),
      chunkOf(2, 'второй'),
      chunkOf(3, 'третий'),
    ]);
    caller.onGenerate = (request, call) async {
      if (call == 2) {
        throw const GenerationException(GenerationErrorCode.network);
      }
      return resultWith(<GeneratedCard>[
        makeGeneratedCard(front: 'Вопрос $call', back: 'Ответ $call'),
      ]);
    };

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['раз два три']),
      ]),
    );

    expect(caller.calls, 3);
    expect(result.status, GenerationJobStatus.partial);
    expect(result.cards, hasLength(2));
    expect(result.failures, hasLength(1));
    expect(result.failures.single.code, GenerationErrorCode.network);
    expect(result.failures.single.materialsText, 'второй');
    expect(result.failures.single.limit, 10);
    expect(result.failures.single.retryable, isTrue);
    expect(jobs.saved.last.status, GenerationJobStatus.partial);
    expect(jobs.saved.last.errorCode, 'network');
  });

  test('ошибка без полученных карточек — job error', () async {
    final pipeline = pipelineWith(<GenerationChunk>[chunkOf(1, 'первый')]);
    caller.onGenerate = (request, call) async {
      throw const GenerationException(GenerationErrorCode.serverUnavailable);
    };

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['первый']),
      ]),
    );

    expect(result.status, GenerationJobStatus.error);
    expect(result.cards, isEmpty);
    expect(result.failures, hasLength(1));
  });

  test(
    'отмена: полученное сохраняется, job = cancelled, вызовов больше нет',
    () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        chunkOf(1, 'первый'),
        chunkOf(2, 'второй'),
      ]);
      final cancellation = GenerationCancellation();
      caller.onGenerate = (request, call) async {
        cancellation.cancel();
        return resultWith(<GeneratedCard>[makeGeneratedCard()]);
      };

      final result = await pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['первый второй']),
        ]),
        cancellation: cancellation,
      );

      expect(caller.calls, 1);
      expect(result.cancelled, isTrue);
      expect(result.status, GenerationJobStatus.cancelled);
      expect(result.cards, hasLength(1));
      expect(jobs.saved.last.status, GenerationJobStatus.cancelled);
    },
  );

  test('truncated: фрагмент делится пополам и повторяется один раз', () async {
    final pipeline = pipelineWith(<GenerationChunk>[
      chunkOf(1, 'Первая половина\n\nВторая половина'),
    ]);
    caller.onGenerate = (request, call) async {
      if (call == 1) {
        throw const GenerationException(GenerationErrorCode.truncated);
      }
      return resultWith(<GeneratedCard>[makeGeneratedCard()]);
    };

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['раз два']),
      ]),
    );

    expect(caller.calls, 3);
    expect(
      caller.requests[1].materialsText,
      isNot(caller.requests[0].materialsText),
    );
    expect(result.status, GenerationJobStatus.done);
    expect(result.failures, isEmpty);
    expect(result.cards, hasLength(1));
  });

  test('truncated дважды — ошибка фрагмента, без третьего вызова', () async {
    final pipeline = pipelineWith(<GenerationChunk>[
      chunkOf(1, 'Первая половина\n\nВторая половина'),
    ]);
    caller.onGenerate = (request, call) async {
      throw const GenerationException(GenerationErrorCode.truncated);
    };

    final result = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['раз два']),
      ]),
    );

    expect(caller.calls, 3);
    expect(result.status, GenerationJobStatus.error);
    expect(result.failures, hasLength(2));
    for (final failure in result.failures) {
      expect(failure.code, GenerationErrorCode.truncated);
    }
  });

  test('нет материала после нарезки — noMaterials, задание error', () async {
    final pipeline = pipelineWith(const <GenerationChunk>[]);

    await expectLater(
      pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['материал']),
        ]),
      ),
      throwsA(
        isA<GenerationException>().having(
          (error) => error.code,
          'code',
          GenerationErrorCode.noMaterials,
        ),
      ),
    );
    expect(caller.calls, 0);
    expect(jobs.saved, isNotEmpty);
    expect(jobs.saved.last.status, GenerationJobStatus.error);
    expect(jobs.saved.last.errorCode, 'noMaterials');
  });

  test(
    'прогресс: chunking → sending/receiving с номерами фрагментов',
    () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        chunkOf(1, 'первый'),
        chunkOf(2, 'второй'),
      ]);
      caller.onGenerate = (request, call) async => resultWith(<GeneratedCard>[
        makeGeneratedCard(front: 'В$call', back: 'О$call'),
      ]);
      final progress = <GenerationProgress>[];

      await pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['первый второй']),
        ]),
        onProgress: progress.add,
      );

      expect(progress.first.phase, GenerationProgressPhase.chunking);
      final sending = progress
          .where((item) => item.phase == GenerationProgressPhase.sending)
          .toList();
      expect(sending, hasLength(2));
      expect(sending[0].chunkIndex, 1);
      expect(sending[0].chunkCount, 2);
      expect(sending[1].chunkIndex, 2);
      expect(
        progress.where(
          (item) => item.phase == GenerationProgressPhase.receiving,
        ),
        hasLength(2),
      );
    },
  );

  test(
    'retryFailed: повторяет только упавшие фрагменты и дедуплицирует',
    () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        chunkOf(1, 'первый'),
        chunkOf(2, 'второй'),
      ]);
      caller.onGenerate = (request, call) async {
        if (call == 2) {
          throw const GenerationException(GenerationErrorCode.network);
        }
        return resultWith(<GeneratedCard>[
          makeGeneratedCard(front: 'Вопрос 1', back: 'Ответ 1'),
        ]);
      };
      final first = await pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['раз два']),
        ]),
      );
      expect(first.failures, hasLength(1));

      final retryCaller = FakeGenerationCaller();
      final retryPipeline = GenerationPipeline(
        caller: retryCaller,
        jobRepository: jobs,
        cardStore: store,
        chunker: FixedChunker(<GenerationChunk>[
          chunkOf(1, 'первый'),
          chunkOf(2, 'второй'),
        ]),
        now: () => DateTime.utc(2026),
        jobIdFactory: () => 'job-1',
      );
      retryCaller.onGenerate = (request, call) async => resultWith(
        <GeneratedCard>[makeGeneratedCard(front: 'Вопрос 2', back: 'Ответ 2')],
      );

      final result = await retryPipeline.retryFailed(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['раз два']),
        ]),
        first,
      );

      expect(retryCaller.calls, 1);
      expect(retryCaller.requests.single.materialsText, 'второй');
      expect(result.cards, hasLength(2));
      expect(result.failures, isEmpty);
      expect(result.status, GenerationJobStatus.done);
      expect(result.jobId, first.jobId);
      expect(jobs.saved.last.status, GenerationJobStatus.done);
    },
  );

  test('retryFailed без ошибок возвращает результат без вызовов', () async {
    final pipeline = pipelineWith(<GenerationChunk>[chunkOf(1, 'первый')]);
    caller.onGenerate = (request, call) async =>
        resultWith(<GeneratedCard>[makeGeneratedCard()]);
    final first = await pipeline.run(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['первый']),
      ]),
    );

    final retryCaller = FakeGenerationCaller();
    final retryPipeline = GenerationPipeline(
      caller: retryCaller,
      jobRepository: jobs,
      cardStore: store,
      chunker: FixedChunker(const <GenerationChunk>[]),
      now: () => DateTime.utc(2026),
      jobIdFactory: () => 'job-1',
    );
    final result = await retryPipeline.retryFailed(
      requestWith(<ParsedDocument>[
        docOf('a.txt', <String>['первый']),
      ]),
      first,
    );

    expect(retryCaller.calls, 0);
    expect(result.cards, hasLength(1));
    expect(result.status, GenerationJobStatus.done);
  });

  test(
    'fatal после полученных карточек: partial + fatalErrorCode, без throw',
    () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        chunkOf(1, 'первый'),
        chunkOf(2, 'второй'),
      ]);
      caller.onGenerate = (request, call) async {
        if (call == 2) {
          throw const GenerationException(GenerationErrorCode.invalidApiKey);
        }
        return resultWith(<GeneratedCard>[makeGeneratedCard()]);
      };

      final result = await pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['первый второй']),
        ]),
      );

      expect(caller.calls, 2);
      expect(result.cards, hasLength(1));
      expect(result.status, GenerationJobStatus.partial);
      expect(result.fatalErrorCode, GenerationErrorCode.invalidApiKey);
      expect(jobs.saved.last.status, GenerationJobStatus.partial);
      expect(jobs.saved.last.errorCode, 'invalidApiKey');
    },
  );

  test(
    'retryFailed: фрагмент, упавший без дробления, может быть раздроблен',
    () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        chunkOf(1, 'Первая половина\n\nВторая половина'),
      ]);
      caller.onGenerate = (request, call) async {
        throw const GenerationException(GenerationErrorCode.network);
      };
      final first = await pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['раз два']),
        ]),
      );
      expect(first.failures, hasLength(1));

      final retryCaller = FakeGenerationCaller();
      var retryCall = 0;
      retryCaller.onGenerate = (request, call) async {
        retryCall++;
        if (retryCall == 1) {
          throw const GenerationException(GenerationErrorCode.truncated);
        }
        return resultWith(<GeneratedCard>[
          makeGeneratedCard(
            front: 'Вопрос $retryCall',
            back: 'Ответ $retryCall',
          ),
        ]);
      };
      final retryPipeline = GenerationPipeline(
        caller: retryCaller,
        jobRepository: jobs,
        cardStore: store,
        chunker: const GenerationChunker(),
        now: () => DateTime.utc(2026),
        jobIdFactory: () => 'job-1',
      );

      final result = await retryPipeline.retryFailed(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['раз два']),
        ]),
        first,
      );

      expect(retryCaller.calls, 3, reason: 'truncated → две половины');
      expect(result.failures, isEmpty);
      expect(result.cards, hasLength(2));
    },
  );

  test('ошибка чтения хешей колоды: задание остаётся не running', () async {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore()..existingError = StateError('db down');
    final pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      chunker: FixedChunker(<GenerationChunk>[chunkOf(1, 'материал')]),
      now: () => DateTime.utc(2026),
      jobIdFactory: () => 'job-1',
    );

    await expectLater(
      pipeline.run(
        requestWith(<ParsedDocument>[
          docOf('a.txt', <String>['материал']),
        ], targetDeckId: 'deck-1'),
      ),
      throwsStateError,
    );

    expect(caller.calls, 0);
    expect(jobs.saved.last.status, GenerationJobStatus.error);
    expect(jobs.saved.last.errorCode, 'unexpected');
  });

  test(
    'изображение: вызывается модель с вложением, job.files его содержит',
    () async {
      final GenerationAttachment image = GenerationAttachment(
        fileName: 'схема.png',
        mediaType: AttachmentMediaType.png,
        bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
      );
      caller = FakeGenerationCaller();
      jobs = FakeGenerationJobRepository();
      store = FakeGenerationCardStore();
      final pipeline = GenerationPipeline(
        caller: caller,
        jobRepository: jobs,
        cardStore: store,
        chunker: const GenerationChunker(),
        now: () => DateTime.utc(2026),
        jobIdFactory: () => 'job-1',
      );

      caller.onGenerate = (GenerationRequest request, int call) async {
        expect(request.materialsText, isEmpty);
        expect(request.images, hasLength(1));
        expect(request.images.single.fileName, 'схема.png');
        return resultWith(<GeneratedCard>[makeGeneratedCard()]);
      };

      final result = await pipeline.run(
        requestWith(
          const <ParsedDocument>[],
          images: <GenerationAttachment>[image],
        ),
      );

      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, hasLength(1));
      expect(jobs.saved.first.files, <String>['схема.png']);
    },
  );

  test('повтор упавшего image-фрагмента передаёт вложение', () async {
    final GenerationAttachment image = GenerationAttachment(
      fileName: 'скан.pdf',
      mediaType: AttachmentMediaType.pdf,
      bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]),
    );
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    final GenerationRunResult previous = GenerationRunResult(
      jobId: 'job-1',
      status: GenerationJobStatus.error,
      cards: const <GeneratedCard>[],
      failures: <GenerationChunkFailure>[
        GenerationChunkFailure(
          chunkIndex: 1,
          code: GenerationErrorCode.serverUnavailable,
          materialsText: '',
          limit: 20,
          images: <GenerationAttachment>[image],
        ),
      ],
      tokensUsed: 0,
      estimatedTokens: 10,
      duplicatesRemoved: 0,
      chunkCount: 1,
      cancelled: false,
    );

    caller.onGenerate = (GenerationRequest request, int call) async {
      expect(request.images.single, same(image));
      return resultWith(<GeneratedCard>[makeGeneratedCard()]);
    };

    final pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      chunker: const GenerationChunker(),
      now: () => DateTime.utc(2026),
      jobIdFactory: () => 'job-1',
    );
    final result = await pipeline.retryFailed(
      requestWith(
        const <ParsedDocument>[],
        images: <GenerationAttachment>[image],
      ),
      previous,
    );

    expect(result.cards, hasLength(1));
    expect(caller.calls, 1);
  });
}
