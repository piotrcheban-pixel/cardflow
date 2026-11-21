/// Каноническая JSON-схема ответа модели (SPEC A8.4).
///
/// Единая для всех провайдеров; проекции под возможности провайдера —
/// `provider_schema.dart`. Документация — `docs/api-schema.md`.
///
/// Итерация 7.19 (`gen-ru-v9`, ADR-042): модель назначает изображения обеим
/// сторонам карточки независимо — обязательные массивы `question_image_ids` и
/// `answer_image_ids` (могут быть пустыми) и необязательный объект `image` для
/// внешнего поиска настоящей фотографии со стороной `side`. Прежнее поле
/// `image_id` (одно на карточку) удалено из строгой схемы; локальная терпимая
/// схема принимает v5–v9, чтобы старые ответы не теряли карточки.
library;

/// Имя схемы для `response_format.json_schema.name` (OpenAI).
const String cardsResponseSchemaName = 'cards_response';

/// Виды иллюстрации схемы `gen-ru-v6`/`gen-ru-v9`.
const List<String> kImageKinds = <String>['photo', 'diagram', 'illustration'];

/// Стороны внешнего поиска изображения (схема `gen-ru-v9`).
const List<String> kImageSides = <String>['question', 'answer', 'none'];

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
          'section_id': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'question_image_ids': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
          'answer_image_ids': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
          },
          'image': <String, Object?>{
            'type': <String>['object', 'null'],
            'properties': <String, Object?>{
              'query': <String, Object?>{'type': 'string'},
              'fallback_query': <String, Object?>{'type': 'string'},
              'kind': <String, Object?>{'type': 'string', 'enum': kImageKinds},
              'side': <String, Object?>{'type': 'string', 'enum': kImageSides},
            },
            'required': <String>['query', 'fallback_query', 'kind', 'side'],
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
          'section_id',
          'question_image_ids',
          'answer_image_ids',
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

/// Локальная терпимая схема карточки: v9 (`*_image_ids`, `image.side`) и
/// v5–v8 (`image_id`, `image_query`, `image` без стороны).
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
      'question_image_ids': <String, Object?>{
        'type': <String>['array', 'null'],
        'items': <String, Object?>{'type': 'string'},
      },
      'answer_image_ids': <String, Object?>{
        'type': <String>['array', 'null'],
        'items': <String, Object?>{'type': 'string'},
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
