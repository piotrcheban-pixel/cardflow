import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart' as cards;
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';

/// Красная фаза итерации 2: маппинг доменной карточки и FSRS-снимка.
///
/// После унификации `CardState` (T1) `scheduling.state` и `cards.CardState` —
/// один enum; до неё сравнение падает (ожидаемая причина красной фазы).
void main() {
  final now = DateTime.utc(2026, 11, 13, 12);
  final scheduler = FsrsScheduler();

  cards.Card card({
    String id = 'card-1',
    String? fsrsJson,
    DateTime? due,
    cards.CardState state = cards.CardState.newCard,
  }) {
    return cards.Card(
      id: id,
      deckId: 'deck-1',
      front: 'Вопрос',
      back: 'Ответ',
      hint: 'Подсказка',
      cardType: cards.CardType.basic,
      tags: const <String>['тег'],
      state: state,
      fsrsJson: fsrsJson,
      due: due,
      createdAt: DateTime.utc(2026, 11, 12, 10),
      updatedAt: DateTime.utc(2026, 11, 12, 10),
    );
  }

  group('CardSchedulingMapper.toSchedulingCard', () {
    test('новая карточка: состояние new, шаг 0, due = now', () {
      final scheduling = CardSchedulingMapper.toSchedulingCard(
        card(),
        now: now,
      );

      expect(scheduling.cardId, 'card-1');
      expect(scheduling.state, cards.CardState.newCard);
      expect(scheduling.step, 0);
      expect(scheduling.due, now);
      expect(scheduling.lastReview, isNull);
      expect(scheduling.stability, isNull);
      expect(scheduling.difficulty, isNull);
    });

    test('due карточки используется, если он задан', () {
      final due = DateTime.utc(2026, 11, 14, 9);
      final scheduling = CardSchedulingMapper.toSchedulingCard(
        card(due: due),
        now: now,
      );
      expect(scheduling.due, due);
    });

    test('карточка с fsrs_json: снимок восстанавливается из JSON', () {
      final afterReview = scheduler
          .review(
            SchedulingCard.newCard(cardId: 'card-1', now: now),
            Rating.good,
            now: now,
          )
          .card;
      final json = afterReview.toJson();

      final scheduling = CardSchedulingMapper.toSchedulingCard(
        card(
          fsrsJson: _encode(json),
          due: afterReview.due,
          state: cards.CardState.learning,
        ),
        now: now.add(const Duration(days: 1)),
      );

      expect(scheduling, afterReview);
    });

    test('битый fsrs_json — FormatException, а не тихий сброс в new', () {
      expect(
        () => CardSchedulingMapper.toSchedulingCard(
          card(fsrsJson: '{"state": "нет-такого"}', due: now),
          now: now,
        ),
        throwsFormatException,
      );
    });

    test('fsrs_json чужой карточки — FormatException', () {
      final json = SchedulingCard.newCard(
        cardId: 'other-card',
        now: now,
      ).toJson();
      expect(
        () => CardSchedulingMapper.toSchedulingCard(
          card(fsrsJson: _encode(json), due: now),
          now: now,
        ),
        throwsFormatException,
      );
    });
  });

  group('CardSchedulingMapper.applyOutcome', () {
    test('обновляет state/fsrs_json/due/updatedAt, сохраняя содержимое', () {
      final original = card();
      final outcome = scheduler
          .review(
            SchedulingCard.newCard(cardId: 'card-1', now: now),
            Rating.good,
            now: now,
          )
          .card;
      final updatedAt = now.add(const Duration(seconds: 3));

      final applied = CardSchedulingMapper.applyOutcome(
        original,
        outcome,
        updatedAt: updatedAt,
      );

      expect(applied.state, cards.CardState.learning);
      expect(applied.due, outcome.due);
      expect(applied.fsrsJson, isNotNull);
      expect(applied.updatedAt, updatedAt);
      expect(applied.id, original.id);
      expect(applied.deckId, original.deckId);
      expect(applied.front, original.front);
      expect(applied.back, original.back);
      expect(applied.hint, original.hint);
      expect(applied.tags, original.tags);
      expect(applied.cardType, original.cardType);
      expect(applied.createdAt, original.createdAt);
    });

    test('round-trip: applyOutcome → toSchedulingCard == outcome', () {
      final outcome = scheduler
          .review(
            SchedulingCard.newCard(cardId: 'card-1', now: now),
            Rating.easy,
            now: now,
          )
          .card;
      final applied = CardSchedulingMapper.applyOutcome(
        card(),
        outcome,
        updatedAt: now,
      );

      final scheduling = CardSchedulingMapper.toSchedulingCard(
        applied,
        now: now.add(const Duration(days: 20)),
      );

      expect(scheduling, outcome);
    });
  });
}

String _encode(Map<String, dynamic> json) => jsonEncode(json);
