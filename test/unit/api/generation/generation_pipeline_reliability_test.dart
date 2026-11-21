import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';
import '../../../helpers/generation_plan_fakes.dart';

/// TASK 03: надёжность пайплайна — prompt-only обвязка, продолжение,
/// калибровка, бюджет восстановления, Retry-After, точные image-части.
void main() {
  ParsedDocument docOf(
    String fileName,
    List<String> sections, {
    List<DocumentImage> images = const <DocumentImage>[],
  }) {
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> parsed = <ParsedSection>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      buffer.write(sections[index]);
      parsed.add(ParsedSection(start: start, end: buffer.length));
    }
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: fileName,
      text: buffer.toString(),
      sections: parsed,
      images: images,
    );
  }

  GenerationChunk chunkOf(
    int index,
    String text, {
    int limit = 10,
    List<String> unitIds = const <String>[],
  }) {
    return GenerationChunk(
      index: index,
      materialsText: text,
      sourceFiles: const <String>['a.txt'],
      limit: limit,
      unitIds: unitIds,
    );
  }

  GenerationResult resultWithCards(
    int call, {
    int cards = 1,
    int? promptTokens,
    int? completionTokens,
    int? estimatedInput,
    int? estimatedOutput,
  }) {
    return GenerationResult(
      provider: GenerationProvider.openai,
      model: 'test',
      promptVersion: 'test',
      cards: <GeneratedCard>[
        for (var index = 0; index < cards; index++)
          makeGeneratedCard(
            front: 'Вопрос $call-$index',
            back: 'Ответ $call-$index',
          ),
      ],
      usage: TokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        totalTokens: promptTokens == null || completionTokens == null
            ? null
            : promptTokens + completionTokens,
      ),
      estimatedInputTokens: estimatedInput,
      estimatedOutputTokens: estimatedOutput,
      estimatorVersion: estimatedInput == null ? null : 'test-request',
    );
  }

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late FakeGenerationCardStore store;

  GenerationPipeline pipeline({
    List<GenerationChunk>? chunks,
    int? requestedCards,
    int maxRecoveryRequests = 12,
  }) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      planFactory: chunks == null
          ? null
          : fixedPlanFactory(chunks, requestedCards: requestedCards),
      maxRecoveryRequests: maxRecoveryRequests,
      now: () => DateTime.utc(2026, 11, 19),
      jobIdFactory: () => 'job-reliability',
    );
  }

  GenerationRunRequest requestFor({
    List<ParsedDocument> documents = const <ParsedDocument>[],
    List<GenerationAttachment> images = const <GenerationAttachment>[],
    List<DocumentImage> documentImages = const <DocumentImage>[],
    String? wishes,
    int? requestedCards,
    ProviderAccount? account,
  }) {
    return GenerationRunRequest(
      documents: documents,
      images: images,
      documentImages: documentImages,
      account:
          account ??
          testProviderAccount(presetId: 'deepseek', modelId: 'deepseek-chat'),
      deckName: 'Колода',
      wishes: wishes,
      requestedCards: requestedCards,
    );
  }

  group('prompt-only: production-план и продолжение', () {
    test('production-план считает системный промпт/схему/обёртку', () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (request, call) async =>
          resultWithCards(call, cards: request.limit);
      final GenerationRunResult result = await runner.run(
        requestFor(
          wishes: 'Создай 50 карточек по фотосинтезу',
          requestedCards: 50,
        ),
      );
      final GenerationPlan plan = result.plan!;
      expect(plan.isPromptOnly, isTrue);
      expect(
        plan.budget.systemPromptTokens,
        greaterThan(1000),
        reason: 'gen-ru-v7 не должен считаться нулевым (TASK 03, D1)',
      );
      expect(plan.estimate.fixedPromptTokens, greaterThan(0));
      expect(plan.estimate.wrapperTokens, greaterThan(0));
      expect(plan.estimate.schemaTokens, greaterThan(0));
      expect(plan.chunks.length, greaterThan(1));
    });

    test(
      'со второго запроса передаётся компактная сводка, пожелания целы',
      () async {
        final GenerationPipeline runner = pipeline();
        caller.onGenerate = (request, call) async =>
            resultWithCards(call, cards: request.limit);
        final String wishes = 'Создай 200 карточек по теме фотосинтез';
        final GenerationRunResult result = await runner.run(
          requestFor(wishes: wishes, requestedCards: 200),
        );
        expect(caller.calls, greaterThan(2));
        expect(caller.requests.first.alreadyCreated, isNull);
        for (final GenerationRequest request in caller.requests) {
          expect(
            request.wishes,
            wishes,
            reason: 'исходные требования пользователя не меняются',
          );
        }
        final String second = caller.requests[1].alreadyCreated!;
        expect(second, contains('Уже созданные карточки'));
        expect(second, contains('Вопрос 1-0'));
        expect(second.length, lessThan(8000), reason: 'сводка ограничена');
        // Сводка не содержит инструкций, меняющих заказ.
        expect(second, isNot(contains('Создай 200')));
        final String last = caller.requests.last.alreadyCreated ?? '';
        expect(last, contains('Вопрос'));
        expect(result.cards, hasLength(200));
      },
    );

    test(
      'частичный сбой: повтор несёт сводку уже полученных карточек',
      () async {
        final GenerationPipeline runner = pipeline();
        caller.onGenerate = (request, call) async {
          if (call == 2) {
            throw const GenerationException(GenerationErrorCode.network);
          }
          return resultWithCards(
            call,
            cards: 2 < request.limit ? 2 : request.limit,
          );
        };
        final GenerationRunRequest request = requestFor(
          wishes: 'Создай 20 карточек по фотосинтезу',
          requestedCards: 20,
        );
        final GenerationRunResult first = await runner.run(request);
        expect(first.status, GenerationJobStatus.partial);
        expect(first.failures, hasLength(1));

        final FakeGenerationCaller retryCaller = FakeGenerationCaller();
        retryCaller.onGenerate = (request, call) async =>
            resultWithCards(call + 100, cards: 2);
        final GenerationPipeline retryPipeline = GenerationPipeline(
          caller: retryCaller,
          jobRepository: jobs,
          cardStore: store,
          now: () => DateTime.utc(2026, 11, 19),
          jobIdFactory: () => 'job-retry',
        );
        final GenerationRunResult second = await retryPipeline.retryFailed(
          request,
          first,
        );
        expect(retryCaller.calls, 1);
        final String? continuation = retryCaller.requests.single.alreadyCreated;
        expect(continuation, isNotNull);
        expect(
          continuation,
          contains('Вопрос 1-0'),
          reason: 'повтор видит успешные карточки первого запуска',
        );
        expect(
          second.cards.toSet().length,
          second.cards.length,
          reason: 'дублей нет',
        );
      },
    );
  });

  group('калибровка токенов', () {
    test(
      'сравнивает оценку запроса и usage, сохраняет версию оценщика',
      () async {
        final GenerationPipeline runner = pipeline(
          chunks: <GenerationChunk>[chunkOf(1, 'Материал для карточек.')],
        );
        caller.onGenerate = (request, call) async => resultWithCards(
          call,
          promptTokens: 80,
          completionTokens: 40,
          estimatedInput: 100,
          estimatedOutput: 1040,
        );
        final GenerationRunResult result = await runner.run(
          requestFor(
            documents: <ParsedDocument>[
              docOf('a.txt', <String>['материал']),
            ],
          ),
        );
        expect(result.calibration.samples, hasLength(1));
        expect(result.calibration.failedRequests, 0);
        expect(result.calibration.inputSamples, 1);
        expect(result.calibration.outputSamples, 1);
        expect(result.calibration.meanInputRatio, closeTo(0.8, 0.0001));
        expect(result.calibration.samplesWithoutUsage, 0);
        expect(
          result.calibration.samples.single.estimatorVersion,
          'test-request',
        );
      },
    );

    test('провайдер без usage: отсутствие данных фиксируется, не 0', () async {
      final GenerationPipeline runner = pipeline(
        chunks: <GenerationChunk>[chunkOf(1, 'Материал.')],
      );
      caller.onGenerate = (request, call) async => resultWithCards(call);
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['материал']),
          ],
        ),
      );
      expect(result.calibration.samples, hasLength(1));
      expect(result.calibration.samplesWithoutUsage, 1);
      expect(result.calibration.inputSamples, 0);
      expect(result.calibration.meanInputRatio, isNull);
    });

    test('упавшие запросы учитываются отдельно (usage нет)', () async {
      final GenerationPipeline runner = pipeline(
        chunks: <GenerationChunk>[
          chunkOf(1, 'Первый материал.'),
          chunkOf(2, 'Второй материал.'),
        ],
      );
      caller.onGenerate = (request, call) async {
        if (call == 2) {
          throw const GenerationException(
            GenerationErrorCode.serverUnavailable,
          );
        }
        return resultWithCards(
          call,
          promptTokens: 50,
          completionTokens: 10,
          estimatedInput: 100,
          estimatedOutput: 1024,
        );
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['материал']),
          ],
        ),
      );
      expect(result.calibration.failedRequests, 1);
      expect(result.calibration.samples, hasLength(1));
      expect(result.calibration.samplesWithoutUsage, 0);
    });
  });

  group('восстановление и бюджет', () {
    test('maxRecoveryRequests=0 отключает дробление явно', () async {
      final GenerationPipeline runner = pipeline(
        chunks: <GenerationChunk>[
          chunkOf(
            1,
            'Первая часть материала с достаточным объёмом текста.\n\n'
            'Вторая часть материала с достаточным объёмом текста.',
            limit: 4,
            unitIds: <String>['doc:a.txt#0#0', 'doc:a.txt#0#1'],
          ),
        ],
        maxRecoveryRequests: 0,
      );
      caller.onGenerate = (request, call) async {
        throw const GenerationException(GenerationErrorCode.contextOverflow);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['раз два']),
          ],
        ),
      );
      expect(caller.calls, 1);
      expect(result.recoveryBudget, 0);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.code, GenerationErrorCode.contextOverflow);
      expect(result.failures.single.retryable, isFalse);
    });

    test(
      'исчерпанный бюджет останавливает дробление, успешное сохраняется',
      () async {
        final GenerationPipeline runner = pipeline(
          chunks: <GenerationChunk>[
            chunkOf(
              1,
              'Первая часть материала с достаточным объёмом текста.\n\n'
              'Вторая часть материала с достаточным объёмом текста.',
              limit: 4,
              unitIds: <String>['doc:a.txt#0#0', 'doc:a.txt#0#1'],
            ),
            chunkOf(2, 'Второй целый материал.'),
          ],
          maxRecoveryRequests: 1,
        );
        caller.onGenerate = (request, call) async {
          if (call == 1) {
            throw const GenerationException(
              GenerationErrorCode.contextOverflow,
            );
          }
          if (call == 2) {
            throw const GenerationException(
              GenerationErrorCode.contextOverflow,
            );
          }
          return resultWithCards(call);
        };
        final GenerationRunResult result = await runner.run(
          requestFor(
            documents: <ParsedDocument>[
              docOf('a.txt', <String>['раз два']),
            ],
          ),
        );
        expect(caller.calls, greaterThanOrEqualTo(3));
        expect(result.recoveryRequestsUsed, 1);
        expect(result.recoveryBudget, 1);
        expect(result.recoveryBudgetExhausted, isTrue);
        expect(result.failures, isNotEmpty);
      },
    );

    test('HTTP 413 дробит только проблемный фрагмент', () async {
      final GenerationPipeline runner = pipeline(
        chunks: <GenerationChunk>[
          chunkOf(
            1,
            'Первая часть материала с достаточным объёмом текста.\n\n'
            'Вторая часть материала с достаточным объёмом текста.',
            limit: 4,
            unitIds: <String>['doc:a.txt#0#0', 'doc:a.txt#0#1'],
          ),
        ],
      );
      caller.onGenerate = (request, call) async {
        if (call == 1) {
          throw const GenerationException(GenerationErrorCode.payloadTooLarge);
        }
        return resultWithCards(call);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['раз два']),
          ],
        ),
      );
      expect(caller.calls, 3);
      expect(
        caller.requests[1].materialsText + caller.requests[2].materialsText,
        caller.requests[0].materialsText,
      );
      expect(result.failures, isEmpty);
      expect(result.cards, hasLength(2));
    });

    test('Retry-After сохраняется в сбое фрагмента для UI', () async {
      final GenerationPipeline runner = pipeline(
        chunks: <GenerationChunk>[chunkOf(1, 'Материал.')],
      );
      caller.onGenerate = (request, call) async {
        throw const GenerationException(
          GenerationErrorCode.rateLimited,
          retryAfter: Duration(seconds: 30),
        );
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['материал']),
          ],
        ),
      );
      expect(result.failures.single.retryAfter, const Duration(seconds: 30));
      expect(caller.calls, 1, reason: '429 не дробит материалы');
    });

    test('восстановление не теряет уже полученные карточки', () async {
      final GenerationPipeline runner = pipeline(
        chunks: <GenerationChunk>[
          chunkOf(1, 'Первый целый материал.'),
          chunkOf(
            2,
            'Первая часть материала с достаточным объёмом текста.\n\n'
            'Вторая часть материала с достаточным объёмом текста.',
            limit: 4,
            unitIds: <String>['doc:a.txt#0#0', 'doc:a.txt#0#1'],
          ),
        ],
      );
      caller.onGenerate = (request, call) async {
        if (call == 2) {
          throw const GenerationException(GenerationErrorCode.contextOverflow);
        }
        return resultWithCards(call);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['раз два']),
          ],
        ),
      );
      expect(result.failures, isEmpty);
      expect(result.cards, hasLength(3));
      expect(result.status, GenerationJobStatus.done);
    });
  });

  group('изображения: точные части из плана', () {
    DocumentImage imageOf(int index) {
      return DocumentImage(
        fileName: 'a.txt',
        bytes: Uint8List.fromList(
          List<int>.generate(4096, (i) => (index * 37 + i) % 251),
        ),
        mediaType: AttachmentMediaType.png,
        width: 800,
        height: 600,
        sectionIndex: 0,
        caption: 'Рис. $index',
      );
    }

    test('vision: запрос получает ровно imageParts плана, каталог полный', () async {
      final GenerationPipeline runner = pipeline();
      final List<GenerationRequest> requests = <GenerationRequest>[];
      caller.onGenerate = (request, call) async {
        requests.add(request);
        return resultWithCards(call);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf(
              'a.txt',
              <String>['Текст с рисунками.'],
              images: <DocumentImage>[imageOf(0), imageOf(1)],
            ),
          ],
          wishes: '3 карточки',
          account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
        ),
      );
      expect(
        result.plan!.chunks
            .map((PlannedChunk chunk) => chunk.kind.name)
            .toList(),
        isNotEmpty,
      );
      final GenerationRequest withParts = requests.firstWhere(
        (GenerationRequest request) =>
            request.documentImageParts != null &&
            request.documentImageParts!.isNotEmpty,
        orElse: () => requests.first,
      );
      expect(
        result.plan!.imagesSentToModel,
        2,
        reason:
            'chunks: '
            '${result.plan!.chunks.map((PlannedChunk chunk) => '${chunk.kind.name}:${chunk.imageParts.length}/${chunk.catalogOnly.length}').join(', ')}',
      );
      expect(withParts.documentImageParts, hasLength(2));
      expect(withParts.documentImages, hasLength(2));
      expect(
        withParts.documentImageParts!.map((DocumentImage image) => image.id),
        withParts.documentImages.take(2).map((DocumentImage image) => image.id),
      );
      expect(result.plan!.imagesSentToModel, 2);
    });

    test('без Vision: части пусты, изображения остаются в каталоге', () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (request, call) async {
        expect(request.documentImageParts, isEmpty);
        expect(request.documentImages, hasLength(2));
        return resultWithCards(call);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf(
              'a.txt',
              <String>['Текст с рисунками.'],
              images: <DocumentImage>[imageOf(0), imageOf(1)],
            ),
          ],
          wishes: '3 карточки',
          // Подтверждённое отсутствие Vision — пользовательская настройка:
          // изображения остаются только каталогом.
          account: testProviderAccount(
            presetId: 'deepseek',
            modelId: 'deepseek-chat',
          ).copyWith(supportsVision: false, visionConfigured: true),
        ),
      );
      expect(result.plan!.imagesUnsupported, 2);
      expect(result.plan!.imagesSentToModel, 0);
      for (final PlannedChunk chunk in result.plan!.chunks) {
        expect(chunk.imageParts, isEmpty);
        expect(chunk.catalogOnly, hasLength(2));
      }
    });
  });
}
