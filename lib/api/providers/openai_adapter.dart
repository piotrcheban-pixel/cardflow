/// Адаптер OpenAI Chat Completions со strict JSON Schema (SPEC A8.2).
library;

import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/providers/attachment_parts.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/provider_endpoint.dart';
import 'package:cardflow/api/providers/provider_json.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// OpenAI: `POST https://api.openai.com/v1/chat/completions`,
/// `Authorization: Bearer <key>`, `response_format: {type: "json_schema",
/// json_schema: {name: "cards_response", strict: true, schema: …}}`.
///
/// Проверки ответа (A8.2): `choices[0].message.content` (пустой контент →
/// `emptyResponse`), `message.refusal` (→ `refused`),
/// `choices[0].finish_reason == "length"` (→ `truncated`).
///
/// Лимит токенов ответа адаптер не передаёт: число карточек ограничивает
/// `<limit>` в пользовательском сообщении, а `max_tokens` у части моделей
/// OpenAI устарел; обрезание всё равно распознаётся по `finish_reason`.
class OpenAiAdapter implements GenerationProviderAdapter {
  /// Создаёт адаптер.
  const OpenAiAdapter();

  @override
  GenerationProvider get provider => GenerationProvider.openai;

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
  }) {
    for (final GenerationAttachment image in images) {
      if (image.isPdf) {
        throw const GenerationException(GenerationErrorCode.pdfScanUnsupported);
      }
    }
    final ProviderEndpoint endpoint = ProviderEndpoint.parse(
      protocol: ProviderProtocol.openai,
      baseUrl: baseUrl ?? '',
      model: model,
    );
    final Uri? uri = endpoint.uri;
    if (uri == null) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Некорректный адрес OpenAI',
      );
    }
    return ProviderRequest(
      uri: uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: <String, Object?>{
        'model': model,
        'messages': <Object?>[
          <String, Object?>{'role': 'system', 'content': systemPrompt},
          <String, Object?>{
            'role': 'user',
            'content': openAiUserContent(userContent, images),
          },
        ],
        'response_format': <String, Object?>{
          'type': 'json_schema',
          'json_schema': <String, Object?>{
            'name': cardsResponseSchemaName,
            'strict': true,
            'schema': responseSchema ?? openAiStrictCardSchema(),
          },
        },
      },
    );
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    final rawChoices = json['choices'];
    if (rawChoices == null) {
      throw invalidProviderResponse('OpenAI', 'ответ без choices');
    }
    final choices = jsonListOrNull(rawChoices);
    if (choices == null || choices.isEmpty) {
      throw invalidProviderResponse('OpenAI', 'choices не список или пуст');
    }
    final choice = jsonObjectOrNull(choices.first);
    if (choice == null) {
      throw invalidProviderResponse('OpenAI', 'choices[0] не объект');
    }
    // TASK 04: обрыв по лимиту вывода — не исключение: полные карточки из
    // прерванного JSON спасает сервис, а пайплайн добирает недостачу.
    final bool truncated = choice['finish_reason'] == 'length';
    final message = jsonObjectOrNull(choice['message']);
    if (message == null) {
      throw invalidProviderResponse('OpenAI', 'choices[0].message не объект');
    }
    if (message['refusal'] != null) {
      throw const GenerationException(GenerationErrorCode.refused);
    }
    final content = message['content'];
    if (content == null) {
      if (truncated) {
        throw const GenerationException(GenerationErrorCode.truncated);
      }
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    if (content is! String) {
      throw invalidProviderResponse(
        'OpenAI',
        'choices[0].message.content не строка',
      );
    }
    if (content.trim().isEmpty) {
      if (truncated) {
        throw const GenerationException(GenerationErrorCode.truncated);
      }
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    return ProviderRawResponse(
      cardsJson: content,
      usage: _parseUsage(json),
      truncated: truncated,
    );
  }
}

TokenUsage _parseUsage(Map<String, Object?> json) {
  final usage = jsonObjectOrNull(json['usage']);
  if (usage == null) return const TokenUsage();
  return TokenUsage(
    promptTokens: jsonIntOrNull(usage['prompt_tokens']),
    completionTokens: jsonIntOrNull(usage['completion_tokens']),
    totalTokens: jsonIntOrNull(usage['total_tokens']),
  );
}
