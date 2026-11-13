/// Каноническая JSON-схема ответа модели (SPEC A8.4).
///
/// Единая для всех провайдеров; проекции под возможности провайдера —
/// `provider_schema.dart`. Документация — `docs/api-schema.md`.
library;

/// Имя схемы для `response_format.json_schema.name` (OpenAI).
const String cardsResponseSchemaName = 'cards_response';

/// Каноническая схема A8.4 (валидируется `json_schema`).
///
/// Все свойства в `required`, nullable-поля — union-тип с `null`,
/// `additionalProperties: false` на каждом объекте (требование strict-режима
/// OpenAI). Тот же JSON ожидается от всех провайдеров.
const Map<String, Object?> canonicalCardsResponseSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'cards': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'front': <String, Object?>{'type': 'string'},
          'back': <String, Object?>{'type': 'string'},
          'hint': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'tags': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
          'card_type': <String, Object?>{
            'type': 'string',
            'enum': <String>['basic', 'basic_reversed', 'cloze'],
          },
          'source_excerpt': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'source_file': <String, Object?>{
            'type': <String>['string', 'null'],
          },
        },
        'required': <String>[
          'front',
          'back',
          'hint',
          'tags',
          'card_type',
          'source_excerpt',
          'source_file',
        ],
        'additionalProperties': false,
      },
    },
  },
  'required': <String>['cards'],
  'additionalProperties': false,
};

/// Возвращает независимую копию канонической схемы.
///
/// Нужна, чтобы проекции провайдеров не могли случайно изменить канон.
Map<String, Object?> copyCanonicalCardsResponseSchema() =>
    _copyMap(canonicalCardsResponseSchema);

Map<String, Object?> _copyMap(Map<String, Object?> source) {
  return <String, Object?>{
    for (final entry in source.entries) entry.key: _copyValue(entry.value),
  };
}

Object? _copyValue(Object? value) {
  if (value is Map<String, Object?>) return _copyMap(value);
  if (value is List<Object?>) return value.map(_copyValue).toList();
  return value;
}
