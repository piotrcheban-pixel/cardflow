import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/review/drift_review_repository.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';

import '../db/test_support.dart';

/// Красная фаза итерации 2: транзакционная запись повторений и undo
/// (SPEC A5 — `review_logs` + `due`/`fsrs_json` в одной транзакции; A6.4).
void main() {
  final now = DateTime.utc(2026, 11, 13, 12);
  final scheduler = FsrsScheduler();

  late AppDatabase db;
  late DriftCardRepository cards;
  late DriftReviewRepository reviews;

  setUp(() async {
    db = AppDatabase.inMemory();
    cards = DriftCardRepository(db);
    reviews = DriftReviewRepository(db);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
  });

  tearDown(() async {
    await db.close();
  });

  SchedulingCard outcomeFor(
    SchedulingCard before,
    Rating rating, {
    DateTime? at,
  }) {
    return scheduler.review(before, rating, now: at ?? now).card;
  }

  test('recordReview: лог и карточка обновляются вместе (SPEC A5)', () async {
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      createdAt: 100,
      updatedAt: 100,
    );
    final before = (await cards.cardById('card-1'))!;
    final outcome = outcomeFor(
      SchedulingCard.newCard(cardId: 'card-1', now: now),
      Rating.good,
    );

    final undo = await reviews.recordReview(
      cardId: 'card-1',
      rating: Rating.good,
      reviewedAt: now,
      outcome: outcome,
      mode: reviewModeClassic,
      elapsed: const Duration(seconds: 7),
    );

    final updated = (await cards.cardById('card-1'))!;
    expect(updated.state, CardState.learning);
    expect(updated.due, outcome.due);
    expect(updated.updatedAt, now);
    final restored = SchedulingCard.fromJson(
      jsonDecode(updated.fsrsJson!) as Map<String, dynamic>,
    );
    expect(restored, outcome);

    final logs = await db.select(db.reviewLogs).get();
    expect(logs, hasLength(1));
    final log = logs.single;
    expect(log.id, undo.logId);
    expect(log.cardId, 'card-1');
    expect(log.rating, 3, reason: 'Good = 3 по SPEC A5');
    expect(log.reviewedAt, now.millisecondsSinceEpoch);
    expect(log.mode, reviewModeClassic);
    expect(log.recognitionFlag, 0);
    expect(
      log.scheduledDays,
      closeTo(
        const Duration(minutes: 10).inMilliseconds /
            Duration.millisecondsPerDay,
        1e-9,
      ),
    );
    expect(
      log.actualDays,
      isNull,
      reason:
          'первое повторение — фактического '
          'интервала ещё нет',
    );
    expect(log.elapsedMs, 7000);

    expect(undo.previousCard, before);
    expect(undo.previousCard.state, CardState.newCard);
    expect(undo.previousCard.fsrsJson, isNull);
  });

  test(
    'recordReview: actual_days считается от lastReview повторения',
    () async {
      final firstReviewAt = now.subtract(const Duration(days: 1));
      final first = outcomeFor(
        SchedulingCard.newCard(cardId: 'card-1', now: firstReviewAt),
        Rating.good,
        at: firstReviewAt,
      );
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        state: first.state.wireName,
        fsrsJson: jsonEncode(first.toJson()),
        due: first.due.millisecondsSinceEpoch,
        createdAt: 100,
        updatedAt: 100,
      );
      final outcome = outcomeFor(first, Rating.good);

      await reviews.recordReview(
        cardId: 'card-1',
        rating: Rating.good,
        reviewedAt: now,
        outcome: outcome,
        mode: reviewModeClassic,
      );

      final log = (await db.select(db.reviewLogs).get()).single;
      expect(log.actualDays, closeTo(1.0, 1e-9));
    },
  );

  test(
    'recordReview: несуществующая карточка — ошибка, лог не пишется',
    () async {
      final outcome = outcomeFor(
        SchedulingCard.newCard(cardId: 'нет-такой', now: now),
        Rating.good,
      );

      await expectLater(
        reviews.recordReview(
          cardId: 'нет-такой',
          rating: Rating.good,
          reviewedAt: now,
          outcome: outcome,
          mode: reviewModeClassic,
        ),
        throwsStateError,
      );
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    },
  );

  test('undoReview: удаляет лог и восстанавливает снимок карточки', () async {
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      createdAt: 100,
      updatedAt: 100,
    );
    final before = (await cards.cardById('card-1'))!;
    final outcome = outcomeFor(
      SchedulingCard.newCard(cardId: 'card-1', now: now),
      Rating.again,
    );
    final undo = await reviews.recordReview(
      cardId: 'card-1',
      rating: Rating.again,
      reviewedAt: now,
      outcome: outcome,
      mode: reviewModeClassic,
      elapsed: const Duration(seconds: 2),
    );
    expect((await cards.cardById('card-1'))!.state, isNot(CardState.newCard));

    await reviews.undoReview(undo);

    expect(await db.select(db.reviewLogs).get(), isEmpty);
    expect(await cards.cardById('card-1'), before);
  });

  test('undoReview: лог не найден — ошибка, карточка не меняется', () async {
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      createdAt: 100,
      updatedAt: 100,
    );
    final before = (await cards.cardById('card-1'))!;
    final undo = ReviewUndo(logId: 'нет-такого', previousCard: before);

    await expectLater(reviews.undoReview(undo), throwsStateError);
    expect(await cards.cardById('card-1'), before);
  });

  test(
    'атомарность: ошибка вставки лога откатывает UPDATE карточки (C6)',
    () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        createdAt: 100,
        updatedAt: 100,
      );
      final before = (await cards.cardById('card-1'))!;
      // Триггер падает на INSERT review_logs — уже после UPDATE cards.
      await db.customStatement(
        "CREATE TRIGGER fail_review_log BEFORE INSERT ON review_logs "
        "BEGIN SELECT RAISE(ABORT, 'boom'); END;",
      );
      final outcome = outcomeFor(
        SchedulingCard.newCard(cardId: 'card-1', now: now),
        Rating.good,
      );

      await expectLater(
        reviews.recordReview(
          cardId: 'card-1',
          rating: Rating.good,
          reviewedAt: now,
          outcome: outcome,
          mode: reviewModeClassic,
        ),
        throwsA(anything),
      );

      expect(await cards.cardById('card-1'), before);
      expect(await db.select(db.reviewLogs).get(), isEmpty);
    },
  );

  test('атомарность: ошибка восстановления карточки откатывает undo', () async {
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      createdAt: 100,
      updatedAt: 100,
    );
    final outcome = outcomeFor(
      SchedulingCard.newCard(cardId: 'card-1', now: now),
      Rating.good,
    );
    final undo = await reviews.recordReview(
      cardId: 'card-1',
      rating: Rating.good,
      reviewedAt: now,
      outcome: outcome,
      mode: reviewModeClassic,
    );
    // Карточки больше нет — UPDATE в undo не найдёт строку.
    await (db.delete(
      db.cards,
    )..where((table) => table.id.equals('card-1'))).go();

    await expectLater(reviews.undoReview(undo), throwsStateError);

    expect(
      await db.select(db.reviewLogs).get(),
      hasLength(1),
      reason: 'удаление лога должно откатиться вместе с транзакцией undo',
    );
  });
}
