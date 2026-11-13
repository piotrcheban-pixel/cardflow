/// Адаптер Google Gemini `generateContent` со структурированным выводом (SPEC A8.2).
library;

import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

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
  }) {
    throw UnimplementedError('GeminiAdapter.buildRequest');
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    throw UnimplementedError('GeminiAdapter.parseResponse');
  }
}
