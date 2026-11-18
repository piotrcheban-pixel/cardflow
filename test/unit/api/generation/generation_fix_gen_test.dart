import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';
import '../../../helpers/generation_plan_fakes.dart';

/// Поведение пайплайна, добавленное в итерации fix-gen:
/// изображения из документов (Д3), лимит карточек из пожеланий (A8.1),
/// сквозные коды причин сбоя фрагментов (Д6).
void main() {
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

  GenerationResult resultWith(List<GeneratedCard> cards, {int rejected = 0}) {
    return GenerationResult(
      provider: GenerationProvider.openai,
      model: 'gpt-4o',
      promptVersion: systemPromptVersion,
      cards: cards,
      usage: const TokenUsage(promptTokens: 10, completionTokens: 20),
      rejectedCards: rejected,
    );
  }

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late List<String> diagnostics;

  GenerationPipeline pipelineWith(
    List<GenerationChunk> chunks, {
    FakeCardImageFinder? imageFinder,
  }) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    diagnostics = <String>[];
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: FakeGenerationCardStore(),
      planFactory: fixedPlanFactory(chunks),
      imageFinder: imageFinder,
      diagnostics: GenerationDiagnostics(enabled: true, sink: diagnostics.add),
      now: () => DateTime.utc(2026, 11, 15, 10),
      jobIdFactory: () => 'job-fix-gen',
    );
  }

  GenerationRunRequest requestFor(
    List<ParsedDocument> documents, {
    String? wishes,
  }) {
    return GenerationRunRequest(
      documents: documents,
      account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
      deckName: 'Новая колода',
      wishes: wishes,
    );
  }

  DocumentImage documentImage({List<int>? bytes}) {
    return DocumentImage(
      fileName: 'статика.docx',
      bytes: Uint8List.fromList(bytes ?? <int>[0x89, 0x50, 0x4E, 0x47, 1, 2]),
      mediaType: AttachmentMediaType.png,
      caption: 'Рис. 1. Схема',
      context: 'Две силы уравновешены',
      sectionIndex: 0,
    );
  }

  group('изображения из документов (Д3)', () {
    test(
      'image_id из <images> → карточка получает байты файла, без поиска',
      () async {
        final DocumentImage image = documentImage();
        final finder = FakeCardImageFinder();
        final pipeline = pipelineWith(<GenerationChunk>[
          GenerationChunk(
            index: 1,
            materialsText: 'Файл: статика.docx\nДве силы уравновешены',
            sourceFiles: const <String>['статика.docx'],
            limit: 10,
            documentImages: <DocumentImage>[image],
          ),
        ], imageFinder: finder);
        caller.onGenerate = (GenerationRequest request, int call) async {
          expect(request.documentImages, hasLength(1));
          expect(request.documentImages.single.id, 'img1');
          return resultWith(<GeneratedCard>[
            const GeneratedCard(
              front: 'При каком условии две силы уравновешены?',
              back: 'Когда равны и противоположны.',
              cardType: CardType.basic,
              imageId: 'img1',
            ),
          ]);
        };

        final GenerationRunResult result = await pipeline.run(
          requestFor(<ParsedDocument>[
            docOf('статика.docx', <String>['Две силы']),
          ]),
        );

        expect(finder.queries, isEmpty, reason: 'внешний поиск не нужен');
        expect(result.cards.single.image, isNotNull);
        expect(result.cards.single.image!.bytes, image.bytes);
        expect(result.cards.single.imageId, 'img1');
      },
    );

    test('неизвестный image_id → карточка без картинки, без падения', () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        GenerationChunk(
          index: 1,
          materialsText: 'Файл: статика.docx\nтекст',
          sourceFiles: const <String>['статика.docx'],
          limit: 10,
          documentImages: <DocumentImage>[documentImage()],
        ),
      ], imageFinder: FakeCardImageFinder());
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultWith(<GeneratedCard>[
            const GeneratedCard(
              front: 'Вопрос?',
              back: 'Ответ.',
              cardType: CardType.basic,
              imageId: 'img9',
            ),
          ]);

      final GenerationRunResult result = await pipeline.run(
        requestFor(<ParsedDocument>[
          docOf('статика.docx', <String>['текст']),
        ]),
      );

      expect(result.cards.single.image, isNull);
      expect(result.status, GenerationJobStatus.done);
    });
  });

  group('лимиты карточек из плана (D.7)', () {
    test(
      'лимиты плана исполняются как есть, без повторного распределения',
      () async {
        final chunks = <GenerationChunk>[
          GenerationChunk(
            index: 1,
            materialsText: 'а' * 400,
            sourceFiles: const <String>['a.txt'],
            limit: 13,
          ),
          GenerationChunk(
            index: 2,
            materialsText: 'б' * 100,
            sourceFiles: const <String>['b.txt'],
            limit: 7,
          ),
        ];
        final pipeline = pipelineWith(chunks);
        final List<int> limits = <int>[];
        caller.onGenerate = (GenerationRequest request, int call) async {
          limits.add(request.limit);
          return resultWith(const <GeneratedCard>[]);
        };

        await pipeline.run(
          requestFor(<ParsedDocument>[
            docOf('a.txt', <String>['а' * 400]),
            docOf('b.txt', <String>['б' * 100]),
          ], wishes: 'Статика: аксиомы и фермы. 20 карточек'),
        );

        expect(limits, <int>[13, 7]);
      },
    );

    test(
      'фрагменты с лимитом 1 не пропускаются — контент не теряется',
      () async {
        final pipeline = pipelineWith(<GenerationChunk>[
          GenerationChunk(
            index: 1,
            materialsText: 'а' * 400,
            sourceFiles: const <String>['a.txt'],
            limit: 1,
          ),
          GenerationChunk(
            index: 2,
            materialsText: 'б' * 200,
            sourceFiles: const <String>['b.txt'],
            limit: 1,
          ),
          GenerationChunk(
            index: 3,
            materialsText: 'в' * 100,
            sourceFiles: const <String>['c.txt'],
            limit: 1,
          ),
        ]);
        final List<int> limits = <int>[];
        caller.onGenerate = (GenerationRequest request, int call) async {
          limits.add(request.limit);
          return resultWith(const <GeneratedCard>[]);
        };

        await pipeline.run(
          requestFor(<ParsedDocument>[
            docOf('a.txt', <String>['а' * 400]),
            docOf('b.txt', <String>['б' * 200]),
            docOf('c.txt', <String>['в' * 100]),
          ], wishes: 'Всего 1 карточка'),
        );

        expect(limits, <int>[
          1,
          1,
          1,
        ], reason: 'L-26: фрагмент не пропускается');
      },
    );

    test('без числа карточек лимит фрагмента не меняется', () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        GenerationChunk(
          index: 1,
          materialsText: 'текст',
          sourceFiles: const <String>['a.txt'],
          limit: 7,
        ),
      ]);
      final List<int> limits = <int>[];
      caller.onGenerate = (GenerationRequest request, int call) async {
        limits.add(request.limit);
        return resultWith(const <GeneratedCard>[]);
      };

      await pipeline.run(
        requestFor(<ParsedDocument>[
          docOf('a.txt', <String>['текст']),
        ], wishes: 'Акцент на аксиомах'),
      );

      expect(limits, <int>[7]);
    });
  });

  group('коды причин сбоя фрагментов (Д6)', () {
    test('ошибки фрагментов дают перечень причин в generation_jobs', () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        GenerationChunk(
          index: 1,
          materialsText: 'первый',
          sourceFiles: const <String>['a.txt'],
          limit: 5,
        ),
        GenerationChunk(
          index: 2,
          materialsText: 'второй',
          sourceFiles: const <String>['b.txt'],
          limit: 5,
        ),
        GenerationChunk(
          index: 3,
          materialsText: 'третий',
          sourceFiles: const <String>['c.txt'],
          limit: 5,
        ),
      ]);
      caller.onGenerate = (GenerationRequest request, int call) async {
        if (call == 1) {
          return resultWith(<GeneratedCard>[
            const GeneratedCard(
              front: 'Вопрос?',
              back: 'Ответ.',
              cardType: CardType.basic,
            ),
          ]);
        }
        if (call == 2) {
          throw const GenerationException(
            GenerationErrorCode.invalidResponse,
            failureReason: GenerationFailureReason.jsonParse,
          );
        }
        throw const GenerationException(
          GenerationErrorCode.serverUnavailable,
          failureReason: GenerationFailureReason.httpServerError,
        );
      };

      final GenerationRunResult result = await pipeline.run(
        requestFor(<ParsedDocument>[
          docOf('a.txt', <String>['первый']),
          docOf('b.txt', <String>['второй']),
          docOf('c.txt', <String>['третий']),
        ]),
      );

      expect(result.status, GenerationJobStatus.partial);
      expect(result.cards, hasLength(1));
      expect(result.failures, hasLength(2));
      expect(
        result.failures.map((GenerationChunkFailure failure) => failure.reason),
        <GenerationFailureReason>[
          GenerationFailureReason.jsonParse,
          GenerationFailureReason.httpServerError,
        ],
      );
      expect(jobs.saved.last.errorCode, 'json_parse,http_5xx');
      expect(
        diagnostics.where((String line) => line.contains('reason=json_parse')),
        hasLength(1),
        reason: 'причина пишется в отладочный лог',
      );
    });

    test('испорченные схемой карточки считаются в rejectedCards', () async {
      final pipeline = pipelineWith(<GenerationChunk>[
        GenerationChunk(
          index: 1,
          materialsText: 'текст',
          sourceFiles: const <String>['a.txt'],
          limit: 5,
        ),
      ]);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultWith(<GeneratedCard>[
            const GeneratedCard(
              front: 'Вопрос?',
              back: 'Ответ.',
              cardType: CardType.basic,
            ),
          ], rejected: 2);

      final GenerationRunResult result = await pipeline.run(
        requestFor(<ParsedDocument>[
          docOf('a.txt', <String>['текст']),
        ]),
      );

      expect(result.rejectedCards, 2);
      expect(result.cards, hasLength(1));
      expect(result.status, GenerationJobStatus.done);
    });
  });
}
