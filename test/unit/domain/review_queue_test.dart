import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review_queue.dart';

/// Красная фаза итерации 2: состав и порядок очереди классической сессии
/// (SPEC A7.2, ADR-008).
void main() {
  final now = DateTime.utc(2026, 11, 13, 12);

  Card card({
    required String id,
    CardState state = CardState.newCard,
    DateTime? due,
    DateTime? createdAt,
    DateTime? buriedUntil,
    bool suspended = false,
  }) {
    return Card(
      id: id,
      deckId: 'deck-1',
      front: 'Вопрос $id',
      back: 'Ответ $id',
      cardType: CardType.basic,
      state: state,
      due: due,
      buriedUntil: buriedUntil,
      suspended: suspended,
      createdAt: createdAt ?? DateTime.utc(2026, 11, 10),
      updatedAt: DateTime.utc(2026, 11, 10),
    );
  }

  group('ReviewQueue.build (ADR-008)', () {
    test('пустой список — пустая очередь', () {
      expect(ReviewQueue.build(<Card>[], now: now), isEmpty);
    });

    test('исключает suspended и burial в будущем', () {
      final cards = <Card>[
        card(id: 'ok'),
        card(id: 'suspended', suspended: true),
        card(id: 'buried', buriedUntil: now.add(const Duration(hours: 1))),
        card(
          id: 'unburied',
          buriedUntil: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final queue = ReviewQueue.build(cards, now: now);

      expect(queue.map((Card c) => c.id), <String>['ok', 'unburied']);
    });

    test('будущие due не входят, прошедшие — входят', () {
      final cards = <Card>[
        card(
          id: 'future',
          state: CardState.review,
          due: now.add(const Duration(days: 1)),
        ),
        card(
          id: 'past',
          state: CardState.review,
          due: now.subtract(const Duration(days: 1)),
        ),
      ];

      final queue = ReviewQueue.build(cards, now: now);

      expect(queue.map((Card c) => c.id), <String>['past']);
    });

    test('due ровно now входит (граница)', () {
      final cards = <Card>[
        card(id: 'exactly', state: CardState.learning, due: now),
      ];
      expect(ReviewQueue.build(cards, now: now), hasLength(1));
    });

    test('порядок: просроченные по due, затем новые по createdAt', () {
      final cards = <Card>[
        card(id: 'new-later', createdAt: DateTime.utc(2026, 11, 12)),
        card(
          id: 'due-later',
          state: CardState.review,
          due: now.subtract(const Duration(hours: 1)),
        ),
        card(id: 'new-earlier', createdAt: DateTime.utc(2026, 11, 11)),
        card(
          id: 'due-earlier',
          state: CardState.relearning,
          due: now.subtract(const Duration(days: 2)),
        ),
      ];

      final queue = ReviewQueue.build(cards, now: now);

      expect(queue.map((Card c) => c.id), <String>[
        'due-earlier',
        'due-later',
        'new-earlier',
        'new-later',
      ]);
    });

    test('тай-брек по id детерминирован', () {
      final due = now.subtract(const Duration(hours: 1));
      final createdAt = DateTime.utc(2026, 11, 10);
      final cards = <Card>[
        card(id: 'b', state: CardState.review, due: due),
        card(id: 'a', state: CardState.review, due: due),
        card(id: 'd', createdAt: createdAt),
        card(id: 'c', createdAt: createdAt),
      ];

      final queue = ReviewQueue.build(cards, now: now);

      expect(queue.map((Card c) => c.id), <String>['a', 'b', 'c', 'd']);
    });

    test('новая карточка с due в прошлом попадает в новые (после due)', () {
      final cards = <Card>[
        card(id: 'new-with-due', due: now.subtract(const Duration(days: 3))),
        card(
          id: 'due',
          state: CardState.review,
          due: now.subtract(const Duration(hours: 1)),
        ),
      ];

      final queue = ReviewQueue.build(cards, now: now);

      expect(queue.map((Card c) => c.id), <String>['due', 'new-with-due']);
    });

    test('исходный список не мутируется', () {
      final cards = <Card>[
        card(id: 'new-2', createdAt: DateTime.utc(2026, 11, 12)),
        card(id: 'new-1', createdAt: DateTime.utc(2026, 11, 11)),
      ];
      final before = cards.map((Card c) => c.id).toList();

      ReviewQueue.build(cards, now: now);

      expect(cards.map((Card c) => c.id), before);
    });
  });
}
