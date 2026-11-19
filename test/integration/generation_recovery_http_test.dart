import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../helpers/generation_fakes.dart';
import '../live/support/local_provider_server.dart';

/// TASK 04, раздел 7-F: восстановление после ошибок через **реальный
/// HTTP-сокет** локального тестового endpoint.
///
/// Проверяются контракты, которые на fake-транспорте проходят «слишком
/// гладко»: 413, 429 с `Retry-After`, таймаут приёма, переполнение контекста
/// (400 + текст), битый JSON, обрезанный ответ (`finish_reason=length`).
/// Платных запросов нет — сервер слушает `127.0.0.1` и отвечает по сценарию.
/// Тест не имеет тега `live` и входит в обычный офлайновый набор.
void main() {
  late LocalProviderServer server;
  late Dio dio;

  setUp(() async {
    server = await LocalProviderServer.start();
    dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
  });

  tearDown(() async {
    dio.close(force: true);
    await server.close();
  });

  Map<String, Object?> validCardsBody() {
    return <String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'finish_reason': 'stop',
          'message': <String, Object?>{
            'content': jsonEncode(<String, Object?>{
              'cards': <Object?>[
                <String, Object?>{
                  'front': 'При каком условии две силы уравновешены?',
                  'back': 'Когда равны по модулю и противоположны.',
                  'hint': null,
                  'tags': <Object?>['статика'],
                  'card_type': 'basic',
                  'source_excerpt': null,
                  'source_file': null,
                  'image_id': null,
                  'image_query': null,
                },
              ],
            }),
          },
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': 100,
        'completion_tokens': 20,
        'total_tokens': 120,
      },
    };
  }

  CardGenerationService service({
    int maxAttempts = 1,
    Duration receiveTimeout = const Duration(seconds: 5),
  }) {
    dio.options.receiveTimeout = receiveTimeout;
    return CardGenerationService(
      adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
      apiKeyStore: FakeApiKeyStore(<String, String>{'local': 'test-key'}),
      httpClient: GenerationHttpClient(
        dio: dio,
        retryPolicy: RetryPolicy(
          maxAttempts: maxAttempts,
          baseDelay: const Duration(milliseconds: 1),
          jitter: () => 0,
        ),
        delay: (Duration _) async {},
      ),
    );
  }

  GenerationRequest request() {
    return GenerationRequest(
      account: ProviderAccount(
        id: 'local',
        label: 'Локальный тестовый сервер',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: server.baseUrl.toString(),
        modelId: 'test-model',
        requiresApiKey: true,
      ),
      materialsText:
          'Две силы уравновешены, если равны по модулю и '
          'противоположны по направлению.',
      limit: 1,
    );
  }

  Future<GenerationException> captureError(
    Future<GenerationResult> Function() call,
  ) async {
    try {
      await call();
      fail('Ожидалась GenerationException');
    } on GenerationException catch (error) {
      return error;
    }
  }

  test('успех: реальный HTTP-ответ разбирается, usage сохраняется', () async {
    server.enqueueJson(statusCode: 200, body: validCardsBody());

    final GenerationResult result = await service().generate(request());

    expect(result.cards, hasLength(1));
    expect(result.usage.promptTokens, 100);
    expect(result.usage.completionTokens, 20);
    expect(server.requestCount, 1);
    expect(
      server.requestBodies.single,
      contains('"model":"test-model"'),
      reason: 'тело запроса собрано адаптером',
    );
    expect(server.requestBodies.single, isNot(contains('test-key')));
  });

  test('413 → payloadTooLarge без повторов', () async {
    server.enqueueJson(
      statusCode: 413,
      body: <String, Object?>{'error': 'request too large'},
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(error.code, GenerationErrorCode.payloadTooLarge);
    expect(error.reason, GenerationFailureReason.payloadTooLarge);
    expect(server.requestCount, 1);
  });

  test('400 с текстом про контекст → contextOverflow без повторов', () async {
    server.enqueueJson(
      statusCode: 400,
      body: <String, Object?>{
        'error': <String, Object?>{
          'message': "This model's maximum context length is 8192 tokens",
        },
      },
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(error.code, GenerationErrorCode.contextOverflow);
    expect(error.providerReason, isNotNull);
    expect(server.requestCount, 1);
  });

  test('429 с Retry-After=120: одна попытка и пауза в ошибке', () async {
    server.enqueueJson(
      statusCode: 429,
      body: <String, Object?>{'error': 'rate limited'},
      headers: <String, String>{'retry-after': '120'},
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(error.code, GenerationErrorCode.rateLimited);
    expect(error.retryAfter, const Duration(seconds: 120));
    expect(server.requestCount, 1, reason: 'выше maxRetryAfter — без повтора');
  });

  test('429 с Retry-After=0: транспорт повторяет и получает успех', () async {
    server.enqueueJson(
      statusCode: 429,
      body: <String, Object?>{'error': 'rate limited'},
      headers: <String, String>{'retry-after': '0'},
    );
    server.enqueueJson(statusCode: 200, body: validCardsBody());

    final GenerationResult result = await service(maxAttempts: 2)
        .generate(request());

    expect(result.cards, hasLength(1));
    expect(server.requestCount, 2);
  });

  test('таймаут приёма → timeout', () async {
    server.enqueueJson(
      statusCode: 200,
      body: validCardsBody(),
      delay: const Duration(milliseconds: 800),
    );

    final GenerationException error = await captureError(
      () =>
          service(receiveTimeout: const Duration(milliseconds: 100))
              .generate(request()),
    );

    expect(error.code, GenerationErrorCode.timeout);
  });

  test('битый JSON → invalidResponse без повторов', () async {
    server.enqueue(
      const LocalProviderResponse(statusCode: 200, body: 'это не JSON'),
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(error.code, GenerationErrorCode.invalidResponse);
    expect(server.requestCount, 1);
  });

  test('обрезанный ответ (finish_reason=length) → truncated', () async {
    server.enqueueJson(
      statusCode: 200,
      body: <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'finish_reason': 'length',
            'message': <String, Object?>{'content': '{"cards": ['},
          },
        ],
      },
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(error.code, GenerationErrorCode.truncated);
    expect(server.requestCount, 1);
  });

  test('5xx → serverUnavailable, повторы ограничены политикой', () async {
    for (var attempt = 0; attempt < 2; attempt++) {
      server.enqueueJson(
        statusCode: 500,
        body: <String, Object?>{'error': 'internal'},
      );
    }

    final GenerationException error = await captureError(
      () => service(maxAttempts: 2).generate(request()),
    );

    expect(error.code, GenerationErrorCode.serverUnavailable);
    expect(server.requestCount, 2);
  });

  test('обрыв соединения без ответа → network', () async {
    server.enqueue(
      const LocalProviderResponse(statusCode: 200, closeWithoutReply: true),
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(
      error.code,
      anyOf(
        GenerationErrorCode.network,
        GenerationErrorCode.invalidResponse,
        GenerationErrorCode.timeout,
      ),
    );
  });

  test('401 → invalidApiKey (fatal для пайплайна)', () async {
    server.enqueueJson(
      statusCode: 401,
      body: <String, Object?>{'error': 'invalid key'},
    );

    final GenerationException error = await captureError(
      () => service().generate(request()),
    );

    expect(error.code, GenerationErrorCode.invalidApiKey);
  });
}
