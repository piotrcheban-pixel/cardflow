/// Провайдеры генерации карточек (SPEC A8.2, A6.8).
///
/// Домен не зависит от Flutter: enum используется в UI, настройках, `generation_jobs`.
library;

/// Провайдер облачной LLM, доступный в MVP.
enum GenerationProvider {
  /// OpenAI Chat Completions.
  openai('openai'),

  /// Google Gemini `generateContent`.
  gemini('gemini'),

  /// Anthropic Messages + tool `emit_cards`.
  anthropic('anthropic');

  const GenerationProvider(this.wireName);

  /// Имя в БД/JSON (`generation_jobs.provider`, `app_settings`).
  final String wireName;

  /// Разбирает провайдера из строки БД/JSON.
  static GenerationProvider fromWire(String value) {
    for (final provider in values) {
      if (provider.wireName == value) return provider;
    }
    throw FormatException('Неизвестный провайдер: $value');
  }
}
