import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/api/providers/provider_json.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// Красная фаза итерации 3b: адаптеры OpenAI / Gemini / Anthropic (SPEC A8.2).
void main() {
  Matcher throwsGeneration(GenerationErrorCode code) => throwsA(
    isA<GenerationException>().having(
      (exception) => exception.code,
      'code',
      code,
    ),
  );

  GenerationAttachment imageAttachment() => GenerationAttachment(
    fileName: 'схема.png',
    mediaType: AttachmentMediaType.png,
    bytes: Uint8List.fromList(<int>[1, 2, 3]),
  );

  GenerationAttachment pdfAttachment() => GenerationAttachment(
    fileName: 'скан.pdf',
    mediaType: AttachmentMediaType.pdf,
    bytes: Uint8List.fromList(<int>[4, 5, 6]),
  );

  group('OpenAI adapter', () {
    const adapter = OpenAiAdapter();
    late ProviderRequest request;
    setUp(() {
      request = adapter.buildRequest(
        apiKey: 'test-key-openai',
        model: 'gpt-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        maxOutputTokens: 4096,
      );
    });

    test('provider = openai и endpoint Chat Completions', () {
      expect(adapter.provider, GenerationProvider.openai);
      expect(
        request.uri,
        Uri.parse('https://api.openai.com/v1/chat/completions'),
      );
      expect(request.headers['Authorization'], 'Bearer test-key-openai');
      expect(request.headers['Content-Type'], 'application/json');
    });

    test('body: model, system+user сообщения, strict json_schema', () {
      expect(request.body['model'], 'gpt-test');
      final messages = request.body['messages']! as List<Object?>;
      expect(messages, hasLength(2));
      expect((messages[0]! as Map<String, Object?>)['role'], 'system');
      expect(
        (messages[0]! as Map<String, Object?>)['content'],
        'СИСТЕМНЫЙ ПРОМПТ',
      );
      expect((messages[1]! as Map<String, Object?>)['role'], 'user');
      expect(
        (messages[1]! as Map<String, Object?>)['content'],
        'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
      );
      final format = request.body['response_format']! as Map<String, Object?>;
      expect(format['type'], 'json_schema');
      final strict = format['json_schema']! as Map<String, Object?>;
      expect(strict['name'], 'cards_response');
      expect(strict['strict'], isTrue);
      expect(strict['schema'], openAiStrictCardSchema());
      expect(request.body.containsKey('max_tokens'), isFalse);
      expect(jsonEncode(request.body), isNotEmpty);
    });

    test('image part: data URI base64 в content пользователя', () {
      final withImage = adapter.buildRequest(
        apiKey: 'test-key-openai',
        model: 'gpt-4o',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        maxOutputTokens: 4096,
        images: <GenerationAttachment>[imageAttachment()],
      );
      final messages = withImage.body['messages']! as List<Object?>;
      final user = messages[1]! as Map<String, Object?>;
      final content = user['content']! as List<Object?>;
      expect(content, hasLength(2));
      expect((content[0]! as Map<String, Object?>)['type'], 'text');
      expect(
        (content[0]! as Map<String, Object?>)['text'],
        'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
      );
      final image = content[1]! as Map<String, Object?>;
      expect(image['type'], 'image_url');
      final imageUrl = image['image_url']! as Map<String, Object?>;
      expect(imageUrl['url'], 'data:image/png;base64,AQID');
    });

    test('PDF-скан в OpenAI Chat Completions → pdfScanUnsupported', () {
      expect(
        () => adapter.buildRequest(
          apiKey: 'test-key-openai',
          model: 'gpt-4o',
          systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
          userContent: 'ТЕКСТ',
          maxOutputTokens: 4096,
          images: <GenerationAttachment>[pdfAttachment()],
        ),
        throwsGeneration(GenerationErrorCode.pdfScanUnsupported),
      );
    });

    test('ответ: content → cardsJson, usage', () {
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
      expect(response.usage.promptTokens, 11);
      expect(response.usage.completionTokens, 22);
      expect(response.usage.totalTokens, 33);
    });

    test('refusal → refused', () {
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
    });

    test('finish_reason length → truncated', () {
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{'content': '{"cards":['},
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

    test('нет choices/content не строка → invalidResponse', () {
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

  group('Gemini adapter', () {
    const adapter = GeminiAdapter();
    late ProviderRequest request;
    setUp(() {
      request = adapter.buildRequest(
        apiKey: 'test-key-gemini',
        model: 'gemini-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        maxOutputTokens: 4096,
      );
    });

    test('provider = gemini, endpoint с моделью, ключ только в заголовке', () {
      expect(adapter.provider, GenerationProvider.gemini);
      expect(
        request.uri,
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/'
          'gemini-test:generateContent',
        ),
      );
      expect(request.headers['x-goog-api-key'], 'test-key-gemini');
      expect(request.uri.toString(), isNot(contains('test-key-gemini')));
    });

    test(
      'body: systemInstruction, contents, responseMimeType/responseSchema',
      () {
        final system =
            request.body['systemInstruction']! as Map<String, Object?>;
        final systemParts = system['parts']! as List<Object?>;
        expect(
          (systemParts.single! as Map<String, Object?>)['text'],
          'СИСТЕМНЫЙ ПРОМПТ',
        );

        final contents = request.body['contents']! as List<Object?>;
        final user = contents.single! as Map<String, Object?>;
        expect(user['role'], 'user');
        final parts = user['parts']! as List<Object?>;
        expect(
          (parts.single! as Map<String, Object?>)['text'],
          'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        );

        final config =
            request.body['generationConfig']! as Map<String, Object?>;
        expect(config['responseMimeType'], 'application/json');
        expect(config['responseSchema'], geminiCardSchema());
        expect(jsonEncode(request.body), isNotEmpty);
      },
    );

    test('image part: inlineData с mimeType и base64', () {
      final withImage = adapter.buildRequest(
        apiKey: 'test-key-gemini',
        model: 'gemini-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        maxOutputTokens: 4096,
        images: <GenerationAttachment>[imageAttachment()],
      );
      final contents = withImage.body['contents']! as List<Object?>;
      final parts =
          (contents.single! as Map<String, Object?>)['parts']! as List<Object?>;
      expect(parts, hasLength(2));
      expect(
        (parts[0]! as Map<String, Object?>)['text'],
        'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
      );
      final inline =
          (parts[1]! as Map<String, Object?>)['inlineData']!
              as Map<String, Object?>;
      expect(inline['mimeType'], 'image/png');
      expect(inline['data'], 'AQID');
    });

    test('PDF-скан: inlineData application/pdf', () {
      final withPdf = adapter.buildRequest(
        apiKey: 'test-key-gemini',
        model: 'gemini-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ТЕКСТ',
        maxOutputTokens: 4096,
        images: <GenerationAttachment>[pdfAttachment()],
      );
      final contents = withPdf.body['contents']! as List<Object?>;
      final parts =
          (contents.single! as Map<String, Object?>)['parts']! as List<Object?>;
      final inline =
          (parts[1]! as Map<String, Object?>)['inlineData']!
              as Map<String, Object?>;
      expect(inline['mimeType'], 'application/pdf');
      expect(inline['data'], 'BAUG');
    });

    test('ответ: candidates[0].content.parts[].text и usageMetadata', () {
      final response = adapter.parseResponse(<String, Object?>{
        'candidates': <Object?>[
          <String, Object?>{
            'content': <String, Object?>{
              'parts': <Object?>[
                <String, Object?>{'text': '{"cards":[]}'},
              ],
            },
            'finishReason': 'STOP',
          },
        ],
        'usageMetadata': <String, Object?>{
          'promptTokenCount': 7,
          'candidatesTokenCount': 8,
          'totalTokenCount': 15,
        },
      });
      expect(response.cardsJson, '{"cards":[]}');
      expect(response.usage.promptTokens, 7);
      expect(response.usage.completionTokens, 8);
      expect(response.usage.totalTokens, 15);
    });

    test('finishReason MAX_TOKENS → truncated', () {
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': '{"cards":['},
                ],
              },
              'finishReason': 'MAX_TOKENS',
            },
          ],
        }),
        throwsGeneration(GenerationErrorCode.truncated),
      );
    });

    test('safety finishReason и blockReason → refused', () {
      for (final reason in <String>[
        'SAFETY',
        'RECITATION',
        'BLOCKLIST',
        'PROHIBITED_CONTENT',
        'SPII',
      ]) {
        expect(
          () => adapter.parseResponse(<String, Object?>{
            'candidates': <Object?>[
              <String, Object?>{
                'content': <String, Object?>{'parts': <Object?>[]},
                'finishReason': reason,
              },
            ],
          }),
          throwsGeneration(GenerationErrorCode.refused),
          reason: reason,
        );
      }
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'promptFeedback': <String, Object?>{'blockReason': 'SAFETY'},
        }),
        throwsGeneration(GenerationErrorCode.refused),
      );
    });

    test('пустые candidates/текст → emptyResponse', () {
      for (final payload in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'candidates': <Object?>[]},
        <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{'parts': <Object?>[]},
            },
          ],
        },
        <String, Object?>{
          'candidates': <Object?>[
            <String, Object?>{
              'content': <String, Object?>{
                'parts': <Object?>[
                  <String, Object?>{'text': ''},
                ],
              },
            },
          ],
        },
      ]) {
        expect(
          () => adapter.parseResponse(payload),
          throwsGeneration(GenerationErrorCode.emptyResponse),
          reason: 'payload=$payload',
        );
      }
    });
  });

  group('Anthropic adapter', () {
    const adapter = AnthropicAdapter();
    late ProviderRequest request;
    setUp(() {
      request = adapter.buildRequest(
        apiKey: 'test-key-anthropic',
        model: 'claude-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        maxOutputTokens: 4096,
      );
    });

    test('provider = anthropic, endpoint, ключ и версия API в заголовках', () {
      expect(adapter.provider, GenerationProvider.anthropic);
      expect(request.uri, Uri.parse('https://api.anthropic.com/v1/messages'));
      expect(request.headers['x-api-key'], 'test-key-anthropic');
      expect(request.headers['anthropic-version'], '2023-06-01');
    });

    test('body: model/max_tokens/system/messages/tools/tool_choice', () {
      expect(request.body['model'], 'claude-test');
      expect(request.body['max_tokens'], 4096);
      expect(request.body['system'], 'СИСТЕМНЫЙ ПРОМПТ');
      final messages = request.body['messages']! as List<Object?>;
      final user = messages.single! as Map<String, Object?>;
      expect(user['role'], 'user');
      expect(user['content'], 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ');

      final tools = request.body['tools']! as List<Object?>;
      final tool = tools.single! as Map<String, Object?>;
      expect(tool['name'], 'emit_cards');
      expect((tool['description']! as String).trim(), isNotEmpty);
      expect(tool['input_schema'], anthropicToolCardSchema());

      expect(request.body['tool_choice'], <String, Object?>{
        'type': 'tool',
        'name': 'emit_cards',
      });
      expect(jsonEncode(request.body), isNotEmpty);
    });

    test('image part: блок image с base64-источником', () {
      final withImage = adapter.buildRequest(
        apiKey: 'test-key-anthropic',
        model: 'claude-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ПОЛЬЗОВАТЕЛЬСКИЙ ТЕКСТ',
        maxOutputTokens: 4096,
        images: <GenerationAttachment>[imageAttachment()],
      );
      final messages = withImage.body['messages']! as List<Object?>;
      final user = messages.single! as Map<String, Object?>;
      final content = user['content']! as List<Object?>;
      expect(content, hasLength(2));
      expect((content[0]! as Map<String, Object?>)['type'], 'text');
      final image = content[1]! as Map<String, Object?>;
      expect(image['type'], 'image');
      final source = image['source']! as Map<String, Object?>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'image/png');
      expect(source['data'], 'AQID');
    });

    test('PDF-скан: блок document с application/pdf', () {
      final withPdf = adapter.buildRequest(
        apiKey: 'test-key-anthropic',
        model: 'claude-test',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ТЕКСТ',
        maxOutputTokens: 4096,
        images: <GenerationAttachment>[pdfAttachment()],
      );
      final messages = withPdf.body['messages']! as List<Object?>;
      final user = messages.single! as Map<String, Object?>;
      final content = user['content']! as List<Object?>;
      final document = content[1]! as Map<String, Object?>;
      expect(document['type'], 'document');
      final source = document['source']! as Map<String, Object?>;
      expect(source['type'], 'base64');
      expect(source['media_type'], 'application/pdf');
      expect(source['data'], 'BAUG');
      expect(withPdf.headers['anthropic-beta'], 'pdfs-2024-09-25');
    });

    test('ответ: tool_use emit_cards → cardsJson и usage', () {
      final response = adapter.parseResponse(<String, Object?>{
        'content': <Object?>[
          <String, Object?>{
            'type': 'tool_use',
            'id': 'toolu_1',
            'name': 'emit_cards',
            'input': <String, Object?>{'cards': <Object?>[]},
          },
        ],
        'stop_reason': 'tool_use',
        'usage': <String, Object?>{'input_tokens': 9, 'output_tokens': 4},
      });
      expect(jsonDecode(response.cardsJson), <String, Object?>{
        'cards': <Object?>[],
      });
      expect(response.usage.promptTokens, 9);
      expect(response.usage.completionTokens, 4);
      expect(response.usage.totalTokens, 13);
    });

    test('stop_reason max_tokens → truncated', () {
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'content': <Object?>[],
          'stop_reason': 'max_tokens',
        }),
        throwsGeneration(GenerationErrorCode.truncated),
      );
    });

    test('stop_reason refusal → refused', () {
      expect(
        () => adapter.parseResponse(<String, Object?>{
          'content': <Object?>[],
          'stop_reason': 'refusal',
        }),
        throwsGeneration(GenerationErrorCode.refused),
      );
    });

    test('нет tool_use с emit_cards → invalidResponse', () {
      for (final content in <List<Object?>>[
        <Object?>[],
        <Object?>[
          <String, Object?>{'type': 'text', 'text': 'вот карточки'},
        ],
        <Object?>[
          <String, Object?>{
            'type': 'tool_use',
            'name': 'other_tool',
            'input': <String, Object?>{},
          },
        ],
        <Object?>[
          <String, Object?>{
            'type': 'tool_use',
            'name': 'emit_cards',
            'input': 'не объект',
          },
        ],
      ]) {
        expect(
          () => adapter.parseResponse(<String, Object?>{
            'content': content,
            'stop_reason': 'tool_use',
          }),
          throwsGeneration(GenerationErrorCode.invalidResponse),
          reason: 'content=$content',
        );
      }
    });

    test('некорректный envelope → invalidResponse', () {
      for (final payload in <Map<String, Object?>>[
        <String, Object?>{},
        <String, Object?>{'content': 'нет'},
        <String, Object?>{
          'content': <Object?>['нет'],
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

  group('OpenAI-compatible adapter: вложения', () {
    const adapter = OpenAiCompatibleAdapter();

    test('image part кодируется так же, как в OpenAI', () {
      final request = adapter.buildRequest(
        apiKey: '',
        model: 'vision-model',
        systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
        userContent: 'ТЕКСТ',
        maxOutputTokens: 4096,
        baseUrl: 'http://localhost:1234/v1',
        images: <GenerationAttachment>[imageAttachment()],
      );
      final messages = request.body['messages']! as List<Object?>;
      final user = messages[1]! as Map<String, Object?>;
      final content = user['content']! as List<Object?>;
      final image = content[1]! as Map<String, Object?>;
      expect(image['type'], 'image_url');
      expect(
        (image['image_url']! as Map<String, Object?>)['url'],
        'data:image/png;base64,AQID',
      );
    });

    test('PDF-скан → pdfScanUnsupported', () {
      expect(
        () => adapter.buildRequest(
          apiKey: '',
          model: 'vision-model',
          systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
          userContent: 'ТЕКСТ',
          maxOutputTokens: 4096,
          baseUrl: 'http://localhost:1234/v1',
          images: <GenerationAttachment>[pdfAttachment()],
        ),
        throwsGeneration(GenerationErrorCode.pdfScanUnsupported),
      );
    });
  });

  group('общий контракт адаптеров', () {
    test('все четыре провайдера покрыты адаптерами', () {
      const adapters = <GenerationProviderAdapter>[
        OpenAiAdapter(),
        GeminiAdapter(),
        AnthropicAdapter(),
        OpenAiCompatibleAdapter(),
      ];
      expect(
        adapters.map((adapter) => adapter.provider).toSet(),
        GenerationProvider.values.toSet(),
      );
    });

    test('jsonIntOrNull устойчив к нечисловым и неконечным значениям', () {
      expect(jsonIntOrNull(null), isNull);
      expect(jsonIntOrNull('42'), isNull);
      expect(jsonIntOrNull(42), 42);
      expect(jsonIntOrNull(42.0), 42);
      expect(jsonIntOrNull(double.infinity), isNull);
      expect(jsonIntOrNull(double.nan), isNull);
    });

    test('Request/Response — immutable-значения с полями', () {
      final request = ProviderRequest(
        uri: Uri.https('api.test', '/v1'),
        headers: <String, String>{'h': 'v'},
        body: <String, Object?>{'k': 1},
      );
      expect(request.uri.host, 'api.test');
      expect(request.headers['h'], 'v');
      expect(request.body['k'], 1);

      final response = ProviderRawResponse(
        cardsJson: '{}',
        usage: const TokenUsage(),
      );
      expect(response.cardsJson, '{}');
    });
  });
}
