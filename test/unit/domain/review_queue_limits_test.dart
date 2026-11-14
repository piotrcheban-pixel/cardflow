import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review_queue.dart';

import '../../helpers/decks_fakes.dart';

void main() {
  final DateTime now = DateTime.utc(2026, 11, 14, 12);

  List<Card> cards() => <Card>[
    for (int index = 0; index < 3; index++)
      makeCard(
        id: 'due-$index',
        deckId: 'deck-1',
        front: 'Просроченная $index',
        state: CardState.review,
        due: now.subtract(Duration(hours: 3 - index)),
        createdAt: DateTime.utc(2026, 11, 1),
      ),
    for (int index = 0; index < 4; index++)
      makeCard(
        id: 'new-$index',
        deckId: 'deck-1',
        front: 'Новая $index',
        createdAt: DateTime.utc(2026, 11, 2 + index),
      ),
  ];

  group('ReviewQueue — дневные лимиты (A6.6, ADR-019 §2)', () {
    test('0 — без ограничения, порядок ADR-008 сохранён', () {
      final List<Card> queue = ReviewQueue.build(cards(), now: now);
      expect(queue.length, 7);
      expect(queue.first.id, 'due-0');
      expect(queue.last.id, 'new-3');
    });

    test('reviewLimit обрезает просроченные, newLimit — новые', () {
      final List<Card> queue = ReviewQueue.build(
        cards(),
        now: now,
        newLimit: 2,
        reviewLimit: 1,
      );
      expect(queue.map((Card card) => card.id).toList(), <String>[
        'due-0',
        'new-0',
        'new-1',
      ]);
    });

    test('лимит больше доступного не добавляет карточек', () {
      final List<Card> queue = ReviewQueue.build(
        cards(),
        now: now,
        newLimit: 100,
        reviewLimit: 100,
      );
      expect(queue.length, 7);
    });

    test('0 — дневной лимит исчерпан: карточек в сессии нет (ADR-019 §8)', () {
      final List<Card> exhausted = ReviewQueue.build(
        cards(),
        now: now,
        newLimit: 0,
        reviewLimit: 0,
      );
      expect(
        exhausted,
        isEmpty,
        reason: 'остаток дня 0 — очередь пуста, а не «без ограничения»',
      );
    });

    test('остаток дня обрезает каждую часть отдельно (L45)', () {
      // Вторая сессия того же дня: новые израсходованы (0 из 2), повторных
      // осталось 2 из 3.
      final List<Card> queue = ReviewQueue.build(
        cards(),
        now: now,
        newLimit: 0,
        reviewLimit: 2,
      );
      expect(queue.map((Card card) => card.id).toList(), <String>[
        'due-0',
        'due-1',
      ]);
    });
  });
}
