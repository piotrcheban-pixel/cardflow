/// Карта знаний этапа Understanding (TASK «Срез 3», ADR-050): модель
/// предлагает атомарные единицы знания с якорями на блоки `ContentModel`,
/// а приложение (парсер) присваивает id, отбрасывает невалидные единицы и
/// решает, какие подсказки модели принимать.
///
/// Тип — доменный: без Flutter, сети и Dio/drift (guard
/// `test/guards/architecture_test.dart`). Вызов модели, промпт `gen-map-v1`
/// и разбор ответа живут в `lib/api/`.
library;

/// Вид атомарной единицы знания; значения совпадают с wire-значениями схемы
/// `gen-map-v1`.
enum KnowledgeUnitKind {
  /// Определение понятия.
  definition('definition'),

  /// Факт: дата, число, имя, свойство.
  fact('fact'),

  /// Связь: причина — следствие, условие — результат, сравнение.
  relation('relation'),

  /// Формула или закон в математической записи.
  formula('formula'),

  /// Порядок действий, алгоритм, правило.
  procedure('procedure');

  /// Создаёт значение с wire-именем.
  const KnowledgeUnitKind(this.wireName);

  /// Wire-имя в ответе модели и в JSON-схеме.
  final String wireName;

  /// Значение по wire-имени; `null` — неизвестный вид (единица отбрасывается).
  static KnowledgeUnitKind? fromWire(String value) {
    for (final KnowledgeUnitKind kind in values) {
      if (kind.wireName == value) return kind;
    }
    return null;
  }
}

/// Wire-имена видов в порядке объявления.
const List<String> kKnowledgeUnitKindWires = <String>[
  'definition',
  'fact',
  'relation',
  'formula',
  'procedure',
];

/// Имя схемы ответа модели (`response_format.json_schema.name`).
const String knowledgeMapSchemaName = 'knowledge_map';

/// Каноническая JSON-схема ответа `gen-map-v1` (по образцу A8.4).
///
/// Strict-совместима с OpenAI: все свойства в `required`, nullable-поле
/// `section_id` — union-тип с `null`, на каждом объекте
/// `additionalProperties: false`. Диапазон `salience` (0..1) проверяет парсер:
/// strict-режим не поддерживает `minimum`/`maximum`.
const Map<String, Object?> canonicalKnowledgeMapSchema = <String, Object?>{
  'type': 'object',
  'properties': <String, Object?>{
    'units': <String, Object?>{
      'type': 'array',
      'items': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'section_id': <String, Object?>{
            'type': <String>['string', 'null'],
          },
          'topic': <String, Object?>{'type': 'string'},
          'kind': <String, Object?>{
            'type': 'string',
            'enum': kKnowledgeUnitKindWires,
          },
          'statement': <String, Object?>{'type': 'string'},
          'anchors': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'block_id': <String, Object?>{'type': 'string'},
                'quote': <String, Object?>{'type': 'string'},
              },
              'required': <String>['block_id', 'quote'],
              'additionalProperties': false,
            },
          },
          'salience': <String, Object?>{'type': 'number'},
          'splittable': <String, Object?>{'type': 'boolean'},
        },
        'required': <String>[
          'section_id',
          'topic',
          'kind',
          'statement',
          'anchors',
          'salience',
          'splittable',
        ],
        'additionalProperties': false,
      },
    },
  },
  'required': <String>['units'],
  'additionalProperties': false,
};

/// Схема одной единицы — независимая копия из канона.
///
/// Ответ модели может содержать двадцать единиц, из которых одна кривая:
/// поштучная проверка отбрасывает только её, остальные идут в карту.
Map<String, Object?> canonicalKnowledgeUnitSchema() {
  final Map<String, Object?> properties =
      canonicalKnowledgeMapSchema['properties']! as Map<String, Object?>;
  final Map<String, Object?> units =
      properties['units']! as Map<String, Object?>;
  return _copyMap(units['items']! as Map<String, Object?>);
}

/// Якорь единицы знания: блок `ContentModel` и дословная цитата из него.
class KnowledgeAnchor {
  /// Создаёт якорь.
  const KnowledgeAnchor({required this.blockId, required this.quote})
    : assert(blockId != '', 'У якоря обязан быть блок'),
      assert(quote != '', 'У якоря обязана быть цитата');

  /// id блока в `ContentModel` (`doc:<файл>#<раздел>#<блок>`).
  final String blockId;

  /// Дословная подстрока текста блока.
  final String quote;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is KnowledgeAnchor &&
          other.blockId == blockId &&
          other.quote == quote;

  @override
  int get hashCode => Object.hash(blockId, quote);

  @override
  String toString() => 'KnowledgeAnchor($blockId)';
}

