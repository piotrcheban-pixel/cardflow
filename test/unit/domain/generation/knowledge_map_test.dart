import 'dart:convert';

import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт карты знаний: `KnowledgeUnit`, якоря и каноническая JSON-схема
/// `gen-map-v1` (этап Understanding, TASK «Срез 3», ADR-050: модель — только
/// источник кандидатов, покрытие и дедуп остаются домену).
void main() {
  group('KnowledgeUnit', () {
    test('хранит поля, якоря неизменяемы', () {
      final List<KnowledgeAnchor> anchors = <KnowledgeAnchor>[
        const KnowledgeAnchor(blockId: 'doc:файл.md#0#0', quote: 'цитата'),
      ];
      final KnowledgeUnit unit = KnowledgeUnit(
        id: 'ku:doc:файл.md#0#0',
        sectionId: 'doc:файл.md#0',
        topic: 'тема',
        kind: KnowledgeUnitKind.definition,
        statement: 'Утверждение материала.',
        anchors: anchors,
        salience: 0.75,
        splittable: true,
      );

      expect(unit.id, 'ku:doc:файл.md#0#0');
      expect(unit.sectionId, 'doc:файл.md#0');
      expect(unit.topic, 'тема');
      expect(unit.kind, KnowledgeUnitKind.definition);
      expect(unit.statement, 'Утверждение материала.');
      expect(unit.salience, 0.75);
      expect(unit.splittable, isTrue);
      expect(unit.anchors, hasLength(1));
      expect(unit.anchors.single.blockId, 'doc:файл.md#0#0');
      expect(unit.anchors.single.quote, 'цитата');

      anchors.add(
        const KnowledgeAnchor(blockId: 'doc:файл.md#0#1', quote: 'ещё'),
      );
      expect(
        unit.anchors,
        hasLength(1),
        reason: 'Список якорей должен быть копией, а не ссылкой',
      );
      expect(
        () => unit.anchors.add(
          const KnowledgeAnchor(blockId: 'doc:файл.md#0#1', quote: 'ещё'),
        ),
        throwsUnsupportedError,
      );
    });

    test('инварианты конструктора: обязательные поля и диапазон salience', () {
      expect(() => _unit(id: ''), throwsAssertionError);
      expect(() => _unit(sectionId: ''), throwsAssertionError);
      expect(() => _unit(statement: ''), throwsAssertionError);
      expect(
        () => _unit(anchors: const <KnowledgeAnchor>[]),
        throwsAssertionError,
      );
      expect(() => _unit(salience: -0.01), throwsAssertionError);
      expect(() => _unit(salience: 1.01), throwsAssertionError);
      expect(
        () => _unit(
          anchors: <KnowledgeAnchor>[
            KnowledgeAnchor(blockId: '', quote: 'цитата'),
          ],
        ),
        throwsAssertionError,
      );
      expect(
        () => _unit(
          anchors: <KnowledgeAnchor>[
            KnowledgeAnchor(blockId: 'doc:файл.md#0#0', quote: ''),
          ],
        ),
        throwsAssertionError,
      );
      expect(_unit(salience: 0).salience, 0);
      expect(_unit(salience: 1).salience, 1);
    });
  });

  group('KnowledgeMap', () {
    test('unit по id — прямая ссылка из индекса, без поиска по списку', () {
      final KnowledgeUnit first = _unit(
        id: 'ku:doc:файл.md#0#0',
        sectionId: 'doc:файл.md#0',
      );
      final KnowledgeUnit second = _unit(
        id: 'ku:doc:файл.md#0#1',
        sectionId: 'doc:файл.md#1',
      );
      final KnowledgeMap map = KnowledgeMap(
        documentId: 'doc:файл.md',
        units: <KnowledgeUnit>[first, second],
      );

      expect(identical(map.unit('ku:doc:файл.md#0#0'), first), isTrue);
      expect(identical(map.unit('ku:doc:файл.md#0#1'), second), isTrue);
      expect(map.unit('ku:нет'), isNull);
      expect(map.length, 2);
      expect(map.isEmpty, isFalse);
      expect(map.unitsOfSection('doc:файл.md#0'), <KnowledgeUnit>[first]);
      expect(map.unitsOfSection('doc:файл.md#1'), <KnowledgeUnit>[second]);
      expect(map.unitsOfSection('doc:нет'), isEmpty);
    });

    test('splittableUnits и неизменяемость списка единиц', () {
      final KnowledgeMap map = KnowledgeMap(
        documentId: 'doc:файл.md',
        units: <KnowledgeUnit>[
          _unit(id: 'ku:1', splittable: false),
          _unit(id: 'ku:2', splittable: true),
        ],
      );

      expect(map.splittableUnits.map((KnowledgeUnit unit) => unit.id), <String>[
        'ku:2',
      ]);
      expect(() => map.units.add(_unit(id: 'ku:3')), throwsUnsupportedError);
    });

    test('пустая карта и дубли id', () {
      final KnowledgeMap empty = KnowledgeMap(documentId: 'doc:файл.md');
      expect(empty.isEmpty, isTrue);
      expect(empty.units, isEmpty);

      expect(
        () => KnowledgeMap(
          documentId: 'doc:файл.md',
          units: <KnowledgeUnit>[
            _unit(id: 'ku:1'),
            _unit(id: 'ku:1'),
          ],
        ),
        throwsArgumentError,
        reason: 'id единицы однозначно указывает на единицу',
      );
    });
  });

  group('KnowledgeUnitKind', () {
    test('wire-имена закреплены и разбираются обратно', () {
      expect(kKnowledgeUnitKindWires, <String>[
        'definition',
        'fact',
        'relation',
        'formula',
        'procedure',
      ]);
      expect(
        KnowledgeUnitKind.values.map((KnowledgeUnitKind kind) => kind.wireName),
        kKnowledgeUnitKindWires,
      );
      for (final KnowledgeUnitKind kind in KnowledgeUnitKind.values) {
        expect(KnowledgeUnitKind.fromWire(kind.wireName), kind);
      }
      expect(KnowledgeUnitKind.fromWire('opinion'), isNull);
      expect(KnowledgeUnitKind.fromWire(''), isNull);
    });
  });

  group('каноническая схема gen-map-v1', () {
    test('строгая по A8.4: все поля required, additionalProperties false', () {
      final Map<String, Object?> schema = canonicalKnowledgeMapSchema;
      expect(schema['type'], 'object');
      expect(schema['additionalProperties'], isFalse);
      expect(schema['required'], <String>['units']);

      final Map<String, Object?> properties =
          schema['properties']! as Map<String, Object?>;
      final Map<String, Object?> units =
          properties['units']! as Map<String, Object?>;
      expect(units['type'], 'array');
      final Map<String, Object?> item = units['items']! as Map<String, Object?>;
      expect(item['type'], 'object');
      expect(item['additionalProperties'], isFalse);

      final Map<String, Object?> itemProperties =
          item['properties']! as Map<String, Object?>;
      expect(
        (item['required']! as List<Object?>).cast<String>().toSet(),
        itemProperties.keys.toSet(),
        reason: 'Каждое свойство единицы обязано быть в required (strict)',
      );
      expect(itemProperties.keys, <String>[
        'section_id',
        'topic',
        'kind',
        'statement',
        'anchors',
        'salience',
        'splittable',
      ]);
      expect(
        (itemProperties['section_id']! as Map<String, Object?>)['type'],
        <String>['string', 'null'],
      );
      expect(
        (itemProperties['kind']! as Map<String, Object?>)['enum'],
        kKnowledgeUnitKindWires,
      );
      expect(
        (itemProperties['salience']! as Map<String, Object?>)['type'],
        'number',
      );
      expect(
        (itemProperties['splittable']! as Map<String, Object?>)['type'],
        'boolean',
      );

      final Map<String, Object?> anchors =
          itemProperties['anchors']! as Map<String, Object?>;
      expect(anchors['type'], 'array');
      final Map<String, Object?> anchor =
          anchors['items']! as Map<String, Object?>;
      expect(anchor['additionalProperties'], isFalse);
      expect(anchor['required'], <String>['block_id', 'quote']);
      expect(
        (anchor['properties']! as Map<String, Object?>).keys.toSet(),
        <String>{'block_id', 'quote'},
      );
    });

    test('схема единицы копируется, JSON сериализуем', () {
      final Map<String, Object?> first = canonicalKnowledgeUnitSchema();
      final Map<String, Object?> second = canonicalKnowledgeUnitSchema();
      expect(identical(first, second), isFalse);
      expect(() => jsonEncode(canonicalKnowledgeMapSchema), returnsNormally);

      (first['properties']! as Map<String, Object?>).remove('statement');
      expect(
        second['properties']! as Map<String, Object?>,
        contains('statement'),
        reason: 'Копия не должна менять канон',
      );
      expect(
        (canonicalKnowledgeMapSchema['properties']!
            as Map<String, Object?>)['units'],
        isNotNull,
      );
    });
  });
}

KnowledgeUnit _unit({
  String id = 'ku:doc:файл.md#0#0',
  String sectionId = 'doc:файл.md#0',
  String topic = 'тема',
  KnowledgeUnitKind kind = KnowledgeUnitKind.fact,
  String statement = 'Утверждение.',
  List<KnowledgeAnchor> anchors = const <KnowledgeAnchor>[
    KnowledgeAnchor(blockId: 'doc:файл.md#0#0', quote: 'цитата'),
  ],
  double salience = 0.5,
  bool splittable = false,
}) => KnowledgeUnit(
  id: id,
  sectionId: sectionId,
  topic: topic,
  kind: kind,
  statement: statement,
  anchors: anchors,
  salience: salience,
  splittable: splittable,
);
