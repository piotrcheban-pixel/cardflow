import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/generation/request_token_counter.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Нативный подсчёт входа (ADR-040 §3.5.1): только mock-HTTP.
void main() {
  Dio dioWith(FakeHttpAdapter adapter) {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
      ),
    );
    dio.httpClientAdapter = adapter;
    return dio;
  }

  ProviderAccount account(ProviderProtocol protocol, String model) =>
      ProviderAccount(
        id: 'acc',
        label: 'Acc',
        protocol: protocol,
        baseUrl: protocol == ProviderProtocol.anthropicMessages
            ? 'https://api.anthropic.com'
            : 'https://generativelanguage.googleapis.com',
        modelId: model,
        requiresApiKey: true,
      );

  test('Anthropic count_tokens: точное значение и тело запроса', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(<String, Object?>{'input_tokens': 1234}),
    );
    final ExactTokenCount count =
        await AnthropicRequestTokenCounter(
          dioWith(adapter),
          readApiKey: (String id) async => 'test-key',
        ).count(
          account(ProviderProtocol.anthropicMessages, 'claude-test'),
          systemPrompt: 'system',
          userContent: 'user content',
        );
    expect(count.tokens, 1234);
    expect(count.isExact, isTrue);
    final RequestOptions request = adapter.requests.single;
    expect(
      request.uri.toString(),
      'https://api.anthropic.com/v1/messages/count_tokens',
    );
    expect(request.headers['anthropic-version'], '2023-06-01');
    expect(request.headers['Authorization'], 'Bearer test-key');
    final Map<String, Object?> body = request.data! as Map<String, Object?>;
    expect(body['model'], 'claude-test');
    expect(body['system'], 'system');
    // Схема ответа идёт инструментом и входит в точный подсчёт (docs).
    final List<Object?> tools = body['tools']! as List<Object?>;
    final Map<String, Object?> tool = tools.single! as Map<String, Object?>;
    expect(tool['input_schema'], anthropicToolCardSchema());
    expect(body['tool_choice'], isNotNull);
  });

  test('Gemini countTokens: x-goog-api-key и totalTokens', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(<String, Object?>{'totalTokens': 777}),
    );
    final ExactTokenCount count =
        await GeminiRequestTokenCounter(
          dioWith(adapter),
          readApiKey: (String id) async => 'test-key',
        ).count(
          account(ProviderProtocol.geminiGenerateContent, 'gemini-test'),
          systemPrompt: 'sys',
          userContent: 'text',
        );
    expect(count.tokens, 777);
    final RequestOptions request = adapter.requests.single;
    expect(request.uri.path, '/v1beta/models/gemini-test:countTokens');
    expect(request.headers['x-goog-api-key'], 'test-key');
    final Map<String, Object?> body = request.data! as Map<String, Object?>;
    final Map<String, Object?> config =
        body['generationConfig']! as Map<String, Object?>;
    expect(config['responseSchema'], geminiCardSchema());
  });

  test('ошибка HTTP — unknown с машинным кодом, не исключение', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) => jsonResponse(<String, Object?>{
        'error': 'unauthorized',
      }, statusCode: 401),
    );
    final ExactTokenCount count =
        await AnthropicRequestTokenCounter(
          dioWith(adapter),
          readApiKey: (String id) async => 'test-key',
        ).count(
          account(ProviderProtocol.anthropicMessages, 'claude-test'),
          systemPrompt: 's',
          userContent: 'u',
        );
    expect(count.isExact, isFalse);
    expect(count.errorCode, 'http_401');
  });

  test('нет ключа — no_api_key без запроса', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) => jsonResponse(<String, Object?>{}),
    );
    final ExactTokenCount count =
        await AnthropicRequestTokenCounter(
          dioWith(adapter),
          readApiKey: (String id) async => null,
        ).count(
          account(ProviderProtocol.anthropicMessages, 'claude-test'),
          systemPrompt: 's',
          userContent: 'u',
        );
    expect(count.errorCode, 'no_api_key');
    expect(adapter.requests, isEmpty);
  });

  test('supports: только документированные протоколы', () {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) => jsonResponse(<String, Object?>{}),
    );
    final Dio dio = dioWith(adapter);
    final RequestTokenCounter anthropic = AnthropicRequestTokenCounter(
      dio,
      readApiKey: (String id) async => 'k',
    );
    final RequestTokenCounter gemini = GeminiRequestTokenCounter(
      dio,
      readApiKey: (String id) async => 'k',
    );
    expect(
      anthropic.supports(account(ProviderProtocol.anthropicMessages, 'c')),
      isTrue,
    );
    expect(
      anthropic.supports(account(ProviderProtocol.geminiGenerateContent, 'g')),
      isFalse,
    );
    expect(
      gemini.supports(account(ProviderProtocol.geminiGenerateContent, 'g')),
      isTrue,
    );
    expect(gemini.supports(account(ProviderProtocol.openai, 'o')), isFalse);
    final ProtocolRequestTokenCounter router = ProtocolRequestTokenCounter(
      dio: dio,
      readApiKey: (String id) async => 'k',
    );
    expect(router.supports(account(ProviderProtocol.openai, 'o')), isFalse);
    expect(
      router.supports(account(ProviderProtocol.anthropicMessages, 'c')),
      isTrue,
    );
    expect(adapter.requests, isEmpty, reason: 'supports не ходит в сеть');
  });

  test('недокументированный протокол — no-op счётчик', () {
    final RequestTokenCounter counter = requestTokenCounterFor(
      account(ProviderProtocol.openai, 'gpt-4o-mini'),
      dioWith(
        FakeHttpAdapter(
          (RequestOptions options) => jsonResponse(<String, Object?>{}),
        ),
      ),
      readApiKey: (String id) async => 'k',
    );
    expect(counter, isA<NoopRequestTokenCounter>());
  });
}
