import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/http/redacting_log_interceptor.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/generation_fakes.dart';

/// Интеграционный срез итерации 3b (урок H1 итерации 2): production-проводка
/// `app_providers` → сервис → реальные адаптеры → HTTP-клиент → fake-транспорт.
/// Проверяются стыки: ключ из store → запрос провайдера → ответ → карточки.
void main() {
  const openAiKey = 'test-key-openai';

  Map<String, Object?> cardJson() => <String, Object?>{
    'front': 'Что такое FSRS?',
    'back': 'Алгоритм интервального повторения.',
    'hint': null,
    'tags': <Object?>['fsrs'],
    'card_type': 'basic',
    'source_excerpt': null,
    'source_file': 'лекция.docx',
  };

  Map<String, Object?> openAiSuccessPayload() => <String, Object?>{
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, Object?>{
          'role': 'assistant',
          'content': jsonEncode(<String, Object?>{
            'cards': <Object?>[cardJson()],
          }),
        },
        'finish_reason': 'stop',
      },
    ],
    'usage': <String, Object?>{
      'prompt_tokens': 10,
      'completion_tokens': 20,
      'total_tokens': 30,
    },
  };

  /// Аккаунт провайдера для запроса (id === ключ в secure storage).
  ProviderAccount accountWith({
    required String id,
    required ProviderProtocol protocol,
    required String modelId,
    String? baseUrl,
    bool requiresApiKey = true,
  }) {
    return ProviderAccount(
      id: id,
      label: id,
      protocol: protocol,
      baseUrl: baseUrl ?? protocol.defaultBaseUrl,
      modelId: modelId,
      requiresApiKey: requiresApiKey,
    );
  }

  ProviderContainer containerWith(
    Dio dio, {
    FakeApiKeyStore? keyStore,
    FakeGenerationSettingsStore? settingsStore,
  }) {
    final container = ProviderContainer(
      overrides: [
        generationDioProvider.overrideWithValue(dio),
        apiKeyStoreProvider.overrideWithValue(
          keyStore ?? FakeApiKeyStore(<String, String>{'openai': openAiKey}),
        ),
        generationSettingsStoreProvider.overrideWithValue(
          settingsStore ?? FakeGenerationSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'production-граф: OpenAI-запрос, ответ модели и валидация карточек',
    () async {
      final adapter = FakeHttpAdapter(
        (options) => jsonResponse(openAiSuccessPayload()),
      );
      final dio = dioWithAdapter(adapter);
      final container = containerWith(dio);
      final service = container.read(cardGenerationServiceProvider);

      final GenerationResult result = await service.generate(
        GenerationRequest(
          account: accountWith(
            id: 'openai',
            protocol: ProviderProtocol.openai,
            modelId: 'gpt-test',
          ),
          materialsText: 'Материал лекции',
          wishes: 'Покороче',
          limit: 7,
        ),
      );

      expect(result.cards, hasLength(1));
      expect(result.cards.single.front, 'Что такое FSRS?');
      expect(result.usage.totalTokens, 30);
      expect(result.promptVersion, 'gen-ru-v2');

      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.uri.toString(), 'https://api.openai.com/v1/chat/completions');
      expect(sent.headers['Authorization'], 'Bearer $openAiKey');
      final body = jsonDecode(sent.data! as String) as Map<String, Object?>;
      expect(body['model'], 'gpt-test');
      final messages = body['messages']! as List<Object?>;
      final userMessage =
          (messages[1]! as Map<String, Object?>)['content']! as String;
      expect(
        userMessage,
        contains('<materials>\nМатериал лекции\n</materials>'),
      );
      expect(userMessage, contains('<wishes>\nПокороче\n</wishes>'));
      expect(userMessage, endsWith('<limit>7</limit>'));
      final format = body['response_format']! as Map<String, Object?>;
      final strict = format['json_schema']! as Map<String, Object?>;
      expect(strict['strict'], isTrue);
    },
  );

  test('ошибка провайдера (401) доходит кодом invalidApiKey', () async {
    final dio = dioWithAdapter(
      FakeHttpAdapter(
        (options) => jsonResponse(<String, Object?>{
          'error': 'unauthorized',
        }, statusCode: 401),
      ),
    );
    final container = containerWith(dio);

    await expectLater(
      container
          .read(cardGenerationServiceProvider)
          .generate(
            GenerationRequest(
              account: accountWith(
                id: 'openai',
                protocol: ProviderProtocol.openai,
                modelId: 'gpt-test',
              ),
              materialsText: 'Материал',
              limit: 3,
            ),
          ),
      throwsA(
        isA<GenerationException>().having(
          (exception) => exception.code,
          'code',
          GenerationErrorCode.invalidApiKey,
        ),
      ),
    );
  });

  test('нет ключа — сообщение missingApiKey, запрос не уходит', () async {
    final adapter = FakeHttpAdapter(
      (options) => jsonResponse(openAiSuccessPayload()),
    );
    final container = containerWith(
      dioWithAdapter(adapter),
      keyStore: FakeApiKeyStore(),
    );

    await expectLater(
      container
          .read(cardGenerationServiceProvider)
          .generate(
            GenerationRequest(
              account: accountWith(
                id: 'openai',
                protocol: ProviderProtocol.openai,
                modelId: 'gpt-test',
              ),
              materialsText: 'Материал',
              limit: 3,
            ),
          ),
      throwsA(
        isA<GenerationException>().having(
          (exception) => exception.code,
          'code',
          GenerationErrorCode.missingApiKey,
        ),
      ),
    );
    expect(adapter.requests, isEmpty);
  });

  test(
    'production-граф: Gemini — ключ в заголовке, responseSchema, разбор ответа',
    () async {
      const geminiKey = 'test-key-gemini';
      final adapter = FakeHttpAdapter(
        (options) => jsonResponse(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{
                    'text': jsonEncode(<String, Object?>{
                      'cards': <Object?>[cardJson()],
                    }),
                  },
                ],
              },
              'finishReason': 'STOP',
            },
          ],
          'usageMetadata': <String, Object?>{
            'promptTokenCount': 5,
            'candidatesTokenCount': 6,
            'totalTokenCount': 11,
          },
        }),
      );
      final container = containerWith(
        dioWithAdapter(adapter),
        keyStore: FakeApiKeyStore(<String, String>{'gemini': geminiKey}),
      );

      final result = await container
          .read(cardGenerationServiceProvider)
          .generate(
            GenerationRequest(
              account: accountWith(
                id: 'gemini',
                protocol: ProviderProtocol.geminiGenerateContent,
                modelId: 'gemini-test',
              ),
              materialsText: 'Материал лекции',
              limit: 5,
            ),
          );

      expect(result.cards, hasLength(1));
      expect(result.usage.totalTokens, 11);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(
        sent.uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-test:generateContent',
      );
      expect(sent.headers['x-goog-api-key'], geminiKey);
      expect(sent.uri.toString(), isNot(contains(geminiKey)));
      final body = jsonDecode(sent.data! as String) as Map<String, Object?>;
      final config = body['generationConfig']! as Map<String, Object?>;
      expect(config['responseMimeType'], 'application/json');
      expect(
        config,
        containsPair('responseSchema', isA<Map<String, Object?>>()),
      );
    },
  );

  test(
    'production-граф: Anthropic — x-api-key, tool_use и разбор ответа',
    () async {
      const anthropicKey = 'test-key-anthropic';
      final adapter = FakeHttpAdapter(
        (options) => jsonResponse(<String, Object?>{
          'content': <Object?>[
            <String, Object?>{
              'type': 'tool_use',
              'id': 'toolu_1',
              'name': 'emit_cards',
              'input': <String, Object?>{
                'cards': <Object?>[cardJson()],
              },
            },
          ],
          'stop_reason': 'tool_use',
          'usage': <String, Object?>{'input_tokens': 7, 'output_tokens': 3},
        }),
      );
      final container = containerWith(
        dioWithAdapter(adapter),
        keyStore: FakeApiKeyStore(<String, String>{'anthropic': anthropicKey}),
      );

      final result = await container
          .read(cardGenerationServiceProvider)
          .generate(
            GenerationRequest(
              account: accountWith(
                id: 'anthropic',
                protocol: ProviderProtocol.anthropicMessages,
                modelId: 'claude-test',
              ),
              materialsText: 'Материал лекции',
              limit: 5,
            ),
          );

      expect(result.cards, hasLength(1));
      expect(result.usage.totalTokens, 10);
      expect(adapter.requests, hasLength(1));
      final sent = adapter.requests.single;
      expect(sent.uri.toString(), 'https://api.anthropic.com/v1/messages');
      expect(sent.headers['x-api-key'], anthropicKey);
      expect(sent.headers['anthropic-version'], '2023-06-01');
      final body = jsonDecode(sent.data! as String) as Map<String, Object?>;
      expect(body['max_tokens'], 8192);
      expect(body['tool_choice'], <String, Object?>{
        'type': 'tool',
        'name': 'emit_cards',
      });
    },
  );

  test('production-граф: OpenAI-compatible без ключа — локальный endpoint без Authorization', () async {
    final adapter = FakeHttpAdapter(
      (options) => jsonResponse(openAiSuccessPayload()),
    );
    final container = containerWith(
      dioWithAdapter(adapter),
      keyStore: FakeApiKeyStore(),
    );

    final GenerationResult result = await container
        .read(cardGenerationServiceProvider)
        .generate(
          GenerationRequest(
            account: accountWith(
              id: 'ollama',
              protocol: ProviderProtocol.openaiCompletions,
              modelId: 'qwen2.5',
              baseUrl: 'http://localhost:11434/v1',
              requiresApiKey: false,
            ),
            materialsText: 'Материал лекции',
            limit: 5,
          ),
        );

    expect(result.cards, hasLength(1));
    expect(result.model, 'qwen2.5');
    expect(adapter.requests, hasLength(1));
    final sent = adapter.requests.single;
    expect(sent.uri.toString(), 'http://localhost:11434/v1/chat/completions');
    expect(sent.headers.containsKey('Authorization'), isFalse);
    final body = jsonDecode(sent.data! as String) as Map<String, Object?>;
    expect(body['model'], 'qwen2.5');
    final format = body['response_format']! as Map<String, Object?>;
    expect(format['type'], 'json_schema');
  });

  test('production-граф: OpenAI-compatible strict 400 → fallback без response_format', () async {
    var calls = 0;
    final adapter = FakeHttpAdapter((options) {
      calls++;
      if (calls == 1) {
        return jsonResponse(<String, Object?>{
          'error': 'response_format is not supported',
        }, statusCode: 400);
      }
      return jsonResponse(openAiSuccessPayload());
    });
    final container = containerWith(
      dioWithAdapter(adapter),
      keyStore: FakeApiKeyStore(<String, String>{
        'deepseek': 'deepseek-test-key',
      }),
    );

    final GenerationResult result = await container
        .read(cardGenerationServiceProvider)
        .generate(
          GenerationRequest(
            account: accountWith(
              id: 'deepseek',
              protocol: ProviderProtocol.openaiCompletions,
              modelId: 'deepseek-chat',
              baseUrl: 'https://api.deepseek.com',
            ),
            materialsText: 'Материал лекции',
            limit: 5,
          ),
        );

    expect(result.cards, hasLength(1));
    expect(adapter.requests, hasLength(2));
    final first = adapter.requests[0];
    final second = adapter.requests[1];
    expect(first.uri.toString(), 'https://api.deepseek.com/chat/completions');
    expect(first.headers['Authorization'], 'Bearer deepseek-test-key');
    final firstBody = jsonDecode(first.data! as String) as Map<String, Object?>;
    expect(
      (firstBody['response_format']! as Map<String, Object?>)['type'],
      'json_schema',
    );
    final secondBody =
        jsonDecode(second.data! as String) as Map<String, Object?>;
    expect(secondBody.containsKey('response_format'), isFalse);
    expect(secondBody['model'], 'deepseek-chat');
  });

  test('production Dio: таймауты A8.6 и redaction-перехватчик', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dio = container.read(generationDioProvider);

    expect(dio.options.connectTimeout, const Duration(seconds: 15));
    expect(dio.options.sendTimeout, const Duration(seconds: 60));
    expect(dio.options.receiveTimeout, const Duration(seconds: 180));
    expect(dio.interceptors.whereType<RedactingLogInterceptor>(), hasLength(1));
  });

  test('production-граф собирает 4 адаптера (включая OpenAI-compatible)', () {
    final container = ProviderContainer(
      overrides: [
        apiKeyStoreProvider.overrideWithValue(FakeApiKeyStore()),
        generationSettingsStoreProvider.overrideWithValue(
          FakeGenerationSettingsStore(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final service = container.read(cardGenerationServiceProvider);
    expect(
      service.adapters.map((adapter) => adapter.provider).toSet(),
      GenerationProvider.values.toSet(),
    );
  });
}
