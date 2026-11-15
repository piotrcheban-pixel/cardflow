import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/practice_queue.dart';

import '../../helpers/decks_fakes.dart';

/// Очередь режима «Тренировка» (ADR-025, итерация 7.11): никакого FSRS-фильтра.
void main() {
  final DateTime now = DateTime.utc(2026, 11, 15, 19);

  test(
    'входят новые карточки, просроченные и будущие — всё, кроме suspended',
    () {
      final List<Card> cards = <Card>[
        makeCard(
          id: 'new',
          deckId: 'deck-1',
          front: 'Новая',
          createdAt: DateTime.utc(2026, 11, 15, 18),
        ),
        makeCard(
          id: 'due-past',
          deckId: 'deck-1',
          front: 'Просроченная',
          state: CardState.review,
          due: now.subtract(const Duration(days: 2)),
          createdAt: DateTime.utc(2026, 11, 10),
        ),
        makeCard(
          id: 'due-future',
          deckId: 'deck-1',
          front: 'Будущая',
          state: CardState.review,
          due: now.add(const Duration(days: 5)),
          createdAt: DateTime.utc(2026, 11, 11),
        ),
        makeCard(
          id: 'learning',
          deckId: 'deck-1',
          front: 'Изучаемая',
          state: CardState.learning,
          due: now.add(const Duration(minutes: 10)),
          createdAt: DateTime.utc(2026, 11, 12),
        ),
        makeCard(
          id: 'suspended',
          deckId: 'deck-1',
          front: 'Приостановлена',
          suspended: true,
          createdAt: DateTime.utc(2026, 11, 9),
        ),
      ];

      final List<Card> queue = PracticeQueue.build(cards);

      expect(queue.map((Card card) => card.id), <String>[
        'due-past',
        'due-future',
        'learning',
        'new',
      ], reason: 'порядок — createdAt ASC, приостановленные исключены');
    },
  );

  test('buried-карточка входит: тренировка не учитывает статус FSRS', () {
    final List<Card> cards = <Card>[
      makeCard(
        id: 'buried',
        deckId: 'deck-1',
        front: 'Отложенная',
        state: CardState.review,
        due: now.subtract(const Duration(days: 1)),
        buriedUntil: now.add(const Duration(days: 1)),
      ),
    ];

    expect(PracticeQueue.build(cards), hasLength(1));
  });

  test('пустая колода — пустая очередь', () {
    expect(PracticeQueue.build(const <Card>[]), isEmpty);
  });
}
