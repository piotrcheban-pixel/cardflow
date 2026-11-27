import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

/// Адаптер OpenAI-совместимого сервера (ADR-013): копия логики OpenAI,
/// но endpoint, модель и необязательный ключ — из настроек.
void main() {
  const adapter = OpenAiCompatibleAdapter();

  ProviderRequest build({
    String apiKey = 'test-key',
    String baseUrl = 'http://localhost:11434/v1',
    bool strictSchema = true,
    bool sendMaxTokens = true,
    int maxOutputTokens = 4096,
  }) {
    return adapter.buildRequest(
      apiKey: apiKey,
      model: 'local-model',
      systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
      userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
      maxOutputTokens: maxOutputTokens,
      baseUrl: baseUrl,
      strictSchema: strictSchema,
      sendMaxTokens: sendMaxTokens,
    );
  }

  Matcher throwsGeneration(GenerationErrorCode code) => throwsA(
    isA<GenerationException>().having(
      (exception) => exception.code,
      'code',
      code,
    ),
  );

  group('buildRequest', () {
    test('provider = openaiCompatible, endpoint из base_url', () {
      expect(adapter.provider, GenerationProvider.openaiCompatible);
      expect(
        build(baseUrl: 'https://api.deepseek.com').uri.toString(),
        'https://api.deepseek.com/chat/completions',
      );
      expect(
        build().uri.toString(),
        'http://localhost:11434/v1/chat/completions',
      );
    });

    test('ключ опционален: пустой → нет Authorization', () {
      for (final key in <String>['', '   ']) {
        final request = build(apiKey: key);
        expect(
          request.headers.containsKey('Authorization'),
          isFalse,
          reason: 'key="$key"',
        );
        expect(request.headers['Content-Type'], 'application/json');
      }
      expect(
        build(apiKey: ' test-key ').headers['Authorization'],
        'Bearer test-key',
      );
    });

    test('body как у OpenAI: model, system+user, strict json_schema', () {
      final request = build();
      expect(request.body['model'], 'local-model');
      final messages = request.body['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect((messages[0]! as Map<String, Object?>)['role'], 'system');
      expect(
        (messages[0]! as Map<String, Object?>)['content'],
        'СИСТЕМНЫЙ ПРОМПТ',
      );
      expect((messages[1]! as Map<String, Object?>)['role'], 'user');
      final format = request.body['response_format']! as Map<String, Object?>;
      expect(format['type'], 'json_schema');
      final strict = format['json_schema']! as Map<String, Object?>;
      expect(strict['name'], 'cards_response');
      expect(strict['strict'], isTrue);
      expect(strict['schema'], openAiStrictCardSchema());
    });

    test('max_tokens передаётся: серверный дефолт DeepSeek (4096) мал', () {
      expect(build().body['max_tokens'], 4096);
      expect(build(maxOutputTokens: 8192).body['max_tokens'], 8192);
    });

    test('fallback без strict: response_format отсутствует, max_tokens нет '
        'только при sendMaxTokens=false', () {
      final withBudget = build(strictSchema: false);
      expect(withBudget.body.containsKey('response_format'), isFalse);
      expect(withBudget.body['max_tokens'], 4096);
      expect(withBudget.body['model'], 'local-model');
      expect(withBudget.body['messages'], hasLength(2));

      final plain = build(strictSchema: false, sendMaxTokens: false);
      expect(plain.body.containsKey('max_tokens'), isFalse);
      expect(plain.body.containsKey('response_format'), isFalse);
    });

    test('некорректный base_url → ArgumentError, запрос не строится', () {
      for (final baseUrl in <String>['', 'ftp://x', 'https://user:pass@x']) {
        expect(
          () => build(baseUrl: baseUrl),
          throwsArgumentError,
          reason: baseUrl,
        );
      }
    });
  });

  group('parseResponse', () {
    test('content → cardsJson, usage', () {
      final response = adapter.parseResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'role': 'assistant',
              'content': '{"cards":[]}',
            },
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, Object?>{
          'prompt_tokens': 11,
          'completion_tokens': 22,
          'total_tokens': 33,
        },
      });
      expect(response.cardsJson, '{"cards":[]}');
      expect(response.usage.totalTokens, 33);
    });

    test('refusal → refused; length → truncated-ответ, не исключение', () {
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'content': null,
                'refusal': 'Не могу помочь',
              },
              'finish_reason': 'stop',
            },
          ],
        }),
        throwsGeneration(GenerationErrorCode.refused),
      );
      // TASK 04: обрыв по лимиту вывода больше не выбрасывает уже полученные
      // карточки — сервис спасает полные карточки из прерванного JSON.
      final response = adapter.parseResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': '{"cards":['},
            'finish_reason': 'length',
          },
        ],
      });
      expect(response.truncated, isTrue);
      expect(response.cardsJson, '{"cards":[');
      // Без контента спасать нечего — остаётся доменная ошибка восстановления.
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': null},
              'finish_reason': 'length',
            },
          ],
        }),
        throwsGeneration(GenerationErrorCode.truncated),
      );
    });

    test('пустой/отсутствующий content → emptyResponse', () {
      for (final content in <Object?>[null, '', '   ']) {
        expect(
          () => adapter.parseResponse(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{'content': content},
                'finish_reason': 'stop',
              },
            ],
          }),
          throwsGeneration(GenerationErrorCode.emptyResponse),
          reason: 'content=$content',
        );
      }
    });

    test('битый envelope → invalidResponse', () {
      for (final payload in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'choices': <Object?>[]},
        <String, Object?>{'choices': 'нет'},
        <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{'message': 'нет'},
          ],
        },
      ]) {
        expect(
          () => adapter.parseResponse(payload),
          throwsGeneration(GenerationErrorCode.invalidResponse),
          reason: 'payload=$payload',
        );
      }
    });
  });
}
