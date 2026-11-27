import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/provider_result.dart';
import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

/// Срез 5, п. 1: адаптеры не переписываются, но их исходы нормализуются в
/// единый [ProviderResult]: контент, причина остановки, расход, отказ и код
/// ошибки — в одном типе и одинаково для всех четырёх протоколов.
void main() {
  const ProviderResponseNormalizer normalizer = ProviderResponseNormalizer();
  const String cardsJson = '{"cards":[],"source_exhausted":false}';

  group('успешный ответ любого протокола даёт одинаковый результат', () {
    final Map<String, GenerationProviderAdapter> adapters =
        <String, GenerationProviderAdapter>{
          'OpenAI-совместимый': const OpenAiCompatibleAdapter(),
          'OpenAI': const OpenAiAdapter(),
          'Gemini': const GeminiAdapter(),
          'Anthropic': const AnthropicAdapter(),
        };
    final Map<String, Map<String, Object?>> fixtures =
        <String, Map<String, Object?>>{
          'OpenAI-совместимый': _openAiCompatible(cardsJson),
          'OpenAI': _openAiCompatible(cardsJson),
          'Gemini': _gemini(cardsJson),
          'Anthropic': _anthropic(cardsJson),
        };

    for (final MapEntry<String, GenerationProviderAdapter> entry
        in adapters.entries) {
      test('${entry.key}: контент, stop и usage', () {
        final ProviderResult result = normalizer.normalize(
          entry.value,
          fixtures[entry.key]!,
        );

        expect(result.content, cardsJson);
        expect(result.finishReason, ProviderFinishReason.stop);
        expect(result.isError, isFalse);
        expect(result.hasContent, isTrue);
        expect(result.rawError, isNull);
        expect(result.usage.promptTokens, 10);
        expect(result.usage.completionTokens, 5);
      });
    }
  });

  group('обрезка по лимиту вывода', () {
    test('OpenAI-совместимый: finish_reason length → length + контент', () {
      final ProviderResult result = normalizer.normalize(
        const OpenAiCompatibleAdapter(),
        _openAiCompatible(cardsJson, finishReason: 'length'),
      );

      expect(result.finishReason, ProviderFinishReason.length);
      expect(result.isTruncated, isTrue);
      expect(result.isError, isFalse);
      expect(result.content, cardsJson);
    });

    test('Gemini: MAX_TOKENS → length', () {
      final ProviderResult result = normalizer.normalize(
        const GeminiAdapter(),
        _gemini(cardsJson, finishReason: 'MAX_TOKENS'),
      );

      expect(result.finishReason, ProviderFinishReason.length);
      expect(result.usage.totalTokens, 15);
    });

    test('Anthropic: max_tokens без tool_use → length, контента нет', () {
      final ProviderResult result = normalizer.normalize(
        const AnthropicAdapter(),
        <String, Object?>{
          'content': <Object?>[
            <String, Object?>{'type': 'text', 'text': 'обрезано'},
          ],
          'stop_reason': 'max_tokens',
          'usage': <String, Object?>{'input_tokens': 10, 'output_tokens': 5},
        },
      );

      expect(result.finishReason, ProviderFinishReason.length);
      expect(result.isError, isTrue);
      expect(result.rawError, GenerationErrorCode.truncated);
      // Адаптер бросает до разбора `usage`: расхода в ошибке нет — не выдумываем.
      expect(result.usage.promptTokens, isNull);
    });
  });

  group('отказ и пустой ответ', () {
    test('refusal модели → refusal, без контента, код refused', () {
      final ProviderResult result = normalizer.normalize(
        const OpenAiCompatibleAdapter(),
        <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'content': null,
                'refusal': 'Не могу помочь с этим запросом',
              },
              'finish_reason': 'stop',
            },
          ],
        },
      );

      expect(result.refusal, isTrue);
      expect(result.finishReason, ProviderFinishReason.refusal);
      expect(result.rawError, GenerationErrorCode.refused);
      expect(result.hasContent, isFalse);
    });

    test('пустой контент → empty, код emptyResponse', () {
      final ProviderResult result = normalizer.normalize(
        const OpenAiCompatibleAdapter(),
        <String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': '   '},
              'finish_reason': 'stop',
            },
          ],
        },
      );

      expect(result.finishReason, ProviderFinishReason.empty);
      expect(result.rawError, GenerationErrorCode.emptyResponse);
    });

    test('ответ не по протоколу → error, код invalidResponse', () {
      final ProviderResult result = normalizer.normalize(
        const OpenAiCompatibleAdapter(),
        <String, Object?>{'error': 'nope'},
      );

      expect(result.finishReason, ProviderFinishReason.error);
      expect(result.rawError, GenerationErrorCode.invalidResponse);
      expect(result.hasContent, isFalse);
    });
  });

  group('сбой транспорта', () {
    test('ошибка провайдера становится результатом с кодом', () {
      final ProviderResult result = normalizer.fromFailure(
        const GenerationException(
          GenerationErrorCode.serverUnavailable,
          details: 'HTTP 503',
        ),
      );

      expect(result.finishReason, ProviderFinishReason.error);
      expect(result.rawError, GenerationErrorCode.serverUnavailable);
      expect(result.detail, 'HTTP 503');
    });

    test('отмена пробрасывается: прогон останавливается', () {
      expect(
        () => normalizer.normalize(
          _ThrowingAdapter(
            const GenerationException(GenerationErrorCode.cancelled),
          ),
          <String, Object?>{},
        ),
        throwsA(
          isA<GenerationException>().having(
            (GenerationException error) => error.code,
            'code',
            GenerationErrorCode.cancelled,
          ),
        ),
      );
    });
  });
}

Map<String, Object?> _openAiCompatible(
  String content, {
  String finishReason = 'stop',
}) => <String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{'content': content},
      'finish_reason': finishReason,
    },
  ],
  'usage': <String, Object?>{
    'prompt_tokens': 10,
    'completion_tokens': 5,
    'total_tokens': 15,
  },
};

Map<String, Object?> _gemini(String content, {String finishReason = 'STOP'}) =>
    <String, Object?>{
      'candidates': <Object?>[
        <String, Object?>{
          'content': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': content},
            ],
          },
          'finishReason': finishReason,
        },
      ],
      'usageMetadata': <String, Object?>{
        'promptTokenCount': 10,
        'candidatesTokenCount': 5,
        'totalTokenCount': 15,
      },
    };

Map<String, Object?> _anthropic(String content) => <String, Object?>{
  'content': <Object?>[
    <String, Object?>{
      'type': 'tool_use',
      'name': 'emit_cards',
      'input': jsonDecode(content),
    },
  ],
  'stop_reason': 'tool_use',
  'usage': <String, Object?>{'input_tokens': 10, 'output_tokens': 5},
};

class _ThrowingAdapter implements GenerationProviderAdapter {
  _ThrowingAdapter(this.error);

  final GenerationException error;

  @override
  GenerationProvider get provider => GenerationProvider.openaiCompatible;

  @override
  ProviderRequest buildRequest({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContent,
    required int maxOutputTokens,
    String? baseUrl,
    bool strictSchema = true,
    bool sendMaxTokens = true,
    List<GenerationAttachment> images = const <GenerationAttachment>[],
    Map<String, Object?>? responseSchema,
  }) => throw UnimplementedError();

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) => throw error;
}
