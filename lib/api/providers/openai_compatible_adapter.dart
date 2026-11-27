/// Адаптер OpenAI-совместимого сервера с настраиваемым `base_url` (ADR-013).
///
/// Логика запроса/разбора — копия OpenAI Chat Completions (SPEC A8.2), но:
/// - endpoint берётся из настроек (`base_url`), а не фиксирован;
/// - ключ API опционален: для локальных серверов заголовок не отправляется;
/// - `response_format` со strict-схемой можно отключить (fallback для серверов,
///   которые не поддерживают strict; ответ всё равно проходит локальную
///   валидацию канонической схемы A8.4 в `CardGenerationService`).
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

/// OpenAI-совместимый провайдер: `POST <base_url>/chat/completions`,
/// `Authorization: Bearer <key>` (если ключ задан),
/// `response_format: {type: "json_schema", json_schema: {…strict: true}}`.
///
/// Проверки ответа — как у OpenAI (A8.2): `choices[0].message.content`
/// (пустой → `emptyResponse`), `message.refusal` (→ `refused`),
/// `finish_reason == "length"` (→ `truncated`).
class OpenAiCompatibleAdapter implements GenerationProviderAdapter {
  /// Создаёт адаптер.
  const OpenAiCompatibleAdapter();

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
  }) {
    for (final GenerationAttachment image in images) {
      if (image.isPdf) {
        throw const GenerationException(GenerationErrorCode.pdfScanUnsupported);
      }
    }
    final ProviderEndpoint endpoint = ProviderEndpoint.parse(
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: baseUrl ?? '',
      model: model,
    );
    final Uri? uri = endpoint.uri;
    if (uri == null) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Некорректный адрес OpenAI-совместимого сервера',
      );
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    final trimmedKey = apiKey.trim();
    if (trimmedKey.isNotEmpty) {
      headers['Authorization'] = 'Bearer $trimmedKey';
    }

    final body = <String, Object?>{
      'model': model,
      'messages': <Object?>[
        <String, Object?>{'role': 'system', 'content': systemPrompt},
        <String, Object?>{
          'role': 'user',
          'content': openAiUserContent(userContent, images),
        },
      ],
    };
    // ADR-021: серверный дефолт у части OpenAI-совместимых серверов (DeepSeek —
    // 4096) меньше 20 карточек ответа. Серверы, требующие вместо `max_tokens`
    // поле `max_completion_tokens`, отсекаются третьим шагом лестницы сервиса.
    if (sendMaxTokens) {
      body['max_tokens'] = maxOutputTokens;
    }
    if (strictSchema) {
      body['response_format'] = <String, Object?>{
        'type': 'json_schema',
        'json_schema': <String, Object?>{
          'name': cardsResponseSchemaName,
          'strict': true,
          'schema': responseSchema ?? openAiStrictCardSchema(),
        },
      };
    }

    return ProviderRequest(uri: uri, headers: headers, body: body);
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    final rawChoices = json['choices'];
    if (rawChoices == null) {
      throw invalidProviderResponse('OpenAI-compatible', 'ответ без choices');
    }
    final choices = jsonListOrNull(rawChoices);
    if (choices == null || choices.isEmpty) {
      throw invalidProviderResponse(
        'OpenAI-compatible',
        'choices не список или пуст',
      );
    }
    final choice = jsonObjectOrNull(choices.first);
    if (choice == null) {
      throw invalidProviderResponse(
        'OpenAI-compatible',
        'choices[0] не объект',
      );
    }
    // TASK 04: обрыв по лимиту вывода — не исключение: полные карточки из
    // прерванного JSON спасает сервис, а пайплайн добирает недостачу.
    final bool truncated = choice['finish_reason'] == 'length';
    final message = jsonObjectOrNull(choice['message']);
    if (message == null) {
      throw invalidProviderResponse(
        'OpenAI-compatible',
        'choices[0].message не объект',
      );
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
        'OpenAI-compatible',
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
