/// Проекции канонической схемы A8.4 под возможности провайдеров (SPEC A8.2).
///
/// Канон один (`card_json_schema.dart`); проекции строятся программно:
/// - OpenAI — канон как есть (strict JSON Schema);
/// - Gemini — union `[T, "null"]` → `nullable: true`, типы в верхнем регистре,
///   без `additionalProperties`, с `propertyOrdering`;
/// - Anthropic — union → `anyOf: [{type: T}, {type: "null"}]`.
library;

import 'package:cardflow/api/generation/card_json_schema.dart';

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
///
/// [canonicalSchema] — основа проекции; `null` — канон A8.4. Расширение
/// среза 5 (`gen-cards-v3`: `unit_id`/`angle`/`quote_ref`) проецируется той же
/// машинерией, поэтому адаптеры не получают второй набор правил.
///
/// Каждый вызов возвращает независимую копию: изменение результата не портит
/// канон и проекции других провайдеров.
Map<String, Object?> projectCardSchema(
  ProviderSchemaFlavor flavor, {
  Map<String, Object?>? canonicalSchema,
}) {
  final Map<String, Object?> source = canonicalSchema == null
      ? copyCanonicalCardsResponseSchema()
      : copyCardSchema(canonicalSchema);
  return switch (flavor) {
    ProviderSchemaFlavor.openAi => source,
    ProviderSchemaFlavor.gemini => _projectForGemini(source),
    ProviderSchemaFlavor.anthropic => _projectForAnthropic(source),
  };
}

/// Схема для `response_format.json_schema.schema` (OpenAI).
Map<String, Object?> openAiStrictCardSchema({
  Map<String, Object?>? canonicalSchema,
}) => projectCardSchema(
  ProviderSchemaFlavor.openAi,
  canonicalSchema: canonicalSchema,
);

/// Схема для `generationConfig.responseSchema` (Gemini).
Map<String, Object?> geminiCardSchema({
  Map<String, Object?>? canonicalSchema,
}) => projectCardSchema(
  ProviderSchemaFlavor.gemini,
  canonicalSchema: canonicalSchema,
);

/// Схема для `tools[].input_schema` (Anthropic).
Map<String, Object?> anthropicToolCardSchema({
  Map<String, Object?>? canonicalSchema,
}) => projectCardSchema(
  ProviderSchemaFlavor.anthropic,
  canonicalSchema: canonicalSchema,
);

/// Проекция расширения `gen-cards-v3` под возможности провайдера.
Map<String, Object?> cardSchemaV3For(ProviderSchemaFlavor flavor) =>
    projectCardSchema(flavor, canonicalSchema: cardsResponseSchemaV3());

/// Типы `Schema` Gemini: JSON Schema → верхний регистр (SPEC A8.2).
const Map<String, String> _geminiTypeNames = <String, String>{
  'string': 'STRING',
  'number': 'NUMBER',
  'integer': 'INTEGER',
  'boolean': 'BOOLEAN',
  'array': 'ARRAY',
  'object': 'OBJECT',
};

