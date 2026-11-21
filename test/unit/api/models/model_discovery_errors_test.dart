import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/models/model_discovery.dart';
import 'package:cardflow/domain/generation/model_capability_discovery.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/fake_http_adapter.dart';

/// §3.3/§5.4: ошибки discovery — неверный тип поля, отсутствующее поле, пустой
/// список, 401 и таймаут — обрабатываются предсказуемо для **каждого**
/// протокола, а не только для OpenAI-совместимого. Значение при ошибке остаётся
/// неизвестным (`null`), а не 0 и не «типовым».
void main() {
  const ApiKeyReader keyReader = _testKey;
  String fixture(String path) =>
      File('test/fixtures/discovery/$path').readAsStringSync();

  Map<String, Object?> decode(String text) {
    final Object? decoded = jsonDecode(text);
    return decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
  }

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

  ProviderAccount anthropic() => const ProviderAccount(
    id: 'claude',
    label: 'Claude',
    protocol: ProviderProtocol.anthropicMessages,
    baseUrl: 'https://api.anthropic.com',
    modelId: 'claude-test',
    presetId: 'anthropic',
  );

  ProviderAccount gemini() => const ProviderAccount(
    id: 'gemini',
    label: 'Gemini',
    protocol: ProviderProtocol.geminiGenerateContent,
    baseUrl: 'https://generativelanguage.googleapis.com',
    modelId: 'gemini-test',
    presetId: 'gemini',
  );

  ProviderAccount ollama() => const ProviderAccount(
    id: 'ollama',
    label: 'Ollama',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'http://localhost:11434',
    modelId: 'test-model',
    presetId: 'ollama',
    requiresApiKey: false,
  );

  ProviderAccount compatible() => const ProviderAccount(
    id: 'custom',
    label: 'Свой сервер',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.example.com',
    modelId: 'test-model',
  );

  ModelCapabilityDiscovery discoveryFor(
    ProviderAccount account,
    FakeHttpAdapter adapter,
  ) => discoveryForAccount(
    account,
    dioWith(adapter),
    readApiKey: keyReader,
  );

  Dio dioAllowing4xx(FakeHttpAdapter adapter) {
    final Dio dio = dioWith(adapter);
    dio.options.validateStatus = (int? status) => true;
    return dio;
  }

  group('Anthropic: ошибки discovery', () {
    test('401 — unauthorized, лимиты неизвестны', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(<String, Object?>{'error': 'x'}, statusCode: 401),
      );
      final DiscoveryResult result = await AnthropicModelsDiscovery(
        dioAllowing4xx(adapter),
        readApiKey: keyReader,
      ).discover(anthropic());
      expect(result.status, DiscoveryStatus.unauthorized);
      expect(result.errorCode, 'unauthorized');
      expect(result.keepsPrevious, isTrue);
      expect(result.limits, isNull);
    });

    test('таймаут — timeout, без падения', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      final DiscoveryResult result = await AnthropicModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(anthropic());
      expect(result.status, DiscoveryStatus.timeout);
      expect(result.errorCode, 'timeout');
    });

    test('пустой список и отсутствующие поля — unknown, не 0', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'claude-test'},
          ],
          'has_more': false,
        }),
      );
      final DiscoveryResult result = await AnthropicModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(anthropic());
      expect(result.status, DiscoveryStatus.success);
      expect(result.limits!.maxInputTokens.isKnown, isFalse);
      expect(result.limits!.maxOutputTokens.isKnown, isFalse);
      expect(result.limits!.supportsImageInput.isKnown, isFalse);
    });

    test('неверный тип поля — не значение', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': 'claude-test',
              'max_input_tokens': '200000',
              'max_tokens': <String, Object?>{'value': 4096},
              'capabilities': 'image_input',
            },
          ],
        }),
      );
      final DiscoveryResult result = await AnthropicModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(anthropic());
      expect(result.limits!.maxInputTokens.isKnown, isFalse);
      expect(result.limits!.maxOutputTokens.isKnown, isFalse);
      expect(result.limits!.supportsImageInput.isKnown, isFalse);
    });
  });

  group('Gemini: ошибки discovery', () {
    test('401 — unauthorized', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(<String, Object?>{}, statusCode: 401),
      );
      final DiscoveryResult result = await GeminiModelsDiscovery(
        dioAllowing4xx(adapter),
        readApiKey: keyReader,
      ).discover(gemini());
      expect(result.status, DiscoveryStatus.unauthorized);
      expect(result.errorCode, 'unauthorized');
    });

    test('таймаут — timeout', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        ),
      );
      final DiscoveryResult result = await GeminiModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(gemini());
      expect(result.status, DiscoveryStatus.timeout);
    });

    test('пустой список — успех, модель не найдена', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(<String, Object?>{'models': <Object?>[]}),
      );
      final DiscoveryResult result = await GeminiModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(gemini());
      expect(result.status, DiscoveryStatus.success);
      expect(result.models, isEmpty);
      expect(result.warnings, contains('model_not_in_list'));
      expect(result.limits!.maxInputTokens.isKnown, isFalse);
    });

    test('неверный тип полей — не значение', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'models': <Object?>[
            <String, Object?>{
              'name': 'models/gemini-test',
              'inputTokenLimit': true,
              'outputTokenLimit': <Object?>[],
            },
          ],
        }),
      );
      final DiscoveryResult result = await GeminiModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(gemini());
      expect(result.limits!.maxInputTokens.isKnown, isFalse);
      expect(result.limits!.maxOutputTokens.isKnown, isFalse);
    });
  });

  group('Ollama: ошибки discovery', () {
    test('401/403 — unauthorized', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(<String, Object?>{}, statusCode: 403),
      );
      final DiscoveryResult result = await OllamaModelsDiscovery(
        dioAllowing4xx(adapter),
        readApiKey: _absentKey,
      ).discover(ollama());
      expect(result.status, DiscoveryStatus.unauthorized);
    });

    test('таймаут на /api/tags — timeout', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      final DiscoveryResult result = await OllamaModelsDiscovery(
        dioWith(adapter),
        readApiKey: _absentKey,
      ).discover(ollama());
      expect(result.status, DiscoveryStatus.timeout);
    });

    test('пустой список моделей — успех без показа модели', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(<String, Object?>{'models': <Object?>[]}),
      );
      final DiscoveryResult result = await OllamaModelsDiscovery(
        dioWith(adapter),
        readApiKey: _absentKey,
      ).discover(ollama());
      expect(result.status, DiscoveryStatus.success);
      expect(result.models, isEmpty);
      expect(result.limits!.contextTokens.isKnown, isFalse);
    });

    test('неверный тип model_info — контекст неизвестен', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        if (options.path.contains('/api/tags')) {
          return jsonResponse(decode(fixture('ollama/tags.json')));
        }
        return jsonResponse(<String, Object?>{
          'model_info': <String, Object?>{
            'llama.context_length': '8192',
          },
          'capabilities': 'vision',
        });
      });
      final DiscoveryResult result = await OllamaModelsDiscovery(
        dioWith(adapter),
        readApiKey: _absentKey,
      ).discover(ollama());
      expect(result.limits!.contextTokens.isKnown, isFalse);
      expect(result.limits!.supportsImageInput.isKnown, isFalse);
      expect(
        result.limits!.contextSemantics,
        ContextSemantics.unknown,
        reason: 'семантика окна не выводится из неверных данных',
      );
    });
  });

  group('OpenAI-совместимый: пустой список и неверный тип', () {
    test('пустой data — успех, модель не найдена', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'data': <Object?>[],
        }),
      );
      final DiscoveryResult result = await discoveryFor(
        compatible(),
        adapter,
      ).discover(compatible());
      expect(result.status, DiscoveryStatus.success);
      expect(result.models, isEmpty);
      expect(result.warnings, contains('model_not_in_list'));
      expect(result.limits!.contextTokens.isKnown, isFalse);
    });

    test('data не список — ошибка parse, без исключения', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'data': <String, Object?>{'id': 'test-model'},
        }),
      );
      final DiscoveryResult result = await discoveryFor(
        compatible(),
        adapter,
      ).discover(compatible());
      expect(result.status, DiscoveryStatus.error);
      expect(result.errorCode, 'no_data');
    });
  });
}

Future<String?> _testKey(String accountId) async => 'test-key';
Future<String?> _absentKey(String accountId) async => null;
