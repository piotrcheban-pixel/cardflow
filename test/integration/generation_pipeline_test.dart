import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/http/redacting_log_interceptor.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
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

  ProviderContainer containerWith(Dio dio, {FakeApiKeyStore? keyStore}) {
    final container = ProviderContainer(
      overrides: [
        generationDioProvider.overrideWithValue(dio),
        apiKeyStoreProvider.overrideWithValue(
          keyStore ??
              FakeApiKeyStore(<GenerationProvider, String>{
                GenerationProvider.openai: openAiKey,
              }),
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
        const GenerationRequest(
          provider: GenerationProvider.openai,
          model: 'gpt-test',
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
            const GenerationRequest(
              provider: GenerationProvider.openai,
              model: 'gpt-test',
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
            const GenerationRequest(
              provider: GenerationProvider.openai,
              model: 'gpt-test',
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

  test('production Dio: таймауты A8.6 и redaction-перехватчик', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final dio = container.read(generationDioProvider);

    expect(dio.options.connectTimeout, const Duration(seconds: 15));
    expect(dio.options.sendTimeout, const Duration(seconds: 60));
    expect(dio.options.receiveTimeout, const Duration(seconds: 180));
    expect(dio.interceptors.whereType<RedactingLogInterceptor>(), hasLength(1));
  });

  test('production-граф собирает 3 адаптера (OpenAI/Gemini/Anthropic)', () {
    final container = ProviderContainer(
      overrides: [apiKeyStoreProvider.overrideWithValue(FakeApiKeyStore())],
    );
    addTearDown(container.dispose);
    final service = container.read(cardGenerationServiceProvider);
    expect(
      service.adapters.map((adapter) => adapter.provider).toSet(),
      GenerationProvider.values.toSet(),
    );
  });
}
