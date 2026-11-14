import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/api/providers/provider_endpoint.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Итерация 7.5 (ADR-020): адрес запроса из протокола и базового адреса
/// аккаунта; все адаптеры уважают `baseUrl` аккаунта.
void main() {
  group('ProviderEndpoint', () {
    test('OpenAI-совместимый: путь chat/completions из каталога', () {
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.openaiCompletions,
          baseUrl: 'https://api.deepseek.com',
          model: 'deepseek-chat',
        ).uri.toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.openaiCompletions,
          baseUrl: 'https://openrouter.ai/api/v1/',
          model: 'x',
        ).uri.toString(),
        'https://openrouter.ai/api/v1/chat/completions',
      );
    });

    test('OpenAI-совместимый: пустой/битый адрес — причина отказа', () {
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.openaiCompletions,
          baseUrl: '',
          model: 'm',
        ).error,
        ProviderEndpointError.empty,
      );
      for (final String bad in <String>[
        'example.com',
        'ftp://x.test',
        'https://user:pass@x.test',
        'https://x.test/?q=1',
      ]) {
        expect(
          ProviderEndpoint.parse(
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: bad,
            model: 'm',
          ).error,
          ProviderEndpointError.invalid,
          reason: bad,
        );
      }
    });

    test('OpenAI: официальный адрес по умолчанию и свой', () {
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.openai,
          baseUrl: '',
          model: 'gpt-4o-mini',
        ).uri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.openai,
          baseUrl: 'https://proxy.test/openai',
          model: 'gpt-4o-mini',
        ).uri.toString(),
        'https://proxy.test/openai/chat/completions',
      );
    });

    test('Anthropic: путь /v1/messages не дублируется', () {
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.anthropicMessages,
          baseUrl: '',
          model: 'claude-3-5-haiku-latest',
        ).uri.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.anthropicMessages,
          baseUrl: 'https://api.anthropic.com/v1/messages',
          model: 'claude-3-5-haiku-latest',
        ).uri.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.anthropicMessages,
          baseUrl: 'https://proxy.test/anthropic',
          model: 'claude-3-5-haiku-latest',
        ).uri.toString(),
        'https://proxy.test/anthropic/v1/messages',
      );
    });

    test('Gemini: модель входит в путь, свой адрес поддерживается', () {
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.geminiGenerateContent,
          baseUrl: '',
          model: 'gemini-2.0-flash',
        ).uri.toString(),
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.0-flash:generateContent',
      );
      expect(
        ProviderEndpoint.parse(
          protocol: ProviderProtocol.geminiGenerateContent,
          baseUrl: 'https://proxy.test/gemini',
          model: 'gemini-2.5-flash',
        ).uri.toString(),
        'https://proxy.test/gemini/v1beta/models/'
        'gemini-2.5-flash:generateContent',
      );
    });
  });

  group('Адаптеры уважают базовый адрес аккаунта (ADR-020)', () {
    ProviderRequest build(
      GenerationProviderAdapter adapter,
      String model, {
      String? baseUrl,
      String apiKey = 'key',
    }) {
      return adapter.buildRequest(
        apiKey: apiKey,
        model: model,
        systemPrompt: 'system',
        userContent: 'user',
        maxOutputTokens: 8,
        baseUrl: baseUrl,
      );
    }

    test('OpenAI-совместимый адаптер: адрес обязателен', () {
      expect(
        build(
          const OpenAiCompatibleAdapter(),
          'deepseek-chat',
          baseUrl: 'https://api.deepseek.com',
        ).uri.toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        () => build(const OpenAiCompatibleAdapter(), 'm', baseUrl: 'nope'),
        throwsArgumentError,
      );
    });

    test('нативные адаптеры: официальный адрес по умолчанию', () {
      expect(
        build(const OpenAiAdapter(), 'gpt-4o-mini').uri.toString(),
        'https://api.openai.com/v1/chat/completions',
      );
      expect(
        build(
          const AnthropicAdapter(),
          'claude-3-5-haiku-latest',
        ).uri.toString(),
        'https://api.anthropic.com/v1/messages',
      );
      expect(
        build(const GeminiAdapter(), 'gemini-2.0-flash').uri.toString(),
        contains('generativelanguage.googleapis.com/v1beta/models/'),
      );
    });

    test('нативные адаптеры: свой базовый адрес (прокси/шлюз)', () {
      expect(
        build(
          const OpenAiAdapter(),
          'gpt-4o-mini',
          baseUrl: 'https://proxy.test/openai',
        ).uri.toString(),
        'https://proxy.test/openai/chat/completions',
      );
      expect(
        build(
          const AnthropicAdapter(),
          'claude-3-5-haiku-latest',
          baseUrl: 'https://proxy.test/anthropic',
        ).uri.toString(),
        'https://proxy.test/anthropic/v1/messages',
      );
      expect(
        build(
          const GeminiAdapter(),
          'gemini-2.0-flash',
          baseUrl: 'https://proxy.test/gemini',
        ).uri.toString(),
        'https://proxy.test/gemini/v1beta/models/'
        'gemini-2.0-flash:generateContent',
      );
    });

    test('ключ не попадает в URL, только в заголовок', () {
      final ProviderRequest request = build(
        const OpenAiCompatibleAdapter(),
        'deepseek-chat',
        baseUrl: 'https://api.deepseek.com',
        apiKey: 'secret-key',
      );
      expect(request.uri.toString(), isNot(contains('secret-key')));
      expect(request.headers['Authorization'], 'Bearer secret-key');
    });
  });
}
