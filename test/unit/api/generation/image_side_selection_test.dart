import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generated_card_image_side.dart';

/// Итерация 7.19, группа B: ИИ независимо выбирает изображения обеим сторонам
/// (схема `gen-ru-v9`, `question_image_ids` / `answer_image_ids`).
void main() {
  const String source = 'Материал про воздухопроницаемость окна.';
  const CardContentValidator validator = CardContentValidator();
  const Set<String> catalog = <String>{'img1', 'img2', 'img3'};

  Map<String, Object?> cardJson({
    Object? questionIds = const <String>[],
    Object? answerIds = const <String>[],
    Object? image,
    String front = 'Какой формулой рассчитывают воздухопроницаемость окна?',
    String back = r'$G = A \cdot \Delta P^{0.67} / R$',
  }) {
    return <String, Object?>{
      'front': front,
      'back': back,
      'hint': null,
      'tags': <Object?>['формулы'],
      'card_type': 'basic',
      'source_excerpt': null,
      'source_file': null,
      'section_id': null,
      'question_image_ids': questionIds,
      'answer_image_ids': answerIds,
      'image': image,
    };
  }

  GeneratedCard validate(Map<String, Object?> card) {
    final List<GeneratedCard> cards = validator.validateResponse(
      <String, Object?>{
        'cards': <Object?>[card],
      },
      sourceText: source,
      imageIds: catalog,
    );
    expect(cards, hasLength(1), reason: 'карточка v9 не отбрасывается');
    return cards.single;
  }

  test('B13: модель назначает разные изображения вопросу и ответу', () {
    final GeneratedCard card = validate(
      cardJson(questionIds: <String>['img1'], answerIds: <String>['img2']),
    );
    expect(card.questionImageIds, <String>['img1']);
    expect(card.answerImageIds, <String>['img2']);
  });

  test('B14: несколько изображений на каждой стороне', () {
    final GeneratedCard card = validate(
      cardJson(
        questionIds: <String>['img1', 'img2'],
        answerIds: <String>['img3'],
      ),
    );
    expect(card.questionImageIds, <String>['img1', 'img2']);
    expect(card.answerImageIds, <String>['img3']);
  });

  test('B15: обе коллекции могут быть пустыми — карточка остаётся', () {
    final GeneratedCard card = validate(cardJson());
    expect(card.questionImageIds, isEmpty);
    expect(card.answerImageIds, isEmpty);
    expect(card.hasImages, isFalse);
  });

  test('B19: неизвестный id безопасно отбрасывается с пометкой', () {
    final GeneratedCard card = validate(
      cardJson(questionIds: <String>['img1', 'imgXX']),
    );
    expect(card.questionImageIds, <String>['img1']);
    expect(card.issues, contains(CardIssueCode.imageIdUnknown));
  });

  test(
    'B20: один id в обеих коллекциях остаётся только на стороне вопроса',
    () {
      final GeneratedCard card = validate(
        cardJson(
          questionIds: <String>['img1'],
          answerIds: <String>['img1', 'img2'],
        ),
      );
      expect(card.questionImageIds, <String>['img1']);
      expect(card.answerImageIds, <String>['img2']);
      expect(card.issues, contains(CardIssueCode.imageDuplicatedSide));
    },
  );

  test(
    'B21: ответ старой схемы v8 (image_id) читается как изображение вопроса',
    () {
      final Map<String, Object?> legacy = <String, Object?>{
        'front': 'Что изображено на схеме?',
        'back': 'Схема фермы.',
        'hint': null,
        'tags': <Object?>['фермы'],
        'card_type': 'basic',
        'source_excerpt': null,
        'source_file': null,
        'image_id': 'img2',
        'image': <String, Object?>{
          'query': 'truss diagram',
          'fallback_query': 'truss',
          'kind': 'diagram',
        },
      };
      final GeneratedCard card = validate(legacy);
      expect(card.questionImageIds, <String>['img2']);
      expect(card.answerImageIds, isEmpty);
      expect(card.imageQuery, 'truss diagram');
      expect(card.imageKind, GeneratedCardImageKind.diagram);
    },
  );

  test('ответ v5 (image_query) читается как поиск для стороны вопроса', () {
    final GeneratedCard card = validate(<String, Object?>{
      'front': 'Что такое ферма?',
      'back': 'Стержневая конструкция.',
      'hint': null,
      'tags': <Object?>['фермы'],
      'card_type': 'basic',
      'source_excerpt': null,
      'source_file': null,
      'image_id': null,
      'image_query': 'truss bridge',
    });
    expect(card.imageQuery, 'truss bridge');
    expect(card.imageSide, GeneratedCardImageSide.question);
  });

  test('image.side=answer: внешний поиск нацелен на сторону ответа', () {
    final GeneratedCard card = validate(
      cardJson(
        image: <String, Object?>{
          'query': 'window air flow diagram',
          'fallback_query': 'window infiltration',
          'kind': 'diagram',
          'side': 'answer',
        },
      ),
    );
    expect(card.imageSide, GeneratedCardImageSide.answer);
    expect(card.imageQuery, 'window air flow diagram');
  });

  test('image.side=none: поиск не запрашивается', () {
    final GeneratedCard card = validate(
      cardJson(
        image: <String, Object?>{
          'query': 'abstract concept',
          'fallback_query': 'concept',
          'kind': 'illustration',
          'side': 'none',
        },
      ),
    );
    expect(card.imageSide, GeneratedCardImageSide.none);
  });

  test('GeneratedCard.image — только изображение вопроса (7.19)', () {
    final GeneratedCard answerOnly = GeneratedCard(
      front: 'q',
      back: 'a',
      cardType: CardType.basic,
      answerImages: <GeneratedCardImage>[
        GeneratedCardImage(
          bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 1, 2, 3]),
          mediaType: AttachmentMediaType.jpeg,
          query: 'formula',
        ),
      ],
    );
    expect(answerOnly.image, isNull, reason: 'ответ не попадает на лицевую');
    expect(answerOnly.hasImages, isTrue);

    final GeneratedCard both = answerOnly.copyWith(
      questionImages: <GeneratedCardImage>[
        GeneratedCardImage(
          bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 4, 5, 6]),
          mediaType: AttachmentMediaType.jpeg,
          query: 'scheme',
        ),
      ],
    );
    expect(both.image, same(both.questionImages.single));
  });

  test('канон-схема v9: ответ с массивами валиден', () {
    final CardResponseSchema schema = CardResponseSchema();
    final Map<String, Object?> payload = <String, Object?>{
      'cards': <Object?>[cardJson()],
      'source_exhausted': false,
    };
    expect(schema.isValid(payload), isTrue);
    final CardPayloadValidation split = schema.splitValid(payload);
    expect(split.cards, hasLength(1));
    expect(split.rejectedCards, 0);
  });

  test('канон-схема v9: image — необязательный объект', () {
    final CardResponseSchema schema = CardResponseSchema();
    final Map<String, Object?> payload = <String, Object?>{
      'cards': <Object?>[
        cardJson(
          image: <String, Object?>{
            'query': 'formula diagram',
            'fallback_query': 'formula',
            'kind': 'diagram',
            'side': 'answer',
          },
        ),
      ],
      'source_exhausted': false,
    };
    expect(schema.isValid(payload), isTrue);
  });
}
