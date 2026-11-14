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
import 'package:cardflow/domain/generation/provider_account.dart';

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

/// Итерация 7.5 (ADR-020): проверка подключения по аккаунту провайдера.
void main() {
  late _FakeTransport transport;
  late FakeApiKeyStore keys;

  ApiKeyVerifier verifier() => ApiKeyVerifier(
    adapters: <GenerationProviderAdapter>[
      const OpenAiAdapter(),
      const GeminiAdapter(),
      const AnthropicAdapter(),
      const OpenAiCompatibleAdapter(),
    ],
    apiKeyStore: keys,
    transport: transport,
  );

  setUp(() {
    transport = _FakeTransport();
    keys = FakeApiKeyStore();
  });

  group('ApiKeyVerifier — каталог провайдеров', () {
    test('ключ не задан — missingKey, запрос не уходит', () async {
      final ApiKeyCheckResult result = await verifier().check(
        testProviderAccount(presetId: 'deepseek'),
      );
      expect(result.status, ApiKeyCheckStatus.missingKey);
      expect(transport.calls, 0);
    });

    test('DeepSeek: ключ из хранилища в заголовке, запрос на api.deepseek.com', () async {
      keys = FakeApiKeyStore(<String, String>{'deepseek': 'sk-deepseek'});
      final ApiKeyCheckResult result = await verifier().check(
        testProviderAccount(presetId: 'deepseek'),
      );
      expect(result.status, ApiKeyCheckStatus.valid);
      expect(transport.calls, 1);
      expect(
        transport.lastRequest!.headers['Authorization'],
        'Bearer sk-deepseek',
      );
      expect(
        transport.lastRequest!.uri.toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(transport.lastRequest!.uri.toString(), isNot(contains('sk-')));
      // Проверка подключения — минимальный совместимый запрос: без strict-схемы
      // и без `max_tokens` (ADR-021).
      expect(transport.lastRequest!.body.containsKey('max_tokens'), isFalse);
      expect(
        transport.lastRequest!.body.containsKey('response_format'),
        isFalse,
      );
    });

    test('Gemini и Anthropic используют свои заголовки и адреса', () async {
      keys = FakeApiKeyStore(<String, String>{
        'gemini': 'key-gemini',
        'anthropic': 'key-anthropic',
      });
      expect(
        (await verifier().check(testProviderAccount(presetId: 'gemini')))
            .status,
        ApiKeyCheckStatus.valid,
      );
      expect(transport.lastRequest!.headers['x-goog-api-key'], 'key-gemini');
      expect(
        transport.lastRequest!.uri.toString(),
        contains('generativelanguage.googleapis.com/v1beta/models/'),
      );

      expect(
        (await verifier().check(testProviderAccount(presetId: 'anthropic')))
            .status,
        ApiKeyCheckStatus.valid,
      );
      expect(transport.lastRequest!.headers['x-api-key'], 'key-anthropic');
      expect(
        transport.lastRequest!.uri.toString(),
        contains('api.anthropic.com/v1/messages'),
      );
    });

    test('ошибки транспорта маппятся в статусы без сырых деталей', () async {
      keys = FakeApiKeyStore(<String, String>{'deepseek': 'sk-deepseek'});
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
          testProviderAccount(presetId: 'deepseek'),
        );
        expect(result.status, entry.value, reason: entry.key.name);
      }
    });

    test('неожиданное исключение — unexpected', () async {
      keys = FakeApiKeyStore(<String, String>{'deepseek': 'sk-deepseek'});
      transport.error = StateError('boom');
      final ApiKeyCheckResult result = await verifier().check(
        testProviderAccount(presetId: 'deepseek'),
      );
      expect(result.status, ApiKeyCheckStatus.unexpected);
    });
  });

  group('ApiKeyVerifier — пользовательский провайдер', () {
    test(
      'неполный аккаунт — providerNotConfigured, запрос не уходит',
      () async {
        final ApiKeyCheckResult result = await verifier().check(
          testCustomProviderAccount(baseUrl: '  '),
        );
        expect(result.status, ApiKeyCheckStatus.providerNotConfigured);
        expect(transport.calls, 0);
      },
    );

    test(
      'локальный сервер без ключа — запрос без Authorization и valid',
      () async {
        final ApiKeyCheckResult result = await verifier().check(
          testCustomProviderAccount(),
        );
        expect(result.status, ApiKeyCheckStatus.valid);
        expect(
          transport.lastRequest!.headers.containsKey('Authorization'),
          isFalse,
        );
        expect(
          transport.lastRequest!.uri.toString(),
          'http://localhost:1234/v1/chat/completions',
        );
        expect(transport.lastRequest!.body['model'], 'qwen2.5');
      },
    );

    test('локальный сервер с ключом — ключ уходит в заголовке', () async {
      final ProviderAccount account = testCustomProviderAccount(id: 'local');
      keys = FakeApiKeyStore(<String, String>{'local': 'sk-local'});
      final ApiKeyCheckResult result = await verifier().check(account);
      expect(result.status, ApiKeyCheckStatus.valid);
      expect(
        transport.lastRequest!.headers['Authorization'],
        'Bearer sk-local',
      );
    });

    test('Ollama из каталога не требует ключа', () async {
      final ApiKeyCheckResult result = await verifier().check(
        testProviderAccount(presetId: 'ollama'),
      );
      expect(result.status, ApiKeyCheckStatus.valid);
      expect(
        transport.lastRequest!.uri.toString(),
        contains('localhost:11434'),
      );
    });
  });
}
