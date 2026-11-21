import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
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

import '../helpers/generation_fakes.dart';

/// TASK 02B-FINAL: production-путь `GenerationRunRequest → GenerationPlan →
/// запросы → карточки` на mock-вызове модели (без реальных платных запросов).
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

  String words(int count) => List<String>.filled(count, 'слово').join(' ');

  GenerationResult resultWithCard(int call, {int tokens = 10}) {
    return GenerationResult(
      provider: GenerationProvider.openai,
      model: 'test',
      promptVersion: 'test',
      cards: <GeneratedCard>[
        GeneratedCard(
          front: 'Вопрос $call',
          back: 'Ответ $call',
          cardType: CardType.basic,
        ),
      ],
      usage: TokenUsage(
        promptTokens: tokens,
        completionTokens: tokens,
        totalTokens: tokens * 2,
      ),
    );
  }

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late FakeGenerationCardStore store;

  GenerationPipeline pipeline() {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      now: () => DateTime.utc(2026, 11, 19, 10),
      jobIdFactory: () => 'job-adaptive',
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

  test('небольшой запрос: 5 карточек из одного документа — ровно 5', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async {
      expect(request.limit, 5);
      return resultWithCard(call);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>[
            // Ёмкость разделов (ADR-040 §5) должна позволять 5 карточек:
            // ~250 значимых слов и определения дают capacity ≥ 5 на раздел.
            for (var index = 0; index < 5; index++)
              'Понятие $index — это определение. ${words(250)}',
          ]),
        ],
        wishes: 'Сделай 5 карточек',
      ),
    );
    expect(result.status, GenerationJobStatus.done);
    expect(result.plan, isNotNull);
    expect(result.plan!.chunks, hasLength(1));
    expect(result.plan!.requestedCards, 5);
    expect(result.plan!.plannedCards, 5);
    expect(result.cards, hasLength(1));
  });

  test('большой запрос: план до запросов, заказ достигнут без среза', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard(call);
    final GenerationRunResult result = await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          for (var doc = 0; doc < 3; doc++)
            docOf('d$doc.txt', <String>[
              for (var section = 0; section < 8; section++)
                'Раздел $section. ${words(1500)}',
            ]),
        ],
        wishes: 'Нужно 150 карточек',
      ),
    );
    final GenerationPlan plan = result.plan!;
    expect(plan.chunks.length, greaterThan(1));
    expect(plan.requestedCards, 150);
    expect(
      plan.plannedCards,
      150,
      reason:
          'материала хватает: план обязан использовать его (TASK 03, D20), '
          'а не занижать achievableCards',
    );
    expect(
      plan.validity.warnings,
      isNot(contains(PlanWarningCode.requestedAbovePlan)),
    );
    expect(caller.calls, plan.chunks.length);
    expect(
      caller.requests.fold<int>(
        0,
        (int sum, GenerationRequest request) => sum + request.limit,
      ),
      plan.plannedCards,
    );
    expect(result.cards, hasLength(caller.calls));
  });

  test('мало материала: заказ недостижим — предупреждение, не срез', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard(call);
    final GenerationRunResult result = await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          docOf('small.txt', <String>['Короткий материал.']),
        ],
        wishes: 'Нужно 150 карточек',
      ),
    );
    final GenerationPlan plan = result.plan!;
    expect(plan.requestedCards, 150);
    expect(plan.plannedCards, lessThan(150));
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.requestedAbovePlan),
    );
    expect(caller.calls, plan.chunks.length);
  });

  test('несколько документов: порядок и заголовки файлов сохранены', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard(call);
    await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          docOf('first.txt', <String>['Первый документ.']),
          docOf('second.txt', <String>['Второй документ.']),
        ],
        wishes: '10 карточек',
      ),
    );
    expect(caller.calls, 1);
    final String materials = caller.requests.single.materialsText;
    expect(materials.indexOf('Файл: first.txt'), greaterThanOrEqualTo(0));
    expect(
      materials.indexOf('Файл: first.txt'),
      lessThan(materials.indexOf('Файл: second.txt')),
    );
  });

  test('текст и изображения: image-части попадают в запрос', () async {
    final GenerationPipeline runner = pipeline();
    final DocumentImage image = DocumentImage(
      fileName: 'a.txt',
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
      mediaType: AttachmentMediaType.png,
      sectionIndex: 0,
      caption: 'Рис. 1',
    );
    caller.onGenerate = (GenerationRequest request, int call) async {
      expect(request.documentImages, isNotEmpty);
      expect(request.documentImages.first.id, 'img1');
      return resultWithCard(call);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          docOf(
            'a.txt',
            <String>['Текст с рисунком.'],
            images: <DocumentImage>[image],
          ),
        ],
        account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
        wishes: '3 карточки',
      ),
    );
    expect(result.status, GenerationJobStatus.done);
    expect(caller.calls, 1);
  });

  test('prompt-only 500 карточек: несколько запросов без материалов', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard(call);
    final GenerationRunResult result = await runner.run(
      requestFor(
        wishes: 'Создай 500 карточек по теме фотосинтеза',
        requestedCards: 500,
      ),
    );
    final GenerationPlan plan = result.plan!;
    expect(plan.isPromptOnly, isTrue);
    expect(plan.requestedCards, 500);
    expect(plan.plannedCards, 500);
    expect(plan.chunks.length, greaterThan(1));
    expect(caller.calls, plan.chunks.length);
    for (final GenerationRequest request in caller.requests) {
      expect(request.materialsText, isEmpty);
      expect(request.wishes, contains('фотосинтез'));
    }
    expect(
      caller.requests.fold<int>(
        0,
        (int sum, GenerationRequest request) => sum + request.limit,
      ),
      500,
    );
    expect(result.promptOnly, isTrue);
    expect(result.cards, hasLength(caller.calls));
  });

  test(
    'частичный успех: успешные фрагменты сохраняются, повтор — только сбой',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async {
        if (call == 1) {
          throw const GenerationException(GenerationErrorCode.network);
        }
        return resultWithCard(call);
      };
      final GenerationRunResult first = await runner.run(
        requestFor(
          documents: <ParsedDocument>[
            for (var doc = 0; doc < 2; doc++)
              docOf('p$doc.txt', <String>[
                for (var section = 0; section < 6; section++)
                  'Раздел $section. ${words(1800)}',
              ]),
          ],
          wishes: '40 карточек',
        ),
      );
      expect(first.failures, hasLength(1));
      expect(first.failures.single.retryable, isTrue);
      expect(first.status, GenerationJobStatus.partial);
      expect(first.cards, hasLength(first.chunkCount - 1));

      final FakeGenerationCaller retry = FakeGenerationCaller();
      retry.onGenerate = (request, call) async => resultWithCard(call + 100);
      final GenerationPipeline retryRunner = GenerationPipeline(
        caller: retry,
        jobRepository: jobs,
        cardStore: store,
        now: () => DateTime.utc(2026, 11, 19, 10),
        jobIdFactory: () => 'job-adaptive',
      );
      final GenerationRunResult second = await retryRunner.retryFailed(
        requestFor(
          documents: <ParsedDocument>[
            for (var doc = 0; doc < 2; doc++)
              docOf('p$doc.txt', <String>[
                for (var section = 0; section < 6; section++)
                  'Раздел $section. ${words(1800)}',
              ]),
          ],
          wishes: '40 карточек',
        ),
        first,
      );
      expect(retry.calls, 1, reason: 'повторяется только упавший фрагмент');
      expect(second.failures, isEmpty);
      expect(second.cards, hasLength(first.cards.length + 1));
      expect(second.status, GenerationJobStatus.done);
    },
  );

  test('rate limit: без дробления материалов, ошибка фрагмента', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (request, call) async {
      throw const GenerationException(GenerationErrorCode.rateLimited);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          docOf('a.txt', <String>['Материал.']),
        ],
        wishes: '2 карточки',
      ),
    );
    expect(caller.calls, 1);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.retryable, isTrue);
    expect(result.status, GenerationJobStatus.error);
  });

  test('авторизация: без бессмысленных повторов', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (request, call) async {
      throw const GenerationException(GenerationErrorCode.invalidApiKey);
    };
    await expectLater(
      runner.run(
        requestFor(
          documents: <ParsedDocument>[
            docOf('a.txt', <String>['Материал.']),
          ],
          wishes: '2 карточки',
        ),
      ),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.invalidApiKey,
        ),
      ),
    );
    expect(caller.calls, 1);
    expect(jobs.saved.last.status, GenerationJobStatus.error);
  });

  test('context overflow: дробится только проблемный фрагмент', () async {
    final GenerationPipeline runner = pipeline();
    final List<GenerationRequest> requests = <GenerationRequest>[];
    caller.onGenerate = (request, call) async {
      requests.add(request);
      if (call == 1) {
        throw const GenerationException(GenerationErrorCode.contextOverflow);
      }
      return resultWithCard(call);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(
        documents: <ParsedDocument>[
          docOf('big.txt', <String>[
            'Первый раздел материала.',
            'Второй раздел материала.',
          ]),
        ],
        wishes: '5 карточек',
      ),
    );
    expect(requests, hasLength(3), reason: 'overflow → две части');
    expect(
      requests[1].materialsText + requests[2].materialsText,
      requests[0].materialsText,
      reason: 'ни один символ материалов не потерян',
    );
    expect(requests[1].limit + requests[2].limit, requests[0].limit);
    expect(result.failures, isEmpty);
    expect(result.cards, hasLength(2));
    expect(result.status, GenerationJobStatus.done);
  });

  test('невалидный план (изображения без Vision) — до запросов', () async {
    final GenerationPipeline runner = pipeline();
    final GenerationAttachment image = GenerationAttachment(
      fileName: 'схема.png',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
    );
    await expectLater(
      runner.run(
        requestFor(
          images: <GenerationAttachment>[image],
          // Подтверждённое отсутствие Vision (пользовательская настройка):
          // план невыполним до запросов. Неизвестность — отдельный сценарий.
          account: testCustomProviderAccount().copyWith(
            supportsVision: false,
            visionConfigured: true,
          ),
          wishes: '2 карточки',
        ),
      ),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.visionUnsupported,
        ),
      ),
    );
    expect(caller.calls, 0);
    expect(jobs.saved.last.status, GenerationJobStatus.error);
  });
}
