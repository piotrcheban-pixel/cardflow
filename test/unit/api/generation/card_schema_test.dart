import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/provider_schema.dart';

/// Красная фаза итерации 3b: каноническая схема A8.4, локальная валидация и
/// проекции под провайдеров (SPEC A8.2, A8.4).
void main() {
  Map<String, Object?> rootProperties() =>
      canonicalCardsResponseSchema['properties']! as Map<String, Object?>;

  Map<String, Object?> cardItem() =>
      (rootProperties()['cards']! as Map<String, Object?>)['items']!
          as Map<String, Object?>;

  Map<String, Object?> cardProperties() =>
      cardItem()['properties']! as Map<String, Object?>;

  Map<String, Object?> validCard() => <String, Object?>{
    'front': 'Что такое FSRS?',
    'back': 'Алгоритм интервального повторения.',
    'hint': null,
    'tags': <Object?>['fsrs', 'память'],
    'card_type': 'basic',
    'source_excerpt': 'FSRS — алгоритм интервального повторения.',
    'source_file': 'лекция.docx',
    'section_id': null,
    'question_image_ids': <String>['img1'],
    'answer_image_ids': <String>['img2'],
    'image': <String, Object?>{
      'query': 'fsrs algorithm memory',
      'fallback_query': 'fsrs memory',
      'kind': 'diagram',
      'side': 'question',
    },
  };

  Map<String, Object?> validResponse() => <String, Object?>{
    'source_exhausted': false,
    'cards': <Object?>[validCard()],
  };

  group('каноническая схема A8.4', () {
    test(
      'корень: объект cards, все свойства required, additionalProperties:false',
      () {
        expect(canonicalCardsResponseSchema['type'], 'object');
        expect(canonicalCardsResponseSchema['required'], <String>[
          'cards',
          'source_exhausted',
        ]);
        expect(canonicalCardsResponseSchema['additionalProperties'], isFalse);
        expect(rootProperties().keys, <String>['source_exhausted', 'cards']);
        expect(cardsResponseSchemaName, 'cards_response');
      },
    );

    test('карточка: ровно свойства A8.4, все в required, без лишних полей', () {
      expect(cardProperties().keys.toSet(), <String>{
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
      });
      expect(
        cardItem()['required'],
        cardProperties().keys.toList(growable: false),
      );
      expect(cardItem()['additionalProperties'], isFalse);
      expect(
        (cardProperties()['card_type']! as Map<String, Object?>)['enum'],
        <String>['basic', 'basic_reversed', 'cloze', 'occlusion'],
      );
      expect(
        (cardProperties()['front']! as Map<String, Object?>)['type'],
        'string',
      );
      expect(
        (cardProperties()['back']! as Map<String, Object?>)['type'],
        'string',
      );
      final image = cardProperties()['image']! as Map<String, Object?>;
      expect(image['type'], <String>['object', 'null']);
      expect(image['required'], <String>[
        'query',
        'fallback_query',
        'kind',
        'side',
      ]);
      expect(image['additionalProperties'], isFalse);
    });

    test('nullable-поля — union с null (строгий режим OpenAI)', () {
      for (final field in <String>[
        'hint',
        'source_excerpt',
        'source_file',
        'section_id',
      ]) {
        expect(
          (cardProperties()[field]! as Map<String, Object?>)['type'],
          <String>['string', 'null'],
          reason: 'Поле $field должно допускать null',
        );
      }
      expect(
        ((cardProperties()['tags']! as Map<String, Object?>)['items']!
            as Map<String, Object?>)['type'],
        'string',
      );
      // Массивы id обязательны, но допускают пустое значение (v9).
      for (final field in <String>['question_image_ids', 'answer_image_ids']) {
        final Map<String, Object?> property =
            cardProperties()[field]! as Map<String, Object?>;
        expect(property['type'], 'array');
        expect((property['items']! as Map<String, Object?>)['type'], 'string');
      }
    });

    test('copyCanonicalCardsResponseSchema возвращает независимую копию', () {
      final copy = copyCanonicalCardsResponseSchema();
      expect(copy, canonicalCardsResponseSchema);
      (copy['required']! as List<Object?>).add('extra');
      expect(canonicalCardsResponseSchema['required'], <String>[
        'cards',
        'source_exhausted',
      ], reason: 'Копия не должна менять канон');
    });
  });

  group('CardResponseSchema (локальная валидация, SPEC A8.4)', () {
    final schema = CardResponseSchema();

    test('валидный ответ без карточек и с карточкой', () {
      expect(
        schema.isValid(<String, Object?>{
          'source_exhausted': false,
          'cards': <Object?>[],
        }),
        isTrue,
      );
      expect(schema.isValid(validResponse()), isTrue);
      expect(schema.validate(validResponse()), isEmpty);
    });

    test('лишнее свойство нарушает additionalProperties:false', () {
      final card = validCard()..['extra'] = 'x';
      final response = <String, Object?>{
        'source_exhausted': false,
        'cards': <Object?>[card],
      };
      expect(schema.isValid(response), isFalse);
      expect(schema.validate(response), isNotEmpty);
    });

    test('отсутствующий required ловится (back)', () {
      final card = validCard()..remove('back');
      expect(
        schema.isValid(<String, Object?>{
          'source_exhausted': false,
          'cards': <Object?>[card],
        }),
        isFalse,
      );
    });

    test('неверные типы и enum ловятся', () {
      for (final mutation in <void Function(Map<String, Object?>)>[
        (card) => card['front'] = 1,
        (card) => card['tags'] = 'не-массив',
        (card) => card['tags'] = <Object?>[1],
        (card) => card['card_type'] = 'image',
        (card) => card['hint'] = 3,
      ]) {
        final card = validCard();
        mutation(card);
        expect(
          schema.isValid(<String, Object?>{
            'source_exhausted': false,
            'cards': <Object?>[card],
          }),
          isFalse,
        );
      }
    });

    test('null допустим в nullable-полях', () {
      final card = validCard()
        ..['hint'] = null
        ..['source_excerpt'] = null
        ..['source_file'] = null
        ..['question_image_ids'] = <String>[]
        ..['answer_image_ids'] = <String>[]
        ..['image'] = null;
      expect(
        schema.isValid(<String, Object?>{
          'source_exhausted': false,
          'cards': <Object?>[card],
        }),
        isTrue,
      );
    });

    test('локальная схема принимает ответ v5 с image_query', () {
      final legacy = <String, Object?>{
        'front': 'Вопрос',
        'back': 'Ответ',
        'hint': null,
        'tags': <Object?>['тег'],
        'card_type': 'basic',
        'source_excerpt': null,
        'source_file': null,
        'image_id': null,
        'image_query': 'truss bridge',
      };
      final validation = CardResponseSchema().splitValid(<String, Object?>{
        'source_exhausted': false,
        'cards': <Object?>[legacy],
      });
      expect(validation.rootInvalid, isFalse);
      expect(validation.cards, hasLength(1));
      expect(validation.rejectedCards, 0);
    });

    test('не объект/не карточки — невалидно', () {
      expect(schema.isValid(null), isFalse);
      expect(schema.isValid(<Object?>[]), isFalse);
      expect(schema.isValid(<String, Object?>{'cards': 'нет'}), isFalse);
      expect(
        schema.isValid(<String, Object?>{
          'source_exhausted': false,
          'cards': <Object?>['нет'],
        }),
        isFalse,
      );
    });
  });

  group('проекции схемы под провайдеров (A8.2)', () {
    Map<String, Object?> itemProperties(Map<String, Object?> schema) {
      final cards =
          (schema['properties']! as Map<String, Object?>)['cards']!
              as Map<String, Object?>;
      final items = cards['items']! as Map<String, Object?>;
      return items['properties']! as Map<String, Object?>;
    }

    bool containsKeyDeep(Object? node, String key) {
      if (node is Map<String, Object?>) {
        if (node.containsKey(key)) return true;
        return node.values.any((value) => containsKeyDeep(value, key));
      }
      if (node is List<Object?>) {
        return node.any((value) => containsKeyDeep(value, key));
      }
      return false;
    }

    test('OpenAI: канон как есть и независимая копия', () {
      final schema = openAiStrictCardSchema();
      expect(schema, canonicalCardsResponseSchema);
      expect(jsonEncode(schema), isNotEmpty);
      (schema['required']! as List<Object?>).add('extra');
      expect(canonicalCardsResponseSchema['required'], <String>[
        'cards',
        'source_exhausted',
      ]);
    });

    test('Gemini: nullable вместо union, типы верхним регистром, без additionalProperties', () {
      final schema = geminiCardSchema();
      final properties = itemProperties(schema);
      expect(jsonEncode(schema), isNotEmpty);

      final hint = properties['hint']! as Map<String, Object?>;
      expect(hint['type'], 'STRING');
      expect(hint['nullable'], isTrue);
      for (final prop in properties.values) {
        expect(
          (prop as Map<String, Object?>)['type'],
          isA<String>(),
          reason: 'Gemini не принимает union-типы',
        );
      }
      final rootType = schema['type'];
      expect(rootType, 'OBJECT');
      expect(containsKeyDeep(schema, 'additionalProperties'), isFalse);
      final cards =
          (schema['properties']! as Map<String, Object?>)['cards']!
              as Map<String, Object?>;
      expect(schema['propertyOrdering'], <String>['source_exhausted', 'cards']);
      final cardItemSchema = cards['items']! as Map<String, Object?>;
      expect(cardItemSchema['propertyOrdering'], <String>[
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
      ]);
      final naming = properties['card_type']! as Map<String, Object?>;
      expect(naming['enum'], <String>[
        'basic',
        'basic_reversed',
        'cloze',
        'occlusion',
      ]);
      final image = properties['image']! as Map<String, Object?>;
      expect(image['type'], 'OBJECT');
      expect(image['nullable'], isTrue);
      expect(image['required'], <String>[
        'query',
        'fallback_query',
        'kind',
        'side',
      ]);
      expect(
        properties['tags']! as Map<String, Object?>,
        containsPair('items', isA<Map<String, Object?>>()),
      );
      expect((properties['tags']! as Map<String, Object?>)['type'], 'ARRAY');
    });

    test('Anthropic: union → anyOf с null, additionalProperties сохранён', () {
      final schema = anthropicToolCardSchema();
      expect(jsonEncode(schema), isNotEmpty);
      final properties = itemProperties(schema);
      final hint = properties['hint']! as Map<String, Object?>;
      expect(hint.containsKey('type'), isFalse);
      expect(hint['anyOf'], <Object?>[
        <String, Object?>{'type': 'string'},
        <String, Object?>{'type': 'null'},
      ]);
      final cards =
          (schema['properties']! as Map<String, Object?>)['cards']!
              as Map<String, Object?>;
      final items = cards['items']! as Map<String, Object?>;
      expect(items['additionalProperties'], isFalse);
    });

    test('канон не изменился после построения проекций', () {
      openAiStrictCardSchema();
      geminiCardSchema();
      anthropicToolCardSchema();
      expect(canonicalCardsResponseSchema['required'], <String>[
        'cards',
        'source_exhausted',
      ]);
      expect(
        CardResponseSchema().isValid(validResponse()),
        isTrue,
        reason: 'Проекции не должны портить канон',
      );
    });
  });
}
