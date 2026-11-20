/// Каноническая JSON-схема ответа модели (SPEC A8.4).
///
/// Единая для всех провайдеров; проекции под возможности провайдера —
/// `provider_schema.dart`. Документация — `docs/api-schema.md`.
///
/// Итерация 7.14 (`gen-ru-v6`): у карточки появился обязательный объект
/// `image` (`query`, `fallback_query`, `kind`). Строгая схема провайдера
/// требует его; локальная проверка (`localCardItemSchema`) принимает и v6, и
/// ответ v5 с `image_query`, чтобы старые модели/провайдеры не теряли карточки.
library;

/// Имя схемы для `response_format.json_schema.name` (OpenAI).
const String cardsResponseSchemaName = 'cards_response';

/// Виды иллюстрации схемы `gen-ru-v6`.
const List<String> kImageKinds = <String>['photo', 'diagram', 'illustration'];

/// Каноническая схема A8.4 (валидируется `json_schema`).
///
/// Все свойства в `required`, nullable-поля — union-тип с `null`,
/// `additionalProperties: false` на каждом объекте (требование strict-режима
/// OpenAI). Тот же JSON ожидается от всех провайдеров.
const Map<String, Object?> canonicalCardsResponseSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'source_exhausted': <String, Object?>{'type': 'boolean'},
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
            'enum': <String>['basic', 'basic_reversed', 'cloze', 'occlusion'],
          },
          'source_excerpt': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'source_file': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'image_id': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'section_id': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'image': <String, Object?>{
            'type': 'object',
            'properties': <String, Object?>{
              'query': <String, Object?>{'type': 'string'},
              'fallback_query': <String, Object?>{'type': 'string'},
              'kind': <String, Object?>{'type': 'string', 'enum': kImageKinds},
            },
            'required': <String>['query', 'fallback_query', 'kind'],
            'additionalProperties': false,
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
          'image_id',
          'section_id',
          'image',
        ],
        'additionalProperties': false,
      },
    },
  },
  'required': <String>['cards', 'source_exhausted'],
  'additionalProperties': false,
};

/// Схема одной карточки (items массива `cards`) — для поштучной проверки.
///
/// Провайдер со strict-схемой может вернуть одну плохую карточку из двадцати;
/// тогда отбрасывается только она, остальные идут в предпросмотр (fix-gen, Д6).
Map<String, Object?> canonicalCardItemSchema() {
  final cards =
      canonicalCardsResponseSchema['properties']! as Map<String, Object?>;
  final items = cards['cards']! as Map<String, Object?>;
  return _copyMap(items['items']! as Map<String, Object?>);
}

/// Локальная терпимая схема карточки: v6 (`image`) и v5 (`image_query`).
///
/// Обязательны только структурные поля (`front`, `back`, `card_type`);
/// остальные проверяет контентный валидатор, а недостающее поле картинки не
/// отбрасывает карточку. Лишние ключи по-прежнему запрещены.
Map<String, Object?> localCardItemSchema() {
  return <String, Object?>{
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
      'card_type': <String, Object?>{'type': 'string'},
      'source_excerpt': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'source_file': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'image_id': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'image_query': <String, Object?>{
        'type': <String>['string', 'null'],
      },
      'image': <String, Object?>{
        'type': <String>['object', 'null'],
      },
      'section_id': <String, Object?>{
        'type': <String>['string', 'null'],
      },
    },
    'required': <String>['front', 'back', 'card_type'],
    'additionalProperties': false,
  };
}

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
