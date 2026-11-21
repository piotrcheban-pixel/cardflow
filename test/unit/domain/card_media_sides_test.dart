import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';

/// Итерация 7.19, группа C (домен): независимые коллекции изображений
/// вопроса и ответа, JSON `media_json` v2 и совместимость со старым форматом.
void main() {
  CardImageUpload upload(String name) => CardImageUpload(
    fileName: name,
    mimeType: 'image/png',
    bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47]),
  );

  group('CardMediaSides: media_json v2', () {
    test('старый массив читается как изображения вопроса', () {
      final CardMediaSides sides = CardMediaSides.decode('["a","b"]');
      expect(sides.question, <String>['a', 'b']);
      expect(sides.answer, isEmpty);
      expect(sides.all, <String>['a', 'b']);
    });

    test('v2: обе стороны независимы', () {
      final CardMediaSides sides = CardMediaSides.decode(
        '{"version":2,"question":["q1","q2"],"answer":["a1"]}',
      );
      expect(sides.question, <String>['q1', 'q2']);
      expect(sides.answer, <String>['a1']);
      expect(sides.all, <String>['q1', 'q2', 'a1']);
    });

    test('encode → decode сохраняет стороны и версию', () {
      const CardMediaSides source = CardMediaSides(
        question: <String>['q1'],
        answer: <String>['a1', 'a2'],
      );
      final String encoded = source.encode();
      final Map<String, Object?> json = (jsonDecode(encoded) as Map)
          .cast<String, Object?>();
      expect(json['version'], 2);
      expect(CardMediaSides.decode(encoded).question, <String>['q1']);
      expect(CardMediaSides.decode(encoded).answer, <String>['a1', 'a2']);
    });

    test('пустой media_json → пустые стороны', () {
      expect(CardMediaSides.decode('[]').isEmpty, isTrue);
      expect(
        CardMediaSides.decode('{"version":2,"question":[],"answer":[]}')
            .isEmpty,
        isTrue,
      );
    });

    test('битый JSON → FormatException, tryDecode → null', () {
      expect(() => CardMediaSides.decode('{oops'), throwsFormatException);
      expect(CardMediaSides.tryDecode('{oops'), isNull);
      expect(
        () => CardMediaSides.decode('{"version":9}'),
        throwsFormatException,
      );
    });

    test('нестроковые элементы отбрасываются', () {
      final CardMediaSides sides = CardMediaSides.decode('[1,"a",null]');
      expect(sides.question, <String>['a']);
    });
  });

  group('Card: вопрос и ответ', () {
    Card card({
      List<String> question = const <String>[],
      List<String> answer = const <String>[],
    }) {
      return Card(
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Вопрос',
        back: 'Ответ',
        cardType: CardType.basic,
        state: CardState.newCard,
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
        questionMediaIds: question,
        answerMediaIds: answer,
      );
    }

    test('mediaIds — объединение сторон в порядке «вопрос → ответ»', () {
      final Card value = card(question: <String>['q1'], answer: <String>['a1']);
      expect(value.mediaIds, <String>['q1', 'a1']);
      expect(value.primaryMediaId, 'q1');
    });

    test('primaryMediaId — первое изображение вопроса, иначе ответа', () {
      expect(card(answer: <String>['a1']).primaryMediaId, 'a1');
    });

    test('равенство учитывает обе коллекции', () {
      expect(
        card(question: <String>['q1']),
        isNot(equals(card(answer: <String>['q1']))),
      );
    });
  });

  group('CardDraft: независимые загрузки сторон', () {
    test('hasImage учитывает обе стороны и новые файлы', () {
      expect(const CardDraft(front: 'q', back: 'a').hasImage, isFalse);
      expect(
        const CardDraft(
          front: 'q',
          back: 'a',
          answerUploads: <CardImageUpload>[],
        ).hasImage,
        isFalse,
      );
      expect(
        CardDraft(
          front: 'q',
          back: 'a',
          answerUploads: <CardImageUpload>[upload('a.png')],
        ).hasImage,
        isTrue,
      );
    });

    test('normalized сохраняет обе коллекции и обе загрузки', () {
      final CardDraft draft = CardDraft(
        front: '  Вопрос  ',
        back: ' Ответ ',
        questionMediaIds: const <String>['q1'],
        answerMediaIds: const <String>['a1'],
        questionUploads: <CardImageUpload>[upload('q.png')],
        answerUploads: <CardImageUpload>[upload('a.png')],
      ).normalized();
      expect(draft.front, 'Вопрос');
      expect(draft.questionMediaIds, <String>['q1']);
      expect(draft.answerMediaIds, <String>['a1']);
      expect(draft.questionUploads, hasLength(1));
      expect(draft.answerUploads, hasLength(1));
    });

    test('occlusion требует изображение на стороне вопроса', () {
      const String occlusionJson = '{"version":1,"masks":[]}';
      final CardDraft answerOnly = CardDraft(
        front: 'q',
        back: 'a',
        answerMediaIds: const <String>['a1'],
        occlusionJson: occlusionJson,
      );
      expect(
        answerOnly.validate()[CardDraftField.occlusion],
        CardValidationError.occlusionImageMissing,
      );
      final CardDraft withQuestion = CardDraft(
        front: 'q',
        back: 'a',
        questionMediaIds: const <String>['q1'],
        occlusionJson: occlusionJson,
      );
      expect(
        withQuestion.validate()[CardDraftField.occlusion],
        isNot(CardValidationError.occlusionImageMissing),
      );
    });

    test('равенство учитывает стороны', () {
      expect(
        const CardDraft(
          front: 'q',
          back: 'a',
          questionMediaIds: <String>['q1'],
        ),
        isNot(
          const CardDraft(
            front: 'q',
            back: 'a',
            answerMediaIds: <String>['q1'],
          ),
        ),
      );
    });
  });
}
