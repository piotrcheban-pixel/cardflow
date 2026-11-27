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

/// Имя схемы ответа промпта `gen-cards-v3` (единицы карты знаний).
const String cardsResponseSchemaV3Name = 'cards_response_v3';

/// Углы карточки схемы `gen-cards-v3`: `primary` — основная карточка.
const List<String> kCardAngleWires = <String>[
  'primary',
  'reverse',
  'cloze',
  'application',
];

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

/// Независимая копия произвольной JSON-схемы карточек (проекции провайдеров).
Map<String, Object?> copyCardSchema(Map<String, Object?> source) =>
    _copyMap(source);

/// Возвращает независимую копию канонической схемы.
///
/// Нужна, чтобы проекции провайдеров не могли случайно изменить канон.
Map<String, Object?> copyCanonicalCardsResponseSchema() =>
    _copyMap(canonicalCardsResponseSchema);

/// Схема ответа промпта `gen-cards-v3`: A8.4 + `unit_id`, `angle`, `quote_ref`.
///
/// TASK «Срез 5» разрешает единственное расширение схемы карточки A8.4 —
/// привязку к единице карты знаний. Схема **отдельная** от канона: прежний
/// промпт `gen-ru-v9` продолжает работать со своей схемой и не должен
/// требовать полей, которых не знает (`examples/` и старый путь не трогаются).
/// На каждом объекте `additionalProperties: false`, все свойства в `required` —
/// требование strict-режима OpenAI.
Map<String, Object?> cardsResponseSchemaV3() {
  final Map<String, Object?> schema = copyCanonicalCardsResponseSchema();
  final Map<String, Object?> properties =
      schema['properties']! as Map<String, Object?>;
  final Map<String, Object?> cards =
      properties['cards']! as Map<String, Object?>;
  final Map<String, Object?> items = cards['items']! as Map<String, Object?>;
  final Map<String, Object?> cardProperties =
      items['properties']! as Map<String, Object?>;
  cardProperties['unit_id'] = <String, Object?>{'type': 'string'};
  cardProperties['angle'] = <String, Object?>{
    'type': 'string',
    'enum': kCardAngleWires,
  };
  cardProperties['quote_ref'] = <String, Object?>{'type': 'string'};
  final List<Object?> required = List<Object?>.of(
    items['required']! as List<Object?>,
  )..addAll(<String>['unit_id', 'angle', 'quote_ref']);
  items['required'] = required;
  return schema;
}

/// Схема одной карточки `gen-cards-v3` — независимая копия из расширения.
Map<String, Object?> cardsResponseV3CardItemSchema() {
  final Map<String, Object?> properties =
      cardsResponseSchemaV3()['properties']! as Map<String, Object?>;
  final Map<String, Object?> cards =
      properties['cards']! as Map<String, Object?>;
  return _copyMap(cards['items']! as Map<String, Object?>);
}

/// Локальная терпимая схема карточки v3: A8.4-поля плюс привязка к единице.
///
/// Обязательны `front`, `back`, `card_type`, `unit_id`, `angle`, `quote_ref`:
/// карточка без привязки к единице не восстанавливает цитату и не считается
/// принятой (TASK «Срез 5»). Остальные поля проверяет контентный валидатор.
Map<String, Object?> localCardV3ItemSchema() {
  final Map<String, Object?> base = localCardItemSchema();
  final Map<String, Object?> properties =
      base['properties']! as Map<String, Object?>;
  properties['unit_id'] = <String, Object?>{'type': 'string'};
  properties['angle'] = <String, Object?>{
    'type': 'string',
    'enum': kCardAngleWires,
  };
  properties['quote_ref'] = <String, Object?>{'type': 'string'};
  final List<Object?> required = List<Object?>.of(
    base['required']! as List<Object?>,
  )..addAll(<String>['unit_id', 'angle', 'quote_ref']);
  base['required'] = required;
  return base;
}

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
