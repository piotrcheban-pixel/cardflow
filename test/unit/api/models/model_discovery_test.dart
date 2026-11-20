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

/// Discovery характеристик модели (ADR-039 §3): mock-HTTP и фикстуры из
/// `test/fixtures/discovery/`.
void main() {
  const ApiKeyReader keyReader = _testKey;
  String fixture(String path) =>
      File('test/fixtures/discovery/$path').readAsStringSync();

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

  ProviderAccount account({
    ProviderProtocol protocol = ProviderProtocol.openaiCompletions,
    String preset = 'deepseek',
    String baseUrl = 'https://api.example.com',
    String model = 'test-model',
    bool requiresKey = true,
  }) => ProviderAccount(
    id: 'acc',
    label: 'Acc',
    protocol: protocol,
    baseUrl: baseUrl,
    modelId: model,
    presetId: preset,
    requiresApiKey: requiresKey,
  );

  group('OpenAI-совместимый: политика доверия полям', () {
    test('idsOnly: список моделей, лимиты не выдумываются', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(
          _decode(fixture('openai_compatible/models_success.json')),
        ),
      );
      final OpenAiCompatibleModelsDiscovery discovery =
          OpenAiCompatibleModelsDiscovery(
            dioWith(adapter),
            readApiKey: keyReader,
            fieldPolicy: OpenAiModelFieldPolicy.idsOnly,
          );
      final DiscoveryResult result = await discovery.discover(account());
      expect(result.status, DiscoveryStatus.success);
      expect(result.models, <String>['deepseek-flash', 'deepseek-chat']);
      expect(result.limits!.contextTokens.isKnown, isFalse);
      expect(result.warnings, contains('provider_fields_not_documented'));
      final RequestOptions request = adapter.requests.single;
      expect(request.uri.toString(), 'https://api.example.com/models');
      expect(request.headers['Authorization'], 'Bearer test-key');
      expect(result.sourceRef, isNot(contains('?')));
    });

    test(
      'documented: поля провайдера принимаются с источником providerApi',
      () async {
        final FakeHttpAdapter adapter = FakeHttpAdapter(
          (RequestOptions options) => jsonResponse(
            _decode(fixture('openai_compatible/models_with_fields.json')),
          ),
        );
        final OpenAiCompatibleModelsDiscovery discovery =
            OpenAiCompatibleModelsDiscovery(
              dioWith(adapter),
              readApiKey: keyReader,
              fieldPolicy: OpenAiModelFieldPolicy.documented,
              defaultSemantics: ContextSemantics.totalInputPlusOutput,
            );
        final DiscoveryResult result = await discovery.discover(account());
        final ModelLimits limits = result.limits!;
        expect(limits.contextTokens.value, 128000);
        expect(limits.contextTokens.source, CapabilitySource.providerApi);
        expect(limits.contextTokens.observedAt, isNotNull);
        expect(limits.maxOutputTokens.value, 8192);
        expect(limits.contextSemantics, ContextSemantics.totalInputPlusOutput);
      },
    );

    test('поля неверного типа и пустые id — не значение', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(
          _decode(fixture('openai_compatible/models_wrong_types.json')),
        ),
      );
      final OpenAiCompatibleModelsDiscovery discovery =
          OpenAiCompatibleModelsDiscovery(
            dioWith(adapter),
            readApiKey: keyReader,
            fieldPolicy: OpenAiModelFieldPolicy.documented,
          );
      final DiscoveryResult result = await discovery.discover(account());
      expect(result.status, DiscoveryStatus.success);
      expect(result.models, <String>['test-model']);
      expect(result.limits!.contextTokens.isKnown, isFalse);
      expect(result.limits!.maxOutputTokens.isKnown, isFalse);
    });

    test('пустой список: успешный ответ, модель не найдена', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(
          _decode(fixture('openai_compatible/models_empty.json')),
        ),
      );
      final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(account());
      expect(result.status, DiscoveryStatus.success);
      expect(result.models, isEmpty);
      expect(result.warnings, contains('model_not_in_list'));
    });

    test('OpenRouter: min(context) и цены за токен → за 1M', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(_decode(fixture('openrouter/models_success.json'))),
      );
      final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
        fieldPolicy: OpenAiModelFieldPolicy.documented,
        defaultSemantics: ContextSemantics.totalInputPlusOutput,
        pricingIsPerToken: true,
      ).discover(account(preset: 'openrouter'));
      final ModelLimits limits = result.limits!;
      expect(limits.contextTokens.value, 128000);
      expect(limits.maxOutputTokens.value, 4096);
      expect(limits.supportsImageInput.value, isTrue);
      expect(limits.pricing.value!.inputPerMillion, closeTo(1.0, 1e-9));
      expect(limits.pricing.value!.outputPerMillion, closeTo(2.0, 1e-9));
      expect(limits.pricing.value!.currency, 'USD');
    });

    test('401 — unauthorized, последнее значение не стирается', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'error': 'unauthorized',
        }, statusCode: 401),
      );
      final Dio dio = dioWith(adapter)..options.validateStatus = (_) => true;
      final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
        dio,
        readApiKey: keyReader,
      ).discover(account());
      expect(
        result.errorCode,
        'unauthorized',
        reason: 'status: ${result.status}',
      );
      expect(result.status, DiscoveryStatus.unauthorized);
      expect(result.keepsPrevious, isTrue);
    });

    test('таймаут — timeout без тела ответа', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => throw DioException(
          requestOptions: options,
          type: DioExceptionType.receiveTimeout,
        ),
      );
      final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
      ).discover(account());
      expect(result.status, DiscoveryStatus.timeout);
      expect(result.errorCode, 'timeout');
    });

    test('нет ключа — unauthorized без сетевого запроса', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{}),
      );
      final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
        dioWith(adapter),
        readApiKey: _absentKey,
      ).discover(account());
      expect(result.status, DiscoveryStatus.unauthorized);
      expect(adapter.requests, isEmpty);
      expect(result.errorCode, 'no_api_key');
    });
  });

  group('Anthropic: пагинация и inputOnly', () {
    test('две страницы after_id, лимиты входа/выхода', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        final String query = options.uri.query;
        return jsonResponse(
          _decode(
            fixture(
              query.contains('after_id=claude-a')
                  ? 'anthropic/page2.json'
                  : 'anthropic/page1.json',
            ),
          ),
        );
      });
      final DiscoveryResult result =
          await AnthropicModelsDiscovery(
            dioWith(adapter),
            readApiKey: keyReader,
          ).discover(
            account(
              protocol: ProviderProtocol.anthropicMessages,
              preset: 'anthropic',
              baseUrl: 'https://api.anthropic.com',
            ),
          );
      expect(result.status, DiscoveryStatus.success);
      expect(adapter.requests, hasLength(2));
      expect(result.models, <String>['claude-a', 'test-model']);
      final ModelLimits limits = result.limits!;
      expect(limits.contextSemantics, ContextSemantics.inputOnly);
      expect(limits.maxInputTokens.value, 100000);
      expect(limits.maxOutputTokens.value, 4096);
      expect(limits.maxInputTokens.source, CapabilitySource.providerApi);
      expect(limits.supportsImageInput.isKnown, isFalse);
      expect(result.sourceRef, isNot(contains('?')));
      expect(adapter.requests.first.headers['anthropic-version'], '2023-06-01');
    });
  });

  group('Gemini: пагинация и фильтр методов', () {
    test('pageToken, name без models/, только generateContent', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        final String query = options.uri.query;
        return jsonResponse(
          _decode(
            fixture(
              query.contains('pageToken=page2')
                  ? 'gemini/page2.json'
                  : 'gemini/page1.json',
            ),
          ),
        );
      });
      final DiscoveryResult result =
          await GeminiModelsDiscovery(
            dioWith(adapter),
            readApiKey: keyReader,
          ).discover(
            account(
              protocol: ProviderProtocol.geminiGenerateContent,
              preset: 'gemini',
              baseUrl: 'https://generativelanguage.googleapis.com',
            ),
          );
      expect(result.status, DiscoveryStatus.success);
      expect(adapter.requests, hasLength(2));
      expect(result.models, <String>['gemini-test', 'test-model']);
      expect(result.limits!.maxInputTokens.value, 32768);
      expect(result.limits!.maxOutputTokens.value, 2048);
      expect(adapter.requests.first.headers['x-goog-api-key'], 'test-key');
    });
  });

  group('Ollama: нативные теги и model_info', () {
    test('context_length и vision из /api/show', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        if (options.path.contains('/api/tags')) {
          return jsonResponse(_decode(fixture('ollama/tags.json')));
        }
        return jsonResponse(_decode(fixture('ollama/show.json')));
      });
      final DiscoveryResult result =
          await OllamaModelsDiscovery(
            dioWith(adapter),
            readApiKey: _absentKey,
          ).discover(
            account(
              preset: 'ollama',
              baseUrl: 'http://localhost:11434',
              model: 'test-model',
              requiresKey: false,
            ),
          );
      expect(result.status, DiscoveryStatus.success);
      expect(result.limits!.contextTokens.value, 8192);
      expect(result.limits!.supportsImageInput.value, isTrue);
      expect(result.warnings, contains('ollama_num_ctx_assumption'));
      expect(adapter.requests, hasLength(2));
    });

    test('модели нет локально — только теги, без показа', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) =>
            jsonResponse(_decode(fixture('ollama/tags.json'))),
      );
      final DiscoveryResult result =
          await OllamaModelsDiscovery(
            dioWith(adapter),
            readApiKey: _absentKey,
          ).discover(
            account(
              preset: 'ollama',
              baseUrl: 'http://localhost:11434',
              model: 'missing',
              requiresKey: false,
            ),
          );
      expect(adapter.requests, hasLength(1));
      expect(result.warnings, contains('model_not_in_list'));
      expect(result.limits!.contextTokens.isKnown, isFalse);
    });
  });

  group('7.18.1 §3: сверка с официальной документацией 2026-11-21', () {
    test(
      'DeepSeek: input_modalities модели → Vision без догадок по имени',
      () async {
        final FakeHttpAdapter adapter = FakeHttpAdapter(
          (RequestOptions options) => jsonResponse(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'test-model',
                'context_window': 128000,
                'max_output_tokens': 8192,
                'input_modalities': <Object?>['text', 'image'],
              },
            ],
          }),
        );
        final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
          dioWith(adapter),
          readApiKey: keyReader,
          fieldPolicy: OpenAiModelFieldPolicy.documented,
          defaultSemantics: ContextSemantics.totalInputPlusOutput,
        ).discover(account());
        expect(result.limits!.contextTokens.value, 128000);
        expect(result.limits!.maxOutputTokens.value, 8192);
        expect(result.limits!.supportsImageInput.value, isTrue);
      },
    );

    test(
      'Anthropic: capabilities.image_input — документированное поле',
      () async {
        final FakeHttpAdapter adapter = FakeHttpAdapter(
          (RequestOptions options) => jsonResponse(<String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'test-model',
                'max_input_tokens': 200000,
                'max_tokens': 64000,
                'capabilities': <String, Object?>{
                  'image_input': true,
                  'pdf_input': true,
                  'structured_outputs': true,
                },
              },
            ],
            'has_more': false,
          }),
        );
        final DiscoveryResult result =
            await AnthropicModelsDiscovery(
              dioWith(adapter),
              readApiKey: keyReader,
            ).discover(
              account(
                protocol: ProviderProtocol.anthropicMessages,
                preset: 'anthropic',
                baseUrl: 'https://api.anthropic.com',
              ),
            );
        expect(result.limits!.maxInputTokens.value, 200000);
        expect(result.limits!.maxOutputTokens.value, 64000);
        expect(result.limits!.supportsImageInput.value, isTrue);
        expect(result.limits!.supportsPdfInput.value, isTrue);
      },
    );

    test('Moonshot: supports_image_in и supports_reasoning', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{
              'id': 'test-model',
              'context_length': 262144,
              'supports_image_in': true,
              'supports_reasoning': true,
            },
          ],
        }),
      );
      final DiscoveryResult result =
          await OpenAiCompatibleModelsDiscovery(
            dioWith(adapter),
            readApiKey: keyReader,
            fieldPolicy: OpenAiModelFieldPolicy.documented,
          ).discover(
            account(preset: 'moonshot', baseUrl: 'https://api.moonshot.ai'),
          );
      expect(result.limits!.contextTokens.value, 262144);
      expect(result.limits!.supportsImageInput.value, isTrue);
      expect(result.limits!.isReasoningModel.value, isTrue);
      expect(result.limits!.contextSemantics, ContextSemantics.unknown);
    });

    test('Ollama: семантика окна неизвестна (не догадка total)', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter((RequestOptions options) {
        if (options.path.contains('/api/tags')) {
          return jsonResponse(_decode(fixture('ollama/tags.json')));
        }
        return jsonResponse(_decode(fixture('ollama/show.json')));
      });
      final DiscoveryResult result =
          await OllamaModelsDiscovery(
            dioWith(adapter),
            readApiKey: _absentKey,
          ).discover(
            account(
              preset: 'ollama',
              baseUrl: 'http://localhost:11434',
              requiresKey: false,
            ),
          );
      expect(result.limits!.contextTokens.value, 8192);
      expect(result.limits!.contextSemantics, ContextSemantics.unknown);
    });

    test('имя модели не даёт лимита: foo-128k остаётся unknown', () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (RequestOptions options) => jsonResponse(<String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': 'foo-128k'},
          ],
        }),
      );
      final DiscoveryResult result = await OpenAiCompatibleModelsDiscovery(
        dioWith(adapter),
        readApiKey: keyReader,
        fieldPolicy: OpenAiModelFieldPolicy.documented,
      ).discover(account(preset: 'custom-server', model: 'foo-128k'));
      expect(result.limits!.contextTokens.isKnown, isFalse);
      expect(result.limits!.maxOutputTokens.isKnown, isFalse);
      expect(result.limits!.supportsImageInput.isKnown, isFalse);
    });
  });
}

Map<String, Object?> _decode(String text) {
  final Object? decoded = jsonDecode(text);
  return decoded is Map ? decoded.cast<String, Object?>() : <String, Object?>{};
}

Future<String?> _testKey(String accountId) async => 'test-key';
Future<String?> _absentKey(String accountId) async => null;
