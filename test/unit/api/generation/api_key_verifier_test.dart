import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/api_key_verifier.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

import '../../../helpers/generation_fakes.dart';

/// Транспорт-заглушка: запоминает запрос и отдаёт успех/исключение.
class _FakeTransport implements GenerationTransport {
  ProviderRequest? lastRequest;
  int calls = 0;
  Object? error;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    lastRequest = request;
    final Object? failure = error;
    if (failure != null) throw failure;
    return <String, Object?>{'ok': true};
  }
}

void main() {
  late _FakeTransport transport;
  late FakeApiKeyStore keys;
  late FakeGenerationSettingsStore compatibleSettings;

  ApiKeyVerifier verifier() => ApiKeyVerifier(
    adapters: <GenerationProviderAdapter>[
      const OpenAiAdapter(),
      const GeminiAdapter(),
      const AnthropicAdapter(),
      const OpenAiCompatibleAdapter(),
    ],
    apiKeyStore: keys,
    transport: transport,
    generationSettingsStore: compatibleSettings,
  );

  setUp(() {
    transport = _FakeTransport();
    keys = FakeApiKeyStore();
    compatibleSettings = FakeGenerationSettingsStore();
  });

  group('ApiKeyVerifier — облачные провайдеры', () {
    test('ключ не задан — missingKey, запрос не уходит', () async {
      final ApiKeyCheckResult result = await verifier().check(
        GenerationProvider.openai,
      );
      expect(result.status, ApiKeyCheckStatus.missingKey);
      expect(transport.calls, 0);
    });

    test(
      'ключ принят — valid, ключ в заголовке провайдера (не в URL)',
      () async {
        keys = FakeApiKeyStore(<GenerationProvider, String>{
          GenerationProvider.openai: 'key-openai',
        });
        final ApiKeyCheckResult result = await verifier().check(
          GenerationProvider.openai,
        );
        expect(result.status, ApiKeyCheckStatus.valid);
        expect(transport.calls, 1);
        expect(
          transport.lastRequest!.headers['Authorization'],
          'Bearer key-openai',
        );
        expect(transport.lastRequest!.uri.query, isNot(contains('key-openai')));
      },
    );

    test('Gemini и Anthropic используют свои заголовки', () async {
      keys = FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.gemini: 'key-gemini',
        GenerationProvider.anthropic: 'key-anthropic',
      });
      expect(
        (await verifier().check(GenerationProvider.gemini)).status,
        ApiKeyCheckStatus.valid,
      );
      expect(transport.lastRequest!.headers['x-goog-api-key'], 'key-gemini');

      expect(
        (await verifier().check(GenerationProvider.anthropic)).status,
        ApiKeyCheckStatus.valid,
      );
      expect(transport.lastRequest!.headers['x-api-key'], 'key-anthropic');
    });

    test('ошибки транспорта маппятся в статусы без сырых деталей', () async {
      keys = FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.openai: 'key-openai',
      });
      final Map<GenerationErrorCode, ApiKeyCheckStatus> cases =
          <GenerationErrorCode, ApiKeyCheckStatus>{
            GenerationErrorCode.invalidApiKey: ApiKeyCheckStatus.invalidKey,
            GenerationErrorCode.network: ApiKeyCheckStatus.noConnection,
            GenerationErrorCode.timeout: ApiKeyCheckStatus.noConnection,
            GenerationErrorCode.rateLimited: ApiKeyCheckStatus.rateLimited,
            GenerationErrorCode.serverUnavailable: ApiKeyCheckStatus.unexpected,
          };
      for (final MapEntry<GenerationErrorCode, ApiKeyCheckStatus> entry
          in cases.entries) {
        transport.error = GenerationException(
          entry.key,
          details: 'сырые детали не должны попасть наружу',
        );
        final ApiKeyCheckResult result = await verifier().check(
          GenerationProvider.openai,
        );
        expect(result.status, entry.value, reason: entry.key.name);
      }
    });

    test('неожиданное исключение — unexpected', () async {
      keys = FakeApiKeyStore(<GenerationProvider, String>{
        GenerationProvider.openai: 'key-openai',
      });
      transport.error = StateError('boom');
      final ApiKeyCheckResult result = await verifier().check(
        GenerationProvider.openai,
      );
      expect(result.status, ApiKeyCheckStatus.unexpected);
    });
  });

  group('ApiKeyVerifier — OpenAI-совместимый сервер', () {
    test('сервер не настроен — providerNotConfigured', () async {
      final ApiKeyCheckResult result = await verifier().check(
        GenerationProvider.openaiCompatible,
      );
      expect(result.status, ApiKeyCheckStatus.providerNotConfigured);
      expect(transport.calls, 0);
    });

    test(
      'сервер настроен без ключа — запрос без Authorization и valid',
      () async {
        compatibleSettings = FakeGenerationSettingsStore(
          const OpenAiCompatibleSettings(
            baseUrl: 'http://localhost:11434/v1',
            model: 'qwen2.5',
          ),
        );
        final ApiKeyCheckResult result = await verifier().check(
          GenerationProvider.openaiCompatible,
        );
        expect(result.status, ApiKeyCheckStatus.valid);
        expect(
          transport.lastRequest!.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(
          transport.lastRequest!.uri.toString(),
          contains('localhost:11434'),
        );
        expect(transport.lastRequest!.body['model'], 'qwen2.5');
      },
    );
  });
}