/// Проекция под Gemini: `nullable` вместо union, без `additionalProperties`,
/// с `propertyOrdering` в порядке свойств канона.
Map<String, Object?> _projectForGemini(Map<String, Object?> node) {
  final result = <String, Object?>{};
  final rawType = node['type'];
  if (rawType is List<Object?>) {
    final nonNullTypes = rawType
        .where((type) => type != 'null')
        .toList(growable: false);
    if (nonNullTypes.length != 1) {
      throw ArgumentError.value(
        rawType,
        'type',
        'Gemini Schema не умеет выражать union нескольких типов',
      );
    }
    result['type'] = _geminiTypeName(nonNullTypes.single);
    if (nonNullTypes.length != rawType.length) {
      result['nullable'] = true;
    }
  } else if (rawType is String) {
    result['type'] = _geminiTypeName(rawType);
  } else if (rawType != null) {
    throw ArgumentError.value(
      rawType,
      'type',
      'Неподдерживаемый тип JSON Schema',
    );
  }

  final enumValues = node['enum'];
  if (enumValues is List<Object?>) {
    result['enum'] = List<Object?>.of(enumValues);
  }
  final description = node['description'];
  if (description is String) {
    result['description'] = description;
  }

  final properties = node['properties'];
  if (properties is Map<String, Object?>) {
    final projectedProperties = <String, Object?>{};
    for (final entry in properties.entries) {
      projectedProperties[entry.key] = _projectForGemini(
        _schemaNode(entry.value, 'properties.${entry.key}'),
      );
    }
    result['properties'] = projectedProperties;
    result['propertyOrdering'] = properties.keys.toList(growable: false);
  }

  final required = node['required'];
  if (required is List<Object?>) {
    result['required'] = List<Object?>.of(required);
  }

  final items = node['items'];
  if (items != null) {
    result['items'] = _projectForGemini(_schemaNode(items, 'items'));
  }

  // `additionalProperties` у Gemini отсутствует в `Schema` API — ключ
  // отбрасывается (ADR-011 §2).
  return result;
}

/// Проекция под Anthropic: union `[T, "null"]` → `anyOf` с `null`,
/// `additionalProperties` сохраняется.
Map<String, Object?> _projectForAnthropic(Map<String, Object?> node) {
  final nullableBranch = _anthropicNullableBranch(node);
  if (nullableBranch != null) {
    return <String, Object?>{
      'anyOf': <Object?>[
        nullableBranch,
        <String, Object?>{'type': 'null'},
      ],
    };
  }
  final result = <String, Object?>{};
  for (final entry in node.entries) {
    result[entry.key] = _projectAnthropicValue(entry.key, entry.value);
  }
  return result;
}

/// Ветка `anyOf` для union-типа с `null`; `null`, если union-типа нет.
Map<String, Object?>? _anthropicNullableBranch(Map<String, Object?> node) {
  final rawType = node['type'];
  if (rawType is! List<Object?>) return null;
  final nonNullTypes = rawType
      .where((type) => type != 'null')
      .toList(growable: false);
  if (nonNullTypes.length != 1) {
    throw ArgumentError.value(
      rawType,
      'type',
      'Anthropic input_schema не умеет выражать union нескольких типов',
    );
  }
  final branch = <String, Object?>{'type': nonNullTypes.single};
  for (final entry in node.entries) {
    if (entry.key == 'type') continue;
    branch[entry.key] = _projectAnthropicValue(entry.key, entry.value);
  }
  return branch;
}

/// Проецирует значение [key] узла схемы Anthropic.
Object? _projectAnthropicValue(String key, Object? value) {
  switch (key) {
    case 'properties':
      final properties = value! as Map<String, Object?>;
      return <String, Object?>{
        for (final entry in properties.entries)
          entry.key: _projectForAnthropic(
            _schemaNode(entry.value, 'properties.${entry.key}'),
          ),
      };
    case 'items':
      return _projectForAnthropic(_schemaNode(value, 'items'));
    case 'required':
    case 'enum':
      return List<Object?>.of(value! as List<Object?>);
    default:
      return value;
  }
}

String _geminiTypeName(Object? rawType) {
  if (rawType is! String) {
    throw ArgumentError.value(
      rawType,
      'type',
      'Тип JSON Schema должен быть строкой',
    );
  }
  final projected = _geminiTypeNames[rawType];
  if (projected == null) {
    throw ArgumentError.value(
      rawType,
      'type',
      'Gemini Schema не поддерживает тип',
    );
  }
  return projected;
}

Map<String, Object?> _schemaNode(Object? value, String path) {
  if (value is Map<String, Object?>) return value;
  throw ArgumentError.value(value, path, 'Ожидался объект JSON Schema');
}
