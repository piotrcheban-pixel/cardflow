/// Адаптер Anthropic Messages с инструментом `emit_cards` (SPEC A8.2).
library;

import 'dart:convert';

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

/// Версия Messages API (SPEC A8.2).
const String _anthropicVersion = '2023-06-01';

/// Имя инструмента, через который модель возвращает карточки.
const String _emitCardsTool = 'emit_cards';

/// Anthropic: `POST https://api.anthropic.com/v1/messages`,
/// `x-api-key: <key>`, `anthropic-version: 2023-06-01`, `max_tokens`,
/// `tools: [{name: "emit_cards", input_schema: …}]`,
/// `tool_choice: {type: "tool", name: "emit_cards"}`.
///
/// Проверки ответа (A8.2): `stop_reason` (`max_tokens` → `truncated`,
/// `refusal` → `refused`), `content[]` с `{type: "tool_use", name: "emit_cards"}`
/// (нет → `invalidResponse`).
class AnthropicAdapter implements GenerationProviderAdapter {
  /// Создаёт адаптер.
  const AnthropicAdapter();

  @override
  GenerationProvider get provider => GenerationProvider.anthropic;

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
  }) {
    final ProviderEndpoint endpoint = ProviderEndpoint.parse(
      protocol: ProviderProtocol.anthropicMessages,
      baseUrl: baseUrl ?? '',
      model: model,
    );
    final Uri? uri = endpoint.uri;
    if (uri == null) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Некорректный адрес Anthropic',
      );
    }
    final Map<String, String> headers = <String, String>{
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': _anthropicVersion,
    };
    // PDF-документы в Messages API включаются beta-заголовком (ADR-022).
    if (images.any((GenerationAttachment attachment) => attachment.isPdf)) {
      headers['anthropic-beta'] = 'pdfs-2024-09-25';
    }
    return ProviderRequest(
      uri: uri,
      headers: headers,
      body: <String, Object?>{
        'model': model,
        // Anthropic требует явный лимит ответа (SPEC A8.2).
        'max_tokens': maxOutputTokens,
        'system': systemPrompt,
        'messages': <Object?>[
          <String, Object?>{
            'role': 'user',
            'content': anthropicUserContent(userContent, images),
          },
        ],
        'tools': <Object?>[
          <String, Object?>{
            'name': _emitCardsTool,
            'description':
                'Emit the generated flashcards as JSON matching the schema.',
            'input_schema': anthropicToolCardSchema(),
          },
        ],
        'tool_choice': <String, Object?>{
          'type': 'tool',
          'name': _emitCardsTool,
        },
      },
    );
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    final stopReason = json['stop_reason'];
    // TASK 04: `max_tokens` — обрыв вывода. У Anthropic JSON карточек приходит
    // уже разобранным внутри `tool_use.input`, поэтому частичного текста нет:
    // если блока нет, сервис получит `truncated` и включит восстановление.
    final bool truncated = stopReason == 'max_tokens';
    if (stopReason == 'refusal') {
      throw const GenerationException(GenerationErrorCode.refused);
    }

    final rawContent = json['content'];
    if (rawContent == null) {
      throw invalidProviderResponse('Anthropic', 'ответ без content');
    }
    final content = jsonListOrNull(rawContent);
    if (content == null) {
      throw invalidProviderResponse('Anthropic', 'content не список');
    }
    for (final rawBlock in content) {
      final block = jsonObjectOrNull(rawBlock);
      if (block == null) {
        throw invalidProviderResponse('Anthropic', 'content[] не объект');
      }
      if (block['type'] != 'tool_use' || block['name'] != _emitCardsTool) {
        continue;
      }
      final input = jsonObjectOrNull(block['input']);
      if (input == null) {
        throw invalidProviderResponse(
          'Anthropic',
          '$_emitCardsTool.input не объект',
        );
      }
      return ProviderRawResponse(
        cardsJson: jsonEncode(input),
        usage: _parseUsage(json['usage']),
        truncated: truncated,
      );
    }
    if (truncated) {
      throw const GenerationException(GenerationErrorCode.truncated);
    }
    throw invalidProviderResponse(
      'Anthropic',
      'нет tool_use-блока $_emitCardsTool',
    );
  }
}

TokenUsage _parseUsage(Object? value) {
  final usage = jsonObjectOrNull(value);
  if (usage == null) return const TokenUsage();
  final promptTokens = jsonIntOrNull(usage['input_tokens']);
  final completionTokens = jsonIntOrNull(usage['output_tokens']);
  final int? totalTokens = promptTokens != null && completionTokens != null
      ? promptTokens + completionTokens
      : null;
  return TokenUsage(
    promptTokens: promptTokens,
    completionTokens: completionTokens,
    totalTokens: totalTokens,
  );
}
