/// Адаптер OpenAI Chat Completions со strict JSON Schema (SPEC A8.2).
library;

import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

/// OpenAI: `POST https://api.openai.com/v1/chat/completions`,
/// `Authorization: Bearer <key>`, `response_format: {type: "json_schema",
/// json_schema: {name: "cards_response", strict: true, schema: …}}`.
///
/// Проверки ответа (A8.2): `choices[0].message.content` (пустой контент →
/// `emptyResponse`), `message.refusal` (→ `refused`),
/// `choices[0].finish_reason == "length"` (→ `truncated`).
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
  }) {
    throw UnimplementedError('OpenAiAdapter.buildRequest');
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    throw UnimplementedError('OpenAiAdapter.parseResponse');
  }
}
