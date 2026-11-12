import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';

void main() {
  final created = DateTime.utc(2026, 11, 12, 10);
  final updated = DateTime.utc(2026, 11, 12, 11);

  Card buildCard() => Card(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Вопрос',
    back: 'Ответ',
    hint: 'Подсказка',
    cardType: CardType.basic,
    tags: const <String>['тег'],
    mediaIds: const <String>['media-1'],
    sourceExcerpt: 'Цитата',
    state: CardState.newCard,
    due: DateTime.utc(2026, 11, 13),
    createdAt: created,
    updatedAt: updated,
  );

  group('CardType/CardState wire', () {
    test('wire-имена соответствуют SPEC', () {
      expect(CardType.basic.wireName, 'basic');
      expect(CardType.basicReversed.wireName, 'basic_reversed');
      expect(CardType.cloze.wireName, 'cloze');
      expect(CardState.newCard.wireName, 'new');
      expect(CardState.learning.wireName, 'learning');
      expect(CardState.review.wireName, 'review');
      expect(CardState.relearning.wireName, 'relearning');
    });

    test('fromWire разбирает значения и бросает FormatException на мусоре', () {
      expect(CardType.fromWire('cloze'), CardType.cloze);
      expect(CardState.fromWire('relearning'), CardState.relearning);
      expect(() => CardType.fromWire('audio'), throwsFormatException);
      expect(() => CardState.fromWire('suspended'), throwsFormatException);
    });
  });

  group('Card', () {
    test('равенство учитывает все поля, включая списки', () {
      expect(buildCard(), equals(buildCard()));
      expect(buildCard().hashCode, equals(buildCard().hashCode));
    });

    test('различие в списках/полях ловится', () {
      final same = buildCard();
      expect(
        Card(
          id: same.id,
          deckId: same.deckId,
          front: same.front,
          back: same.back,
          hint: same.hint,
          cardType: same.cardType,
          tags: const <String>['другой'],
          mediaIds: same.mediaIds,
          sourceExcerpt: same.sourceExcerpt,
          state: same.state,
          due: same.due,
          createdAt: created,
          updatedAt: updated,
        ),
        isNot(equals(same)),
      );
      expect(
        Card(
          id: same.id,
          deckId: same.deckId,
          front: same.front,
          back: same.back,
          hint: same.hint,
          cardType: same.cardType,
          tags: same.tags,
          mediaIds: const <String>[],
          sourceExcerpt: same.sourceExcerpt,
          state: same.state,
          due: same.due,
          createdAt: created,
          updatedAt: updated,
        ),
        isNot(equals(same)),
      );
      expect(
        Card(
          id: same.id,
          deckId: same.deckId,
          front: same.front,
          back: same.back,
          hint: same.hint,
          cardType: same.cardType,
          tags: same.tags,
          mediaIds: same.mediaIds,
          sourceExcerpt: same.sourceExcerpt,
          state: CardState.review,
          due: same.due,
          createdAt: created,
          updatedAt: updated,
        ),
        isNot(equals(same)),
      );
    });

    test('toString содержит id, колоду и тип', () {
      final text = buildCard().toString();
      expect(text, contains('card-1'));
      expect(text, contains('deck-1'));
      expect(text, contains('basic'));
    });
  });
}
