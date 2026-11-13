/// Каноническая JSON-схема ответа модели (SPEC A8.4).
///
/// Единая для всех провайдеров; проекции под возможности провайдера —
/// `provider_schema.dart`. Документация — `docs/api-schema.md`.
library;

/// Имя схемы для `response_format.json_schema.name` (OpenAI).
const String cardsResponseSchemaName = 'cards_response';

/// Каноническая схема A8.4 (валидируется `json_schema`).
const Map<String, Object?> canonicalCardsResponseSchema = <String, Object?>{};

/// Возвращает независимую копию канонической схемы.
///
/// Нужна, чтобы проекции провайдеров не могли случайно изменить канон.
Map<String, Object?> copyCanonicalCardsResponseSchema() {
  throw UnimplementedError('copyCanonicalCardsResponseSchema');
}
