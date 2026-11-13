/// Проекции канонической схемы A8.4 под возможности провайдеров (SPEC A8.2).
///
/// Канон один (`card_json_schema.dart`); проекции строятся программно:
/// - OpenAI — канон как есть (strict JSON Schema);
/// - Gemini — union `[T, "null"]` → `nullable: true`, типы в верхнем регистре,
///   без `additionalProperties`, с `propertyOrdering`;
/// - Anthropic — union → `anyOf: [{type: T}, {type: "null"}]`.
library;

/// Возможности провайдера, влияющие на проекцию схемы.
enum ProviderSchemaFlavor {
  /// OpenAI strict JSON Schema.
  openAi,

  /// Google Gemini `responseSchema`.
  gemini,

  /// Anthropic `input_schema` инструмента.
  anthropic,
}

/// Проецирует каноническую схему A8.4 под [flavor].
Map<String, Object?> projectCardSchema(ProviderSchemaFlavor flavor) {
  throw UnimplementedError('projectCardSchema');
}

/// Схема для `response_format.json_schema.schema` (OpenAI).
Map<String, Object?> openAiStrictCardSchema() =>
    projectCardSchema(ProviderSchemaFlavor.openAi);

/// Схема для `generationConfig.responseSchema` (Gemini).
Map<String, Object?> geminiCardSchema() =>
    projectCardSchema(ProviderSchemaFlavor.gemini);

/// Схема для `tools[].input_schema` (Anthropic).
Map<String, Object?> anthropicToolCardSchema() =>
    projectCardSchema(ProviderSchemaFlavor.anthropic);
