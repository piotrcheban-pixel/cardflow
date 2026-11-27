import 'dart:convert';
import 'dart:io';

import 'package:cardflow/api/generation/knowledge_map_parser.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// Разбор ответа модели на `gen-map-v1` (этап Understanding, TASK «Срез 3»).
///
/// Правила (Q8/Q9): id единицы присваивает приложение (`ku:<фрагмент>#<индекс>`),
/// `section_id` — подсказка, якорь на блок вне запроса отбрасывается, одна
/// невалидная единица не отменяет остальные, а невалидный корень помечает
/// фрагмент.
void main() {
  const KnowledgeMapParser parser = KnowledgeMapParser();
  const KnowledgeMapFragmentContext context = KnowledgeMapFragmentContext(
    fragmentId: 'doc:конспект.docx#0',
    sectionId: 'doc:конспект.docx#0',
    blockIds: <String>{
      'doc:конспект.docx#0#0',
      'doc:конспект.docx#0#1',
      'doc:конспект.docx#0#2',
      'doc:конспект.docx#0#3',
    },
    sectionIds: <String>{'doc:конспект.docx#0'},
  );

  group('golden-фикстура gen-map-v1', () {
    test('валидный ответ разбирается в единицы с якорями', () {
      final String raw = File(
        'test/fixtures/understanding/gen-map-v1-response.json',
      ).readAsStringSync();

      final KnowledgeMapParseOutcome outcome = parser.parse(
        raw,
        context: context,
      );

      expect(outcome.isSuccess, isTrue, reason: '${outcome.failureReason}');
      expect(outcome.rejectedUnits, 0);
      expect(outcome.units, hasLength(3));

      final KnowledgeUnit first = outcome.units[0];
      expect(first.id, 'ku:doc:конспект.docx#0#0');
      expect(first.sectionId, 'doc:конспект.docx#0');
      expect(first.topic, 'момент силы');
      expect(first.kind, KnowledgeUnitKind.definition);
      expect(first.statement, startsWith('Момент силы относительно оси'));
      expect(first.salience, 0.9);
      expect(first.splittable, isFalse);
      expect(first.anchors, hasLength(1));
      expect(first.anchors.single.blockId, 'doc:конспект.docx#0#0');
      expect(
        first.anchors.single.quote,
        'Момент силы относительно оси равен произведению модуля силы на плечо.',
      );

      final KnowledgeUnit second = outcome.units[1];
      expect(second.id, 'ku:doc:конспект.docx#0#1');
      expect(second.kind, KnowledgeUnitKind.relation);
      expect(second.anchors, hasLength(2));
      expect(second.anchors[0].blockId, 'doc:конспект.docx#0#1');
      expect(second.anchors[1].blockId, 'doc:конспект.docx#0#2');

      final KnowledgeUnit third = outcome.units[2];
      expect(third.id, 'ku:doc:конспект.docx#0#2');
      expect(third.kind, KnowledgeUnitKind.formula);
      expect(third.splittable, isTrue);
      expect(
        third.sectionId,
        'doc:конспект.docx#0',
        reason: 'section_id = null — берётся раздел фрагмента',
      );
    });
  });

  group('валидные ответы', () {
    test('пустой список единиц — валидный ответ', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[]),
        context: context,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.units, isEmpty);
      expect(outcome.rejectedUnits, 0);
    });

    test('salience на границах 0 и 1 допустим', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[_unitJson(salience: 0), _unitJson(salience: 1)]),
        context: context,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.units, hasLength(2));
      expect(outcome.rejectedUnits, 0);
    });

    test('id строятся по индексу ответа и стабильны', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[
          _unitJson(statement: 'Первое утверждение.'),
          _unitJson(statement: 'Второе утверждение.'),
          _unitJson(statement: 'Третье утверждение.'),
        ]),
        context: context,
      );

      expect(outcome.units.map((KnowledgeUnit unit) => unit.id), <String>[
        'ku:doc:конспект.docx#0#0',
        'ku:doc:конспект.docx#0#1',
        'ku:doc:конспект.docx#0#2',
      ]);
    });

    test('section_id принимается только для известного раздела', () {
      const KnowledgeMapFragmentContext twoSections =
          KnowledgeMapFragmentContext(
            fragmentId: 'doc:конспект.docx#0',
            sectionId: 'doc:конспект.docx#0',
            blockIds: <String>{'doc:конспект.docx#0#0'},
            sectionIds: <String>{'doc:конспект.docx#0', 'doc:конспект.docx#1'},
          );

      final KnowledgeMapParseOutcome known = parser.parse(
        _json(<Object?>[_unitJson(sectionId: 'doc:конспект.docx#1')]),
        context: twoSections,
      );
      expect(known.units.single.sectionId, 'doc:конспект.docx#1');

      final KnowledgeMapParseOutcome unknown = parser.parse(
        _json(<Object?>[_unitJson(sectionId: 'doc:чужой.docx#7')]),
        context: twoSections,
      );
      expect(
        unknown.units.single.sectionId,
        'doc:конспект.docx#0',
        reason: 'Неизвестная подсказка не становится фактом',
      );

      final KnowledgeMapParseOutcome absent = parser.parse(
        _json(<Object?>[_unitJson(sectionId: null)]),
        context: twoSections,
      );
      expect(absent.units.single.sectionId, 'doc:конспект.docx#0');
    });

    test('markdown-ограждение разбирается только в терпимом режиме', () {
      final String fenced = '```json\n${_json(<Object?>[_unitJson()])}\n```';

      expect(
        parser.parse(fenced, context: context).isSuccess,
        isFalse,
        reason: 'Строгий режим требует чистый JSON',
      );
      expect(
        parser.parse(fenced, context: context, tolerant: true).isSuccess,
        isTrue,
      );
    });
  });

  group('невалидные ответы помечают фрагмент', () {
    test('не JSON, пустая строка и текст без JSON — jsonParse', () {
      for (final String raw in <String>[
        '{"units": [',
        '',
        '   ',
        'Не JSON, модель ответила текстом.',
      ]) {
        final KnowledgeMapParseOutcome outcome = parser.parse(
          raw,
          context: context,
        );
        expect(outcome.isSuccess, isFalse, reason: 'raw: «$raw»');
        expect(
          outcome.failureReason,
          KnowledgeMapFailureReason.jsonParse,
          reason: 'raw: «$raw»',
        );
        expect(outcome.units, isEmpty);
        expect(outcome.rejectedUnits, 0);
      }
    });

    test('корень не {"units": [...]} — schemaInvalid', () {
      for (final String raw in <String>[
        '[]',
        '{"cards": []}',
        '{"units": {}}',
        '{"units": null}',
      ]) {
        final KnowledgeMapParseOutcome outcome = parser.parse(
          raw,
          context: context,
        );
        expect(outcome.isSuccess, isFalse, reason: 'raw: $raw');
        expect(outcome.failureReason, KnowledgeMapFailureReason.schemaInvalid);
        expect(outcome.units, isEmpty);
      }
    });
  });

  group('поштучная проверка единиц', () {
    test('одна невалидная единица не отменяет остальные', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[
          _unitJson(statement: 'Хорошее утверждение.'),
          _unitJson(salience: 1.5),
        ]),
        context: context,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.units, hasLength(1));
      expect(outcome.units.single.statement, 'Хорошее утверждение.');
      expect(outcome.rejectedUnits, 1);
    });

    test('без обязательного поля и с неизвестным kind — отбрасываются', () {
      final Map<String, Object?> withoutSalience = _unitJson();
      withoutSalience.remove('salience');

      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[
          withoutSalience,
          _unitJson(kind: 'opinion'),
          _unitJson(statement: '   '),
        ]),
        context: context,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.units, isEmpty);
      expect(outcome.rejectedUnits, 3);
    });

    test('якорь на блок вне запроса отбрасывается, но единица остаётся', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[
          _unitJson(
            anchors: <Map<String, Object?>>[
              <String, Object?>{
                'block_id': 'doc:конспект.docx#7#7',
                'quote': 'чужой блок',
              },
              <String, Object?>{
                'block_id': 'doc:конспект.docx#0#0',
                'quote': 'Первая строка.',
              },
            ],
          ),
        ]),
        context: context,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.units.single.anchors, hasLength(1));
      expect(
        outcome.units.single.anchors.single.blockId,
        'doc:конспект.docx#0#0',
      );
    });

    test('без валидных якорей и с пустой цитатой единица отбрасывается', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[
          _unitJson(
            anchors: <Map<String, Object?>>[
              <String, Object?>{
                'block_id': 'doc:конспект.docx#7#7',
                'quote': 'чужой блок',
              },
            ],
          ),
          _unitJson(
            anchors: <Map<String, Object?>>[
              <String, Object?>{
                'block_id': 'doc:конспект.docx#0#0',
                'quote': ' ',
              },
            ],
          ),
        ]),
        context: context,
      );

      expect(outcome.isSuccess, isTrue);
      expect(outcome.units, isEmpty);
      expect(outcome.rejectedUnits, 2);
    });

    test('пробелы вокруг полей обрезаются', () {
      final KnowledgeMapParseOutcome outcome = parser.parse(
        _json(<Object?>[
          _unitJson(
            sectionId: ' doc:конспект.docx#0 ',
            topic: ' тема ',
            statement: '  Утверждение.  ',
            anchors: <Map<String, Object?>>[
              <String, Object?>{
                'block_id': ' doc:конспект.docx#0#0 ',
                'quote': ' Первая строка. ',
              },
            ],
          ),
        ]),
        context: context,
      );

      final KnowledgeUnit unit = outcome.units.single;
      expect(unit.sectionId, 'doc:конспект.docx#0');
      expect(unit.topic, 'тема');
      expect(unit.statement, 'Утверждение.');
      expect(unit.anchors.single.blockId, 'doc:конспект.docx#0#0');
      expect(unit.anchors.single.quote, 'Первая строка.');
    });
  });
}

String _json(Object? units) => jsonEncode(<String, Object?>{'units': units});

Map<String, Object?> _unitJson({
  Object? sectionId = 'doc:конспект.docx#0',
  String topic = 'тема',
  String kind = 'fact',
  String statement = 'Первая строка.',
  List<Map<String, Object?>>? anchors,
  num salience = 0.5,
  bool splittable = false,
}) => <String, Object?>{
  'section_id': sectionId,
  'topic': topic,
  'kind': kind,
  'statement': statement,
  'anchors':
      anchors ??
      <Map<String, Object?>>[
        <String, Object?>{
          'block_id': 'doc:конспект.docx#0#0',
          'quote': 'Первая строка.',
        },
      ],
  'salience': salience,
  'splittable': splittable,
};
