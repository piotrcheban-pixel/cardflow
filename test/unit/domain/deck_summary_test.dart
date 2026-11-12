import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);

  Deck deck() => Deck(
    id: 'deck-1',
    name: 'Испанский',
    settings: const <String, Object?>{},
    createdAt: now,
    updatedAt: now,
  );

  group('DeckSummary', () {
    test('счётчики по умолчанию нулевые, hasCards = false', () {
      final summary = DeckSummary(deck: deck());
      expect(summary.totalCards, 0);
      expect(summary.newCards, 0);
      expect(summary.inProgressCards, 0);
      expect(summary.dueCards, 0);
      expect(summary.hasCards, isFalse);
    });

    test('hasCards истинно при наличии карточек', () {
      expect(DeckSummary(deck: deck(), totalCards: 1).hasCards, isTrue);
    });

    test('равенство учитывает все счётчики', () {
      expect(
        DeckSummary(deck: deck(), totalCards: 3, dueCards: 1),
        equals(DeckSummary(deck: deck(), totalCards: 3, dueCards: 1)),
      );
      expect(
        DeckSummary(deck: deck(), totalCards: 3) ==
            DeckSummary(deck: deck(), totalCards: 4),
        isFalse,
      );
      expect(
        DeckSummary(deck: deck(), totalCards: 3).hashCode,
        DeckSummary(deck: deck(), totalCards: 3).hashCode,
      );
    });

    test('toString содержит имя и счётчики', () {
      final text = DeckSummary(
        deck: deck(),
        totalCards: 5,
        newCards: 2,
        inProgressCards: 1,
        dueCards: 3,
      ).toString();
      expect(text, contains('Испанский'));
      expect(text, contains('total=5'));
      expect(text, contains('due=3'));
    });
  });
}
