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
  anthropic('anthropic'),

  /// OpenAI-совместимый сервер с настраиваемым `base_url` (ADR-013).
  ///
  /// Покрывает DeepSeek, локальные Ollama / LM Studio и любой другой сервер
  /// с Chat Completions API. Адрес и модель — из настроек (`app_settings`),
  /// ключ — из secure storage и опционален (локальные серверы без ключа).
  openaiCompatible('openai_compatible');

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
