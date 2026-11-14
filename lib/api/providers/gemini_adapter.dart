/// Адаптер Google Gemini `generateContent` со структурированным выводом (SPEC A8.2).
library;

import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/provider_endpoint.dart';
import 'package:cardflow/api/providers/provider_json.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Причины остановки Gemini, означающие отказ/safety-фильтр (SPEC A8.2).
const Set<String> _refusalFinishReasons = <String>{
  'SAFETY',
  'RECITATION',
  'BLOCKLIST',
  'PROHIBITED_CONTENT',
  'SPII',
};

/// Gemini: `POST https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent`,
/// ключ — только в заголовке `x-goog-api-key` (SPEC A8.6: не в URL),
/// `generationConfig: {responseMimeType: "application/json", responseSchema: …}`.
///
/// Проверки ответа (A8.2): `candidates[0]` (нет/пусто → `emptyResponse`),
/// `finishReason` (`MAX_TOKENS` → `truncated`; `SAFETY`/`RECITATION`/`BLOCKLIST`/
/// `PROHIBITED_CONTENT`/`SPII` → `refused`), `promptFeedback.blockReason` (→ `refused`).
class GeminiAdapter implements GenerationProviderAdapter {
  /// Создаёт адаптер.
  const GeminiAdapter();

  @override
  GenerationProvider get provider => GenerationProvider.gemini;

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
  }) {
    final ProviderEndpoint endpoint = ProviderEndpoint.parse(
      protocol: ProviderProtocol.geminiGenerateContent,
      baseUrl: baseUrl ?? '',
      model: model,
    );
    final Uri? uri = endpoint.uri;
    if (uri == null) {
      throw ArgumentError.value(
        baseUrl,
        'baseUrl',
        'Некорректный адрес Gemini',
      );
    }
    return ProviderRequest(
      uri: uri,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'x-goog-api-key': apiKey,
      },
      body: <String, Object?>{
        'systemInstruction': <String, Object?>{
          'parts': <Object?>[
            <String, Object?>{'text': systemPrompt},
          ],
        },
        'contents': <Object?>[
          <String, Object?>{
            'role': 'user',
            'parts': <Object?>[
              <String, Object?>{'text': userContent},
            ],
          },
        ],
        'generationConfig': <String, Object?>{
          'responseMimeType': 'application/json',
          'responseSchema': geminiCardSchema(),
          'maxOutputTokens': maxOutputTokens,
        },
      },
    );
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    final promptFeedback = jsonObjectOrNull(json['promptFeedback']);
    final blockReason = promptFeedback?['blockReason'];
    if (blockReason is String && blockReason.isNotEmpty) {
      throw const GenerationException(GenerationErrorCode.refused);
    }

    final rawCandidates = json['candidates'];
    if (rawCandidates == null) {
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    final candidates = jsonListOrNull(rawCandidates);
    if (candidates == null) {
      throw invalidProviderResponse('Gemini', 'candidates не список');
    }
    if (candidates.isEmpty) {
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    final candidate = jsonObjectOrNull(candidates.first);
    if (candidate == null) {
      throw invalidProviderResponse('Gemini', 'candidates[0] не объект');
    }

    final finishReason = candidate['finishReason'];
    if (finishReason == 'MAX_TOKENS') {
      throw const GenerationException(GenerationErrorCode.truncated);
    }
    if (finishReason is String &&
        _refusalFinishReasons.contains(finishReason)) {
      throw const GenerationException(GenerationErrorCode.refused);
    }

    final content = jsonObjectOrNull(candidate['content']);
    if (content == null) {
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    final rawParts = content['parts'];
    if (rawParts == null) {
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    final parts = jsonListOrNull(rawParts);
    if (parts == null) {
      throw invalidProviderResponse(
        'Gemini',
        'candidates[0].content.parts не список',
      );
    }
    final buffer = StringBuffer();
    for (final rawPart in parts) {
      final part = jsonObjectOrNull(rawPart);
      if (part == null) {
        throw invalidProviderResponse(
          'Gemini',
          'candidates[0].content.parts[] не объект',
        );
      }
      final text = part['text'];
      if (text == null) continue;
      if (text is! String) {
        throw invalidProviderResponse(
          'Gemini',
          'candidates[0].content.parts[].text не строка',
        );
      }
      buffer.write(text);
    }
    final cardsJson = buffer.toString();
    if (cardsJson.trim().isEmpty) {
      throw const GenerationException(GenerationErrorCode.emptyResponse);
    }
    return ProviderRawResponse(
      cardsJson: cardsJson,
      usage: _parseUsage(json['usageMetadata']),
    );
  }
}

TokenUsage _parseUsage(Object? value) {
  final usage = jsonObjectOrNull(value);
  if (usage == null) return const TokenUsage();
  return TokenUsage(
    promptTokens: jsonIntOrNull(usage['promptTokenCount']),
    completionTokens: jsonIntOrNull(usage['candidatesTokenCount']),
    totalTokens: jsonIntOrNull(usage['totalTokenCount']),
  );
}
