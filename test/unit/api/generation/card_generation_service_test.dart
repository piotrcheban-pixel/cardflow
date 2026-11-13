import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

import '../../../helpers/generation_fakes.dart';

/// Красная фаза итерации 3b: сервис генерации — ключ → промпт → адаптер →
/// транспорт → разбор → схема → контент-валидация (SPEC A8.5 шаги 6–7).
void main() {
  const request = GenerationRequest(
    provider: GenerationProvider.openai,
    model: 'gpt-test',
    materialsText: 'Материал лекции',
    wishes: 'Акцент на датах',
    limit: 10,
  );

  Map<String, Object?> validCardJson() => <String, Object?>{
    'front': 'Вопрос',
    'back': 'Ответ',
    'hint': null,
    'tags': <Object?>['тег'],
    'card_type': 'basic',
    'source_excerpt': null,
    'source_file': null,
  };

  String cardsJson(List<Map<String, Object?>> cards) =>
      jsonEncode(<String, Object?>{'cards': cards});

  CardGenerationService serviceWith({
    required FakeProviderAdapter adapter,
    required FakeGenerationTransport transport,
    FakeApiKeyStore? apiKeyStore,
    FakeGenerationSettingsStore? settingsStore,
    String systemPrompt = 'СИСТЕМНЫЙ ПРОМПТ',
  }) {
    return CardGenerationService(
      adapters: <FakeProviderAdapter>[adapter],
      apiKeyStore:
          apiKeyStore ??
          FakeApiKeyStore(<GenerationProvider, String>{
            GenerationProvider.openai: 'test-key-openai',
          }),
      generationSettingsStore: settingsStore ?? FakeGenerationSettingsStore(),
      httpClient: transport,
      systemPrompt: systemPrompt,
      promptVersion: 'gen-ru-v2',
      maxOutputTokens: 1234,
    );
  }

  Matcher throwsGeneration(GenerationErrorCode code) => throwsA(
    isA<GenerationException>().having(
      (exception) => exception.code,
      'code',
      code,
    ),
  );

  test(
    'успех: ключ → запрос → ответ → карточки, расход и версия промпта',
    () async {
      final adapter = FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[validCardJson()]),
      );
      final transport = FakeGenerationTransport(
        response: <String, Object?>{'ok': true},
      );
      final service = serviceWith(adapter: adapter, transport: transport);

      final result = await service.generate(request);

      expect(result.provider, GenerationProvider.openai);
      expect(result.model, 'gpt-test');
      expect(result.promptVersion, 'gen-ru-v2');
      expect(result.cards, hasLength(1));
      expect(result.cards.single.front, 'Вопрос');
      expect(adapter.buildArgs!.apiKey, 'test-key-openai');
      expect(adapter.buildArgs!.model, 'gpt-test');
      expect(adapter.buildArgs!.systemPrompt, 'СИСТЕМНЫЙ ПРОМПТ');
      expect(adapter.buildArgs!.maxOutputTokens, 1234);
      expect(
        adapter.buildArgs!.userContent,
        contains('<materials>\nМатериал лекции\n</materials>'),
      );
      expect(
        adapter.buildArgs!.userContent,
        contains('<wishes>\nАкцент на датах\n</wishes>'),
      );
      expect(adapter.buildArgs!.userContent, endsWith('<limit>10</limit>'));
      expect(transport.calls, 1);
    },
  );

  test('ключ не задан → missingApiKey, без запроса', () async {
    final adapter = FakeProviderAdapter();
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = serviceWith(
      adapter: adapter,
      transport: transport,
      apiKeyStore: FakeApiKeyStore(),
    );

    await expectLater(
      service.generate(request),
      throwsGeneration(GenerationErrorCode.missingApiKey),
    );
    expect(adapter.buildCalls, 0);
    expect(transport.calls, 0);
  });

  test('ключ из пробелов → missingApiKey', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
      apiKeyStore: FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.openai: '   ',
      }),
    );
    await expectLater(
      service.generate(request),
      throwsGeneration(GenerationErrorCode.missingApiKey),
    );
  });

  test('ошибка разбора адаптера пробрасывается как есть', () async {
    final adapter = FakeProviderAdapter(
      error: const GenerationException(GenerationErrorCode.truncated),
    );
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = serviceWith(adapter: adapter, transport: transport);

    await expectLater(
      service.generate(request),
      throwsGeneration(GenerationErrorCode.truncated),
    );
    expect(transport.calls, 1);
  });

  test('ошибка транспорта пробрасывается как есть', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(),
      transport: FakeGenerationTransport(
        error: const GenerationException(GenerationErrorCode.serverUnavailable),
      ),
    );
    await expectLater(
      service.generate(request),
      throwsGeneration(GenerationErrorCode.serverUnavailable),
    );
  });

  test('не-JSON ответ модели → invalidResponse', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(cardsJson: 'не json'),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(request),
      throwsGeneration(GenerationErrorCode.invalidResponse),
    );
  });

  test('JSON не по схеме A8.4 → invalidResponse (back отсутствует)', () async {
    final card = validCardJson()..remove('back');
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[card]),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(request),
      throwsGeneration(GenerationErrorCode.invalidResponse),
    );
  });

  test('пустой массив cards — валидный результат без карточек', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final result = await service.generate(request);
    expect(result.cards, isEmpty);
  });

  test('контентные пометки A8.4 доходят до результата', () async {
    final card = validCardJson()..['front'] = '';
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[card]),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final result = await service.generate(request);
    expect(result.cards.single.hasIssues, isTrue);
  });

  test('используется адаптер запрошенного провайдера', () async {
    final openAi = FakeProviderAdapter(provider: GenerationProvider.openai);
    final gemini = FakeProviderAdapter(provider: GenerationProvider.gemini);
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = CardGenerationService(
      adapters: <FakeProviderAdapter>[openAi, gemini],
      apiKeyStore: FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.gemini: 'test-key-gemini',
      }),
      httpClient: transport,
    );

    await service.generate(
      const GenerationRequest(
        provider: GenerationProvider.gemini,
        model: 'gemini-test',
        materialsText: 'Материал',
        limit: 5,
      ),
    );
    expect(openAi.buildCalls, 0);
    expect(gemini.buildCalls, 1);
    expect(gemini.buildArgs!.apiKey, 'test-key-gemini');
  });

  test('нет адаптера для провайдера → ArgumentError', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(provider: GenerationProvider.openai),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(
        const GenerationRequest(
          provider: GenerationProvider.anthropic,
          model: 'claude-test',
          materialsText: 'Материал',
          limit: 5,
        ),
      ),
      throwsArgumentError,
    );
  });

  test('расход токенов из ответа попадает в результат', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
        usage: const TokenUsage(
          promptTokens: 3,
          completionTokens: 4,
          totalTokens: 7,
        ),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final result = await service.generate(request);
    expect(
      result.usage,
      const TokenUsage(promptTokens: 3, completionTokens: 4, totalTokens: 7),
    );
  });

  group('OpenAI-compatible (ADR-013)', () {
    const compatibleRequest = GenerationRequest(
      provider: GenerationProvider.openaiCompatible,
      model: 'модель-из-запроса',
      materialsText: 'Материал лекции',
      limit: 5,
    );
    const configured = OpenAiCompatibleSettings(
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen2.5',
    );

    FakeProviderAdapter compatibleAdapter({
      String cardsJson = '{"cards":[]}',
    }) => FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson,
    );

    test('настройки сервера переопределяют модель, ключ опционален', () async {
      final adapter = compatibleAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: FakeGenerationSettingsStore(configured),
      );

      final result = await service.generate(compatibleRequest);

      expect(result.provider, GenerationProvider.openaiCompatible);
      expect(result.model, 'qwen2.5');
      expect(adapter.buildArgs!.baseUrl, 'http://localhost:11434/v1');
      expect(adapter.buildArgs!.model, 'qwen2.5');
      expect(adapter.buildArgs!.apiKey, isEmpty);
      expect(adapter.buildArgs!.strictSchema, isTrue);
      expect(transport.calls, 1);
    });

    test('сервер не настроен (пустые настройки) → providerNotConfigured', () async {
      final adapter = compatibleAdapter();
      final service = serviceWith(
        adapter: adapter,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: FakeGenerationSettingsStore(),
      );

      await expectLater(
        service.generate(compatibleRequest),
        throwsGeneration(GenerationErrorCode.providerNotConfigured),
      );
      expect(adapter.buildCalls, 0);
    });

    test('некорректный сохранённый base_url → providerNotConfigured', () async {
      final settingsStore = FakeGenerationSettingsStore(
        const OpenAiCompatibleSettings(baseUrl: 'ftp://x', model: 'm'),
      );
      final service = serviceWith(
        adapter: compatibleAdapter(),
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: settingsStore,
      );

      await expectLater(
        service.generate(compatibleRequest),
        throwsGeneration(GenerationErrorCode.providerNotConfigured),
      );
    });

    test('strict 400 → один fallback без response_format, ответ валиден', () async {
      final fenced = '```json\n${cardsJson(<Map<String, Object?>>[])}\n```';
      final adapter = compatibleAdapter(cardsJson: fenced);
      final transport = FakeGenerationTransport(
        response: <String, Object?>{},
        errorsBeforeResponse: <Object?>[
          const GenerationException(GenerationErrorCode.badRequest),
        ],
      );
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: FakeGenerationSettingsStore(configured),
      );

      final result = await service.generate(compatibleRequest);

      expect(result.cards, isEmpty);
      expect(transport.calls, 2);
      expect(adapter.buildCalls, 2);
      expect(adapter.buildArgs!.strictSchema, isFalse);
      expect(adapter.buildArgs!.baseUrl, configured.baseUrl);
    });

    test('fallback тоже 400 → badRequest, не больше двух запросов', () async {
      final transport = FakeGenerationTransport(
        response: <String, Object?>{},
        errorsBeforeResponse: <Object?>[
          const GenerationException(GenerationErrorCode.badRequest),
          const GenerationException(GenerationErrorCode.badRequest),
        ],
      );
      final service = serviceWith(
        adapter: compatibleAdapter(),
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: FakeGenerationSettingsStore(configured),
      );

      await expectLater(
        service.generate(compatibleRequest),
        throwsGeneration(GenerationErrorCode.badRequest),
      );
      expect(transport.calls, 2);
    });

    test('без fallback-кода поведение прежнее: 5xx не повторяется сервисом', () async {
      final transport = FakeGenerationTransport(
        response: <String, Object?>{},
        errorsBeforeResponse: <Object?>[
          const GenerationException(GenerationErrorCode.serverUnavailable),
        ],
      );
      final service = serviceWith(
        adapter: compatibleAdapter(),
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: FakeGenerationSettingsStore(configured),
      );

      await expectLater(
        service.generate(compatibleRequest),
        throwsGeneration(GenerationErrorCode.serverUnavailable),
      );
      expect(transport.calls, 1);
    });

    test('обычный подрядчик: badRequest не повторяется fallback-логикой', () async {
      final transport = FakeGenerationTransport(
        response: <String, Object?>{},
        errorsBeforeResponse: <Object?>[
          const GenerationException(GenerationErrorCode.badRequest),
        ],
      );
      final service = serviceWith(
        adapter: FakeProviderAdapter(provider: GenerationProvider.openai),
        transport: transport,
      );

      await expectLater(
        service.generate(request),
        throwsGeneration(GenerationErrorCode.badRequest),
      );
      expect(transport.calls, 1);
    });

    test('markdown вокруг JSON извлекается только у compatible-провайдера', () async {
      final tolerant = compatibleAdapter(
        cardsJson:
            'Вот карточки:\n```json\n${cardsJson(<Map<String, Object?>>[])}\n```',
      );
      final service = serviceWith(
        adapter: tolerant,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
        settingsStore: FakeGenerationSettingsStore(configured),
      );
      final result = await service.generate(compatibleRequest);
      expect(result.cards, isEmpty);

      final strict = FakeProviderAdapter(
        provider: GenerationProvider.openai,
        cardsJson:
            'Вот карточки:\n```json\n${cardsJson(<Map<String, Object?>>[])}\n```',
      );
      final openAiService = serviceWith(
        adapter: strict,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
      );
      await expectLater(
        openAiService.generate(request),
        throwsGeneration(GenerationErrorCode.invalidResponse),
      );
    });
  });
}
