import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/request_token_counter.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';

/// 7.18.1 §2.2: нативный подсчёт входа (Anthropic/Gemini) подключён к
/// конвейеру: один подсчёт на план, кэш по хэшу содержимого, деградация к
/// оценке при ошибке, тела запросов не логируются.
class _FakeTokenCounter implements RequestTokenCounter {
  _FakeTokenCounter({this.result = const ExactTokenCount.exact(1234)});

  ExactTokenCount result;

  int calls = 0;

  @override
  bool supports(ProviderAccount account) =>
      account.protocol == ProviderProtocol.anthropicMessages;

  final List<String> systemPrompts = <String>[];
  final List<String> userContents = <String>[];

  @override
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
  }) async {
    calls++;
    systemPrompts.add(systemPrompt);
    userContents.add(userContent);
    return result;
  }
}

ParsedDocument docOf(String fileName, String text) => ParsedDocument(
  format: DocumentFormat.txt,
  fileName: fileName,
  text: text,
  sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
);

GenerationResult resultWithCard() => GenerationResult(
  provider: GenerationProvider.anthropic,
  model: 'claude-test',
  promptVersion: 'gen-ru-v8',
  cards: <GeneratedCard>[makeGeneratedCard()],
  usage: const TokenUsage(
    promptTokens: 100,
    completionTokens: 20,
    totalTokens: 120,
  ),
);

void main() {
  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late _FakeTokenCounter counter;
  late List<String> diagnostics;

  ProviderAccount anthropicAccount() => ProviderAccount(
    id: 'claude',
    label: 'Claude',
    protocol: ProviderProtocol.anthropicMessages,
    baseUrl: 'https://api.anthropic.com',
    modelId: 'claude-test',
    contextTokens: 200000,
    requiresApiKey: true,
  );

  ProviderAccount openAiAccount() =>
      testProviderAccount(presetId: 'openai', modelId: 'gpt-4o');

  GenerationPipeline pipeline({
    ProviderAccount? account,
    RequestTokenCounter? tokenCounter,
  }) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    diagnostics = <String>[];
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: FakeGenerationCardStore(),
      tokenCounter: tokenCounter,
      diagnostics: GenerationDiagnostics(
        sink: (String message) => diagnostics.add(message),
      ),
      now: () => DateTime.utc(2026, 11, 21, 10),
      jobIdFactory: () => 'job-exact',
    );
  }

  GenerationRunRequest requestFor(ProviderAccount account) =>
      GenerationRunRequest(
        documents: <ParsedDocument>[
          docOf('лекция.txt', 'Фотосинтез — процесс преобразования света.'),
        ],
        account: account,
        deckName: 'Точный подсчёт',
        wishes: '3 карточки',
      );

  test('один нативный подсчёт на план: точность и источник в плане', () async {
    counter = _FakeTokenCounter();
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();

    final GenerationRunResult result = await runner.run(
      requestFor(anthropicAccount()),
    );

    expect(counter.calls, 1, reason: 'ровно один вызов на план');
    expect(result.plan, isNotNull);
    final InputPlan inputPlan = result.plan!.inputPlan!;
    expect(inputPlan.accuracy, InputAccuracy.exact);
    expect(inputPlan.inputTokenSource, contains('count_tokens'));
    // 1234 точных токенов + запас 3 % (ceil(37.02) = 38).
    expect(inputPlan.inputTokens, 1234 + 38);
    expect(counter.systemPrompts.single, contains('ПЛАНИРОВАНИЕ ВЫДАЧИ'));
    expect(counter.userContents.single, contains('Фотосинтез'));
  });

  test('повторный запуск с тем же содержимым берёт кэш без сети', () async {
    counter = _FakeTokenCounter();
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();

    await runner.run(requestFor(anthropicAccount()));
    await runner.run(requestFor(anthropicAccount()));

    expect(counter.calls, 1, reason: 'кэш по хэшу содержимого запроса');
  });

  test('ошибка подсчёта → консервативная оценка, без падения', () async {
    counter = _FakeTokenCounter(
      result: const ExactTokenCount.unknown('http_401'),
    );
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();

    final GenerationRunResult result = await runner.run(
      requestFor(anthropicAccount()),
    );

    expect(counter.calls, 1);
    final InputPlan inputPlan = result.plan!.inputPlan!;
    expect(inputPlan.accuracy, InputAccuracy.estimated);
    expect(inputPlan.inputTokenSource, contains('estimate'));
    expect(result.status, GenerationJobStatus.done);
    expect(
      diagnostics.any((String line) => line.contains('count_tokens')),
      isTrue,
      reason: 'код ошибки виден в диагностике',
    );
  });

  test('подсчёт не выполняется без нативного счётчика (OpenAI)', () async {
    counter = _FakeTokenCounter();
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();

    final GenerationRunResult result = await runner.run(
      requestFor(openAiAccount()),
    );

    expect(counter.calls, 0, reason: 'у OpenAI/совместимых нет count_tokens');
    expect(result.plan!.inputPlan!.accuracy, InputAccuracy.estimated);
  });

  test('тела запросов не попадают в диагностику', () async {
    counter = _FakeTokenCounter();
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();

    await runner.run(requestFor(anthropicAccount()));

    final String all = diagnostics.join('\n');
    expect(all, isNot(contains('Фотосинтез')));
    expect(all, isNot(contains(jsonEncode(counter.userContents.single))));
    expect(all, isNot(contains('sk-ant')));
  });

  test('exact-режим не обнуляет стоимость изображений', () async {
    counter = _FakeTokenCounter(result: const ExactTokenCount.exact(1000));
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();
    // 64 КБ изображение: байтовая эвристика 256 байт/токен → 256 токенов.
    final DocumentImage image = DocumentImage(
      fileName: 'схема.png',
      id: 'img1',
      bytes: Uint8List.fromList(
        List<int>.generate(64 * 1024, (int i) => (i * 31) % 251),
      ),
      mediaType: AttachmentMediaType.png,
      caption: 'Схема',
      context: 'Схема из текста',
    );
    final GenerationRunRequest request = GenerationRunRequest(
      documents: <ParsedDocument>[
        docOf('лекция.txt', 'Фотосинтез — процесс преобразования света.'),
      ],
      documentImages: <DocumentImage>[image],
      account: anthropicAccount().copyWith(
        supportsVision: true,
        visionConfigured: true,
      ),
      deckName: 'Точный подсчёт',
      wishes: '3 карточки',
    );

    final GenerationRunResult result = await runner.run(request);
    final InputPlan inputPlan = result.plan!.inputPlan!;
    expect(inputPlan.accuracy, InputAccuracy.exact);
    expect(
      inputPlan.inputTokens,
      1256 + 38,
      reason:
          'count_tokens посчитал только текст (1000); изображение (256 '
          'токенов) добавляется оценкой, а не нулём',
    );
    expect(
      inputPlan.inputTokenSource,
      contains('image_estimate'),
      reason: 'источник честно говорит, что часть входа — оценка',
    );
  });
}
