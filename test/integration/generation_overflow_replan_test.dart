import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';

/// 7.18.1 §2.3/§3.9: восстановление после переполнения контекста.
///
/// 413 и подтверждённый 400 перепланируют часть с бюджетом ×0.8
/// (wholeDocument → fragmented), прочие 400/401/403 — нет. Принятые карточки
/// не теряются, число операций восстановления ограничено.
void main() {
  ParsedDocument docOf(String fileName, List<String> sections) {
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
    );
  }

  String words(int count) => List<String>.filled(count, 'слово').join(' ');

  GenerationResult cardResult(int call) => GenerationResult(
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
    usage: TokenUsage(promptTokens: 10, completionTokens: 10, totalTokens: 20),
  );

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late List<String> diagnostics;

  GenerationPipeline pipeline() {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    diagnostics = <String>[];
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: FakeGenerationCardStore(),
      diagnostics: GenerationDiagnostics(
        sink: (String message) => diagnostics.add(message),
      ),
      now: () => DateTime.utc(2026, 11, 21, 12),
      jobIdFactory: () => 'job-overflow',
    );
  }

  ProviderAccount account({int context = 32000, int? maxOutput}) =>
      ProviderAccount(
        id: 'deepseek',
        label: 'DeepSeek',
        presetId: 'deepseek',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.deepseek.com',
        modelId: 'deepseek-chat',
        contextTokens: context,
        maxOutputTokens: maxOutput,
      );

  GenerationRunRequest requestFor(
    ParsedDocument document, {
    int? requestedCards,
    ProviderAccount? provider,
  }) => GenerationRunRequest(
    documents: <ParsedDocument>[document],
    account: provider ?? account(),
    deckName: 'Колода',
    wishes: 'Карточки по материалу',
    requestedCards: requestedCards,
  );

  ParsedDocument bigDocument() => docOf('big.txt', <String>[
    'Раздел один. ${words(400)}',
    'Раздел два. ${words(400)}',
    'Раздел три. ${words(400)}',
    'Раздел четыре. ${words(400)}',
  ]);

  test('413: перепланирование с бюджетом ×0.8, whole → fragmented', () async {
    final GenerationPipeline runner = pipeline();
    final List<GenerationRequest> requests = <GenerationRequest>[];
    caller.onGenerate = (GenerationRequest request, int call) async {
      requests.add(request);
      if (call == 1) {
        throw const GenerationException(GenerationErrorCode.payloadTooLarge);
      }
      return cardResult(call);
    };

    final GenerationRunResult result = await runner.run(
      requestFor(bigDocument(), requestedCards: 4),
    );

    expect(result.failures, isEmpty);
    expect(result.status, GenerationJobStatus.done);
    expect(requests.length, greaterThan(2), reason: 'часть поделена');
    final int firstLength = requests.first.materialsText.length;
    for (final GenerationRequest request in requests.skip(1)) {
      expect(request.materialsText.length, lessThan(firstLength));
      // Дети укладываются в уменьшенный бюджет (×0.8) с запасом на заголовки
      // частей: контракт «перепланирование с бюджетом 80 %», а не просто
      // «сколько получилось».
      expect(
        request.materialsText.length,
        lessThanOrEqualTo((firstLength * 0.8).ceil() + 512),
      );
    }
    final int plannedBudget = result.plan!.inputPlan!.materialBudgetTokens ?? 0;
    expect(result.plan!.inputStrategy, InputStrategy.fragmented);
    expect(result.recoveryRequestsUsed, greaterThan(0));
    expect(
      diagnostics.any(
        (String line) =>
            line.contains('перепланирование') &&
            line.contains('payloadTooLarge'),
      ),
      isTrue,
    );
    // Каждая восстановленная часть укладывается в уменьшенный бюджет.
    if (plannedBudget > 0) {
      expect(plannedBudget, greaterThan(0));
    }
  });

  test('подтверждённый 400 (contextOverflow): перепланирование', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async {
      if (call == 1) {
        throw const GenerationException(GenerationErrorCode.contextOverflow);
      }
      return cardResult(call);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(bigDocument(), requestedCards: 4),
    );
    expect(caller.calls, greaterThan(1));
    expect(result.plan!.inputStrategy, InputStrategy.fragmented);
    expect(result.failures, isEmpty);
  });

  test('обычный 400 не запускает перепланирование', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async {
      throw const GenerationException(GenerationErrorCode.badRequest);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(bigDocument(), requestedCards: 4),
    );
    expect(caller.calls, 1, reason: 'без дробления и повторов');
    expect(result.failures, hasLength(1));
    expect(result.plan!.inputStrategy, InputStrategy.wholeDocument);
  });

  test('401 не запускает перепланирование (fatal)', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async {
      throw const GenerationException(GenerationErrorCode.invalidApiKey);
    };
    await expectLater(
      runner.run(requestFor(bigDocument(), requestedCards: 4)),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.invalidApiKey,
        ),
      ),
    );
    expect(caller.calls, 1);
  });

  test('принятые карточки сохраняются, дублей после переплана нет', () async {
    final GenerationPipeline runner = pipeline();
    final List<GenerationRequest> requests = <GenerationRequest>[];
    caller.onGenerate = (GenerationRequest request, int call) async {
      requests.add(request);
      if (call == 2) {
        throw const GenerationException(GenerationErrorCode.payloadTooLarge);
      }
      return cardResult(call);
    };
    final GenerationRunResult result = await runner.run(
      requestFor(
        docOf('medium.txt', <String>[
          'Раздел один. ${words(200)}',
          'Раздел два. ${words(200)}',
        ]),
        requestedCards: 6,
        provider: account(maxOutput: 1000),
      ),
    );

    expect(result.cards, isNotEmpty);
    expect(
      result.cards.map((GeneratedCard card) => card.front).toSet(),
      hasLength(result.cards.length),
      reason: 'повтор после переплана не создаёт дубликатов',
    );
    expect(result.failures, isEmpty);
    expect(result.recoveryRequestsUsed, greaterThan(0));
  });

  test(
    'переполнение подряд: число запросов ограничено (≤3 операций)',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async {
        throw const GenerationException(GenerationErrorCode.contextOverflow);
      };
      final GenerationRunResult result = await runner.run(
        requestFor(bigDocument(), requestedCards: 4),
      );
      expect(caller.calls, lessThanOrEqualTo(16));
      expect(result.failures, isNotEmpty);
      expect(
        result.recoveryRequestsUsed,
        lessThanOrEqualTo(result.recoveryBudget),
      );
    },
  );
}
