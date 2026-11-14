import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/generation_fakes.dart';

/// Итерация 7.5 (ADR-020): сервис генерации — аккаунт → промпт → адаптер →
/// транспорт → разбор → схема → контент-валидация (SPEC A8.5 шаги 6–7).
void main() {
  /// Облачный аккаунт с ключом в хранилище.
  ProviderAccount openAiAccount({String modelId = 'gpt-test'}) {
    return ProviderAccount(
      id: 'openai',
      label: 'OpenAI',
      presetId: 'openai',
      protocol: ProviderProtocol.openai,
      baseUrl: 'https://api.openai.com/v1',
      modelId: modelId,
      contextTokens: 128000,
      requiresApiKey: true,
    );
  }

  /// OpenAI-совместимый аккаунт (DeepSeek/локальный сервер).
  ProviderAccount compatibleAccount({
    String id = 'deepseek',
    String baseUrl = 'https://api.deepseek.com',
    String modelId = 'deepseek-chat',
    bool requiresApiKey = false,
  }) {
    return ProviderAccount(
      id: id,
      label: 'DeepSeek',
      presetId: 'deepseek',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: baseUrl,
      modelId: modelId,
      contextTokens: 128000,
      requiresApiKey: requiresApiKey,
    );
  }

  GenerationRequest requestFor(
    ProviderAccount account, {
    String materialsText = 'Материал лекции',
    String? wishes = 'Акцент на датах',
    int limit = 10,
  }) {
    return GenerationRequest(
      account: account,
      materialsText: materialsText,
      wishes: wishes,
      limit: limit,
    );
  }

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
    String systemPrompt = 'СИСТЕМНЫЙ ПРОМПТ',
  }) {
    return CardGenerationService(
      adapters: <FakeProviderAdapter>[adapter],
      apiKeyStore:
          apiKeyStore ??
          FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
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

      final result = await service.generate(requestFor(openAiAccount()));

      expect(result.provider, GenerationProvider.openai);
      expect(result.model, 'gpt-test');
      expect(result.promptVersion, 'gen-ru-v2');
      expect(result.cards, hasLength(1));
      expect(result.cards.single.front, 'Вопрос');
      expect(adapter.buildArgs!.apiKey, 'test-key-openai');
      expect(adapter.buildArgs!.model, 'gpt-test');
      expect(adapter.buildArgs!.baseUrl, 'https://api.openai.com/v1');
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

  test(
    'ключ не задан у аккаунта, который его требует → missingApiKey',
    () async {
      final adapter = FakeProviderAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
      );

      await expectLater(
        service.generate(requestFor(openAiAccount())),
        throwsGeneration(GenerationErrorCode.missingApiKey),
      );
      expect(adapter.buildCalls, 0);
      expect(transport.calls, 0);
    },
  );

  test('ключ из пробелов → missingApiKey', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
      apiKeyStore: FakeApiKeyStore(<String, String>{'openai': '   '}),
    );
    await expectLater(
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.missingApiKey),
    );
  });

  test('аккаунт без адреса → providerNotConfigured, без запроса', () async {
    final adapter = FakeProviderAdapter();
    final service = serviceWith(
      adapter: adapter,
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(requestFor(compatibleAccount(baseUrl: '  '))),
      throwsGeneration(GenerationErrorCode.providerNotConfigured),
    );
    expect(adapter.buildCalls, 0);
  });

  test('ошибка разбора адаптера пробрасывается как есть', () async {
    final adapter = FakeProviderAdapter(
      error: const GenerationException(GenerationErrorCode.truncated),
    );
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = serviceWith(adapter: adapter, transport: transport);

    await expectLater(
      service.generate(requestFor(openAiAccount())),
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
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.serverUnavailable),
    );
  });

  test('не-JSON ответ модели → invalidResponse', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(cardsJson: 'не json'),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(requestFor(openAiAccount())),
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
      service.generate(requestFor(openAiAccount())),
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
    final result = await service.generate(requestFor(openAiAccount()));
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
    final result = await service.generate(requestFor(openAiAccount()));
    expect(result.cards.single.hasIssues, isTrue);
  });

  test('используется адаптер протокола аккаунта и ключ его id', () async {
    final openAi = FakeProviderAdapter(provider: GenerationProvider.openai);
    final gemini = FakeProviderAdapter(provider: GenerationProvider.gemini);
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = CardGenerationService(
      adapters: <FakeProviderAdapter>[openAi, gemini],
      apiKeyStore: FakeApiKeyStore(<String, String>{'gemini': 'key-gemini'}),
      httpClient: transport,
    );
    final ProviderAccount geminiAccount = ProviderAccount(
      id: 'gemini',
      label: 'Gemini',
      presetId: 'gemini',
      protocol: ProviderProtocol.geminiGenerateContent,
      baseUrl: 'https://generativelanguage.googleapis.com',
      modelId: 'gemini-2.0-flash',
      contextTokens: 1048576,
      requiresApiKey: true,
    );

    await service.generate(requestFor(geminiAccount));
    expect(openAi.buildCalls, 0);
    expect(gemini.buildCalls, 1);
    expect(gemini.buildArgs!.apiKey, 'key-gemini');
    expect(gemini.buildArgs!.model, 'gemini-2.0-flash');
  });

  test('нет адаптера для протокола аккаунта → ArgumentError', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(provider: GenerationProvider.openai),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final ProviderAccount anthropicAccount = ProviderAccount(
      id: 'anthropic',
      label: 'Anthropic',
      presetId: 'anthropic',
      protocol: ProviderProtocol.anthropicMessages,
      baseUrl: 'https://api.anthropic.com',
      modelId: 'claude-3-5-haiku-latest',
      contextTokens: 200000,
      requiresApiKey: true,
    );
    await expectLater(
      service.generate(requestFor(anthropicAccount)),
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
    final result = await service.generate(requestFor(openAiAccount()));
    expect(
      result.usage,
      const TokenUsage(promptTokens: 3, completionTokens: 4, totalTokens: 7),
    );
  });

  group('OpenAI-совместимый протокол (ADR-013, ADR-020)', () {
    FakeProviderAdapter compatibleAdapter({
      String cardsJson = '{"cards":[]}',
    }) => FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson,
    );

    test('адрес и модель из аккаунта, ключ опционален', () async {
      final adapter = compatibleAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
      );

      final result = await service.generate(
        requestFor(compatibleAccount(baseUrl: 'http://localhost:11434/v1')),
      );

      expect(result.provider, GenerationProvider.openaiCompatible);
      expect(result.model, 'deepseek-chat');
      expect(adapter.buildArgs!.baseUrl, 'http://localhost:11434/v1');
      expect(adapter.buildArgs!.model, 'deepseek-chat');
      expect(adapter.buildArgs!.apiKey, isEmpty);
      expect(adapter.buildArgs!.strictSchema, isTrue);
      expect(transport.calls, 1);
    });

    test('аккаунт, требующий ключ, без ключа → missingApiKey', () async {
      final adapter = compatibleAdapter();
      final service = serviceWith(
        adapter: adapter,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
      );

      await expectLater(
        service.generate(requestFor(compatibleAccount(requiresApiKey: true))),
        throwsGeneration(GenerationErrorCode.missingApiKey),
      );
      expect(adapter.buildCalls, 0);
    });

    test(
      'strict 400 → один fallback без response_format, ответ валиден',
      () async {
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
        );

        final result = await service.generate(
          requestFor(compatibleAccount(baseUrl: 'http://localhost:11434/v1')),
        );

        expect(result.cards, isEmpty);
        expect(transport.calls, 2);
        expect(adapter.buildCalls, 2);
        expect(adapter.buildArgs!.strictSchema, isFalse);
        expect(adapter.buildArgs!.baseUrl, 'http://localhost:11434/v1');
      },
    );

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
      );

      await expectLater(
        service.generate(requestFor(compatibleAccount())),
        throwsGeneration(GenerationErrorCode.badRequest),
      );
      expect(transport.calls, 2);
    });

    test(
      'без fallback-кода поведение прежнее: 5xx не повторяется сервисом',
      () async {
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
        );

        await expectLater(
          service.generate(requestFor(compatibleAccount())),
          throwsGeneration(GenerationErrorCode.serverUnavailable),
        );
        expect(transport.calls, 1);
      },
    );

    test(
      'нативный протокол: badRequest не повторяется fallback-логикой',
      () async {
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
          service.generate(requestFor(openAiAccount())),
          throwsGeneration(GenerationErrorCode.badRequest),
        );
        expect(transport.calls, 1);
      },
    );

    test('markdown вокруг JSON извлекается только у compatible-протокола', () async {
      final tolerant = compatibleAdapter(
        cardsJson:
            'Вот карточки:\n```json\n${cardsJson(<Map<String, Object?>>[])}\n```',
      );
      final service = serviceWith(
        adapter: tolerant,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
      );
      final result = await service.generate(requestFor(compatibleAccount()));
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
        openAiService.generate(requestFor(openAiAccount())),
        throwsGeneration(GenerationErrorCode.invalidResponse),
      );
    });
  });
}
