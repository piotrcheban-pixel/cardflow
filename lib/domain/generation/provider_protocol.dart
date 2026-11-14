/// Протокол API провайдера генерации (SPEC A8.2, ADR-020).
///
/// Протокол — «язык» запроса; аккаунт провайдера (каталог или пользовательский)
/// выбирает протокол и адрес. Домен не зависит от Flutter и сети: протокол
/// отображается в существующий адаптер `GenerationProvider`.
library;

import 'package:cardflow/domain/generation/generation_provider.dart';

/// Протокол API, с которым работает один из адаптеров `lib/api/providers/`.
enum ProviderProtocol {
  /// OpenAI Chat Completions с настраиваемым `base_url`
  /// (DeepSeek, OpenRouter, Moonshot, MiniMax, Groq, Ollama, свои серверы).
  openaiCompletions('openai-completions', GenerationProvider.openaiCompatible),

  /// Официальный OpenAI Chat Completions (фиксированный адрес).
  openai('openai', GenerationProvider.openai),

  /// Anthropic Messages с инструментом `emit_cards`.
  anthropicMessages('anthropic-messages', GenerationProvider.anthropic),

  /// Google Gemini `generateContent`.
  geminiGenerateContent('gemini-generate-content', GenerationProvider.gemini);

  const ProviderProtocol(this.wireName, this.adapterProvider);

  /// Имя в JSON настроек провайдеров (`generation.providers`).
  final String wireName;

  /// Адаптер, который обслуживает протокол.
  final GenerationProvider adapterProvider;

  /// Протоколы, доступные для «Пользовательской модели API»: у всех можно
  /// задать свой базовый адрес.
  static const List<ProviderProtocol> customProtocols = <ProviderProtocol>[
    openaiCompletions,
    anthropicMessages,
    geminiGenerateContent,
  ];

  /// Базовый адрес по умолчанию для протокола (пусто — адрес обязателен).
  String get defaultBaseUrl {
    return switch (this) {
      ProviderProtocol.openaiCompletions => '',
      ProviderProtocol.openai => 'https://api.openai.com/v1',
      ProviderProtocol.anthropicMessages => 'https://api.anthropic.com',
      ProviderProtocol.geminiGenerateContent =>
        'https://generativelanguage.googleapis.com',
    };
  }

  /// Разбирает протокол из JSON; неизвестный — [FormatException].
  static ProviderProtocol fromWire(String value) {
    for (final ProviderProtocol protocol in values) {
      if (protocol.wireName == value) return protocol;
    }
    throw FormatException('Неизвестный протокол провайдера: $value');
  }
}
