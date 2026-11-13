/// Адаптер Anthropic Messages с инструментом `emit_cards` (SPEC A8.2).
library;

import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

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
  }) {
    throw UnimplementedError('AnthropicAdapter.buildRequest');
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    throw UnimplementedError('AnthropicAdapter.parseResponse');
  }
}