/// Атомарная единица знания: одно утверждение материала с доказательством.
class KnowledgeUnit {
  /// Создаёт единицу; списки копируются и становятся неизменяемыми.
  ///
  /// [id] присваивает приложение (`ku:<fragmentId>#<индекс ответа>`), а не
  /// модель: так id стабилен и не может быть подменён ответом.
  KnowledgeUnit({
    required this.id,
    required this.sectionId,
    required this.topic,
    required this.kind,
    required this.statement,
    List<KnowledgeAnchor> anchors = const <KnowledgeAnchor>[],
    this.salience = 0.5,
    this.splittable = false,
  }) : anchors = List<KnowledgeAnchor>.unmodifiable(anchors),
       assert(id != '', 'У единицы обязан быть id'),
       assert(sectionId != '', 'У единицы обязан быть раздел'),
       assert(statement != '', 'У единицы обязано быть утверждение'),
       assert(anchors.isNotEmpty, 'Единица обязана опираться на якорь'),
       assert(salience >= 0 && salience <= 1, 'Важность — доля в 0..1');

  /// Стабильный id (`ku:<fragmentId>#<индекс ответа>`), присваивает парсер.
  final String id;

  /// id раздела `ContentModel`, к которому относится утверждение.
  final String sectionId;

  /// Короткая тема единицы (1–5 слов из материала); может быть пустой.
  final String topic;

  /// Вид единицы.
  final KnowledgeUnitKind kind;

  /// Самодостаточное утверждение на русском языке.
  final String statement;

  /// Якоря: блоки материала и дословные цитаты (минимум один).
  final List<KnowledgeAnchor> anchors;

  /// Важность (доля 0..1): 1 — ключевое определение/закон раздела.
  final double salience;

  /// true — утверждение осталось составным и его стоит разбить дальше.
  final bool splittable;

  /// id блоков, на которые опирается единица.
  Set<String> get blockIds => <String>{
    for (final KnowledgeAnchor anchor in anchors) anchor.blockId,
  };

  @override
  String toString() =>
      'KnowledgeUnit($id, ${kind.wireName}, salience: $salience, '
      '${anchors.length} як.)';
}

/// Карта знаний документа: единицы и быстрый доступ по id/разделу.
class KnowledgeMap {
  /// Создаёт карту; список единиц копируется и становится неизменяемым.
  ///
  /// Дубли id — ошибка программиста ([ArgumentError]): id однозначно указывает
  /// на единицу, иначе «сколько пунктов карты» перестаёт быть определённым.
  KnowledgeMap({
    required this.documentId,
    List<KnowledgeUnit> units = const <KnowledgeUnit>[],
  }) : units = List<KnowledgeUnit>.unmodifiable(units),
       _unitsById = _indexUnits(units),
       _unitsBySection = _groupUnits(units);

  /// id документа (`doc:<имя файла>`).
  final String documentId;

  /// Единицы знания в порядке ответа модели.
  final List<KnowledgeUnit> units;

  final Map<String, KnowledgeUnit> _unitsById;
  final Map<String, List<KnowledgeUnit>> _unitsBySection;

  /// Единица по id за O(1); `null` — такой единицы нет.
  KnowledgeUnit? unit(String id) => _unitsById[id];

  /// Единицы раздела в порядке карты (пустой список, если раздела нет).
  List<KnowledgeUnit> unitsOfSection(String sectionId) =>
      _unitsBySection[sectionId] ?? const <KnowledgeUnit>[];

  /// Единицы, которые модель пометила составными (`splittable`).
  Iterable<KnowledgeUnit> get splittableUnits =>
      units.where((KnowledgeUnit unit) => unit.splittable);

  /// Число единиц.
  int get length => units.length;

  /// true, если единиц нет.
  bool get isEmpty => units.isEmpty;

  static Map<String, KnowledgeUnit> _indexUnits(List<KnowledgeUnit> units) {
    final Map<String, KnowledgeUnit> index = <String, KnowledgeUnit>{};
    for (final KnowledgeUnit unit in units) {
      if (index.containsKey(unit.id)) {
        throw ArgumentError('id единиц должны быть уникальными: ${unit.id}');
      }
      index[unit.id] = unit;
    }
    return index;
  }

  static Map<String, List<KnowledgeUnit>> _groupUnits(
    List<KnowledgeUnit> units,
  ) {
    final Map<String, List<KnowledgeUnit>> grouped =
        <String, List<KnowledgeUnit>>{};
    for (final KnowledgeUnit unit in units) {
      (grouped[unit.sectionId] ??= <KnowledgeUnit>[]).add(unit);
    }
    for (final String sectionId in grouped.keys.toList()) {
      grouped[sectionId] = List<KnowledgeUnit>.unmodifiable(
        grouped[sectionId]!,
      );
    }
    return grouped;
  }

  @override
  String toString() => 'KnowledgeMap($documentId, ${units.length} ед.)';
}

Map<String, Object?> _copyMap(Map<String, Object?> source) {
  return <String, Object?>{
    for (final MapEntry<String, Object?> entry in source.entries)
      entry.key: _copyValue(entry.value),
  };
}

Object? _copyValue(Object? value) {
  if (value is Map<String, Object?>) return _copyMap(value);
  if (value is List<Object?>) return value.map(_copyValue).toList();
  return value;
}
