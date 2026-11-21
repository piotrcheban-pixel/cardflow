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

/// 7.18.3 §2: нативный подсчёт входа получает **тот же** мультимодальный
/// материал, что и production-запрос; изображения не учитываются дважды;
/// кэш зависит от байтов; число провайдера отделено от планового бюджета.
class _FakeTokenCounter implements RequestTokenCounter {
  _FakeTokenCounter({
    this.result = const ExactTokenCount.exact(1234),
    this.protocol = ProviderProtocol.anthropicMessages,
  });

  ExactTokenCount result;
  final ProviderProtocol protocol;

  int calls = 0;

  @override
  bool supports(ProviderAccount account) => account.protocol == protocol;

  final List<String> systemPrompts = <String>[];
  final List<String> userContents = <String>[];
  final List<List<GenerationAttachment>> attachments =
      <List<GenerationAttachment>>[];

  @override
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  }) async {
    calls++;
    systemPrompts.add(systemPrompt);
    userContents.add(userContent);
    this.attachments.add(attachments);
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
  promptVersion: 'gen-ru-v9',
  cards: <GeneratedCard>[makeGeneratedCard()],
  usage: const TokenUsage(
    promptTokens: 100,
    completionTokens: 20,
    totalTokens: 120,
  ),
);

DocumentImage imageOf({int seed = 1}) => DocumentImage(
  fileName: 'схема.png',
  bytes: Uint8List.fromList(
    List<int>.generate(64 * 1024, (int i) => (i * 31 + seed) % 251),
  ),
  mediaType: AttachmentMediaType.png,
  width: 800,
  height: 600,
  caption: 'Схема',
  context: 'Схема из текста',
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
    supportsVision: true,
    visionConfigured: true,
  );

  ProviderAccount geminiAccount() => ProviderAccount(
    id: 'gemini',
    label: 'Gemini',
    protocol: ProviderProtocol.geminiGenerateContent,
    baseUrl: 'https://generativelanguage.googleapis.com',
    modelId: 'gemini-test',
    contextTokens: 128000,
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

  GenerationRunRequest requestFor(
    ProviderAccount account, {
    List<DocumentImage> documentImages = const <DocumentImage>[],
  }) => GenerationRunRequest(
    documents: <ParsedDocument>[
      docOf('лекция.txt', 'Фотосинтез — процесс преобразования света.'),
    ],
    documentImages: documentImages,
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
    expect(inputPlan.nativeInputTokens, 1234, reason: 'число провайдера');
    expect(
      inputPlan.effectiveBudgetTokens,
      1234 + 38,
      reason: 'плановый бюджет = native + резерв, а не число провайдера',
    );
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
    expect(inputPlan.nativeInputTokens, isNull);
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

  test(
    'Anthropic: изображения уходят в count_tokens и не считаются дважды',
    () async {
      counter = _FakeTokenCounter(result: const ExactTokenCount.exact(1000));
      final runner = pipeline(tokenCounter: counter);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultWithCard();

      final GenerationRunResult result = await runner.run(
        requestFor(
          anthropicAccount(),
          documentImages: <DocumentImage>[imageOf()],
        ),
      );

      expect(counter.calls, 1);
      expect(counter.attachments.single, hasLength(1));
      expect(
        counter.attachments.single.single.bytes,
        orderedEquals(imageOf().bytes),
        reason: 'нативный подсчёт видит то же изображение, что и запрос',
      );
      final InputPlan inputPlan = result.plan!.inputPlan!;
      expect(inputPlan.accuracy, InputAccuracy.exact);
      expect(
        inputPlan.estimatedExtraTokens,
        0,
        reason: 'изображение посчитано',
      );
      expect(inputPlan.marginTokens, 30, reason: '3 % exact');
      expect(
        inputPlan.inputTokens,
        1030,
        reason: 'стоимость изображения (256 токенов) не прибавлена повторно',
      );
      expect(inputPlan.inputTokenSource, isNot(contains('image_estimate')));
      expect(
        result.plan!.estimate.schemaTokens,
        greaterThan(0),
        reason: 'схема есть, но Anthropic документированно считает её в tools',
      );
      expect(
        inputPlan.estimatedExtraTokens,
        0,
        reason: 'схема не добавлена повторно: tools входят в native count',
      );
      final String allDiagnostics = diagnostics.join('\n');
      expect(allDiagnostics, isNot(contains('base64')));
      expect(
        allDiagnostics,
        isNot(contains(base64Encode(imageOf().bytes))),
        reason: 'бинарные материалы в диагностику не попадают',
      );
    },
  );

  test(
    'кэш учитывает изменение байтов изображения при том же тексте',
    () async {
      counter = _FakeTokenCounter(result: const ExactTokenCount.exact(1000));
      final runner = pipeline(tokenCounter: counter);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultWithCard();

      await runner.run(
        requestFor(
          anthropicAccount(),
          documentImages: <DocumentImage>[imageOf(seed: 1)],
        ),
      );
      expect(counter.calls, 1);

      // Тот же текст и имя файла, другие байты — старый результат неприменим.
      await runner.run(
        requestFor(
          anthropicAccount(),
          documentImages: <DocumentImage>[imageOf(seed: 2)],
        ),
      );
      expect(
        counter.calls,
        2,
        reason: 'ключ кэша обязан включать digest бинарного содержимого',
      );

      // Тот же запрос ещё раз — снова кэш.
      await runner.run(
        requestFor(
          anthropicAccount(),
          documentImages: <DocumentImage>[imageOf(seed: 2)],
        ),
      );
      expect(counter.calls, 2);
    },
  );

  test(
    'Gemini: native + schemaOverhead = mixed, бюджет не выдан за native',
    () async {
      counter = _FakeTokenCounter(
        protocol: ProviderProtocol.geminiGenerateContent,
        result: const ExactTokenCount.exact(1000),
      );
      final runner = pipeline(tokenCounter: counter);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultWithCard();

      final GenerationRunResult result = await runner.run(
        requestFor(geminiAccount()),
      );

      final InputPlan inputPlan = result.plan!.inputPlan!;
      final int schemaTokens = result.plan!.estimate.schemaTokens;
      expect(schemaTokens, greaterThan(0));
      expect(
        inputPlan.accuracy,
        InputAccuracy.estimated,
        reason: 'responseSchema не подтверждён в totalTokens — не exact',
      );
      expect(inputPlan.nativeInputTokens, 1000);
      expect(inputPlan.estimatedExtraTokens, schemaTokens);
      expect(inputPlan.estimatedComponents, contains('response_schema'));
      final int counted = 1000 + schemaTokens;
      expect(inputPlan.marginTokens, (counted * 0.10).ceil());
      expect(
        inputPlan.effectiveBudgetTokens,
        counted + (counted * 0.10).ceil(),
      );
      expect(
        result.plan!.inputPlan!.inputTokenSource,
        contains('count_tokens'),
      );
    },
  );

  test('ошибка подсчёта с изображением: оценка, без двойного учёта', () async {
    counter = _FakeTokenCounter(
      result: const ExactTokenCount.unknown('timeout'),
    );
    final runner = pipeline(tokenCounter: counter);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        resultWithCard();

    final GenerationRunResult result = await runner.run(
      requestFor(
        anthropicAccount(),
        documentImages: <DocumentImage>[imageOf()],
      ),
    );

    final InputPlan inputPlan = result.plan!.inputPlan!;
    expect(inputPlan.accuracy, InputAccuracy.estimated);
    expect(inputPlan.nativeInputTokens, isNull);
    expect(inputPlan.estimatedExtraTokens, 0);
    expect(
      inputPlan.inputTokenSource,
      contains('estimate'),
      reason: 'источник честно говорит об оценке',
    );
    expect(result.status, GenerationJobStatus.done);
  });

  test(
    'запрос только из вложений: count_tokens видит «Файл:» и части',
    () async {
      counter = _FakeTokenCounter(result: const ExactTokenCount.exact(500));
      final runner = pipeline(tokenCounter: counter);
      caller.onGenerate = (GenerationRequest request, int call) async =>
          resultWithCard();
      final GenerationAttachment attachment = GenerationAttachment(
        fileName: 'схема.png',
        mediaType: AttachmentMediaType.png,
        bytes: imageOf().bytes,
      );

      final GenerationRunResult result = await runner.run(
        GenerationRunRequest(
          documents: const <ParsedDocument>[],
          images: <GenerationAttachment>[attachment],
          account: anthropicAccount(),
          deckName: 'Схема',
        ),
      );

      expect(counter.calls, 1);
      expect(
        counter.userContents.single,
        contains('Файл: схема.png'),
        reason: 'тот же текст материалов, что собирает сервис',
      );
      expect(counter.attachments.single, hasLength(1));
      expect(result.plan!.inputPlan!.nativeInputTokens, 500);
      expect(result.plan!.inputPlan!.accuracy, InputAccuracy.exact);
    },
  );
}
