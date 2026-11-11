import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final now = DateTime.utc(2026, 11, 11, 12);

  group('SchedulingCard: снимок состояния для FSRS', () {
    test('новая карточка имеет состояние new и due = now', () {
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      expect(card.cardId, 'card-1');
      expect(card.state, CardState.newState);
      expect(card.due, now);
      expect(card.lastReview, isNull);
      expect(card.step, 0);
    });

    test('toJson/fromJson сохраняют состояние без потерь', () {
      final scheduler = FsrsScheduler();
      final newCard = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final reviewed = scheduler.review(newCard, Rating.good, now: now).card;

      final restored = SchedulingCard.fromJson(reviewed.toJson());

      expect(restored, reviewed);
      expect(restored.state, reviewed.state);
      expect(restored.step, reviewed.step);
      expect(restored.due, reviewed.due);
      expect(restored.lastReview, reviewed.lastReview);
      expect(restored.stability, reviewed.stability);
      expect(restored.difficulty, reviewed.difficulty);
    });
  });

  group('FsrsScheduler: интервалы и прогноз для кнопок A7.2', () {
    test('прогноз содержит все четыре оценки в порядке Rating.values', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final preview = scheduler.previewIntervals(card, now: now);

      expect(preview.keys.toList(), Rating.values);
    });

    test('для новой карточки интервалы соответствуют шагам обучения FSRS', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final preview = scheduler.previewIntervals(card, now: now);

      // learningSteps по умолчанию: 1 минута и 10 минут.
      expect(preview[Rating.again], const Duration(minutes: 1));
      expect(preview[Rating.hard], const Duration(minutes: 5, seconds: 30));
      expect(preview[Rating.good], const Duration(minutes: 10));
      expect(preview[Rating.easy], const Duration(days: 16));
    });

    test('прогноз монотонен: Again < Hard < Good < Easy (A7.2)', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final preview = scheduler.previewIntervals(card, now: now);
      final durations = <Rating, Duration>{
        for (final rating in Rating.values) rating: preview[rating]!,
      };

      expect(durations[Rating.again]!, lessThan(durations[Rating.hard]!));
      expect(durations[Rating.hard]!, lessThan(durations[Rating.good]!));
      expect(durations[Rating.good]!, lessThan(durations[Rating.easy]!));
    });

    test('оценка Good переводит новую карточку на второй шаг обучения', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final outcome = scheduler.review(card, Rating.good, now: now);

      expect(outcome.reviewedAt, now);
      expect(outcome.card.state, CardState.learning);
      expect(outcome.card.step, 1);
      expect(outcome.card.due, now.add(const Duration(minutes: 10)));
      expect(outcome.card.lastReview, now);
      expect(outcome.card.stability, isNotNull);
      expect(outcome.card.difficulty, isNotNull);
    });

    test('оценка Again возвращает карточку на первый шаг обучения', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final outcome = scheduler.review(card, Rating.again, now: now);

      expect(outcome.card.state, CardState.learning);
      expect(outcome.card.step, 0);
      expect(outcome.card.due, now.add(const Duration(minutes: 1)));
    });

    test('оценка Easy сразу выводит карточку в повторение', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final outcome = scheduler.review(card, Rating.easy, now: now);

      expect(outcome.card.state, CardState.review);
      expect(outcome.card.step, isNull);
      expect(outcome.card.due.difference(now), const Duration(days: 16));
    });

    test('исходная карточка не мутируется оценкой (иммутабельность)', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      scheduler.review(card, Rating.easy, now: now);

      expect(card.state, CardState.newState);
      expect(card.lastReview, isNull);
      expect(card.stability, isNull);
      expect(card.due, now);
    });

    test('низкий desiredRetention даёт более длинный интервал', () {
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final strict = FsrsScheduler(desiredRetention: 0.9);
      final relaxed = FsrsScheduler(desiredRetention: 0.8);

      final strictPreview = strict.previewIntervals(card, now: now);
      final relaxedPreview = relaxed.previewIntervals(card, now: now);

      expect(
        relaxedPreview[Rating.easy]!,
        greaterThan(strictPreview[Rating.easy]!),
      );
    });

    test('fuzzing выключен по умолчанию: прогноз детерминирован', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      final first = scheduler.previewIntervals(card, now: now);
      final second = scheduler.previewIntervals(card, now: now);

      expect(first, second);
    });
  });

  group('SchedulingCard: валидация, ошибки и сериализация', () {
    test('равные карточки равны и имеют одинаковый hashCode', () {
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final restored = SchedulingCard.fromJson(card.toJson());

      expect(restored, card);
      expect(restored.hashCode, card.hashCode);
    });

    test('fromWireName отвергает неизвестное состояние', () {
      expect(() => CardState.fromWireName('archived'), throwsArgumentError);
    });

    test('fromJson восстанавливает карточку без lastReview', () {
      final json = SchedulingCard.newCard(cardId: 'card-1', now: now).toJson();
      final restored = SchedulingCard.fromJson(json);

      expect(restored.lastReview, isNull);
      expect(restored.state, CardState.newState);
      expect(restored.step, 0);
    });

    test('toJson хранит UTC-время в ISO-8601 и состояние строкой SPEC', () {
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final json = card.toJson();

      expect(json['due'], now.toIso8601String());
      expect(json['state'], 'new');
      expect(json['lastReview'], isNull);
    });

    test('toString содержит идентификатор и состояние', () {
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);

      expect(card.toString(), contains('card-1'));
      expect(card.toString(), contains('new'));
    });

    test('конструктор требует UTC для due и lastReview', () {
      expect(
        () => SchedulingCard(
          cardId: 'card-1',
          state: CardState.learning,
          due: DateTime(2026, 11, 11, 12),
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => SchedulingCard(
          cardId: 'card-1',
          state: CardState.review,
          due: now,
          lastReview: DateTime(2026, 11, 10, 12),
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group(
    'FsrsScheduler: прогноз совпадает с фактическим планированием (A7.2)',
    () {
      test('для новой карточки: previewIntervals == due после review', () {
        final scheduler = FsrsScheduler();
        final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
        final preview = scheduler.previewIntervals(card, now: now);

        for (final rating in Rating.values) {
          final outcome = scheduler.review(card, rating, now: now);
          expect(
            outcome.card.due.difference(now),
            preview[rating],
            reason: 'оценка $rating',
          );
        }
      });

      test('для карточки в повторении: прогноз равен факту', () {
        final scheduler = FsrsScheduler();
        final newCard = SchedulingCard.newCard(cardId: 'card-1', now: now);
        final reviewCard = scheduler
            .review(newCard, Rating.easy, now: now)
            .card;
        final later = now.add(const Duration(days: 17));
        final preview = scheduler.previewIntervals(reviewCard, now: later);

        for (final rating in Rating.values) {
          final outcome = scheduler.review(reviewCard, rating, now: later);
          expect(
            outcome.card.due.difference(later),
            preview[rating],
            reason: 'оценка $rating',
          );
        }
      });
    },
  );

  group('FsrsScheduler: переходы состояний (SPEC A5)', () {
    test('второй Good в обучении переводит карточку в review', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final first = scheduler.review(card, Rating.good, now: now).card;
      expect(first.state, CardState.learning);
      expect(first.step, 1);

      final second = scheduler
          .review(first, Rating.good, now: now.add(const Duration(minutes: 10)))
          .card;
      expect(second.state, CardState.review);
      expect(second.step, isNull);
    });

    test('Again из review переводит в relearning с шагом 0', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final reviewCard = scheduler.review(card, Rating.easy, now: now).card;
      expect(reviewCard.state, CardState.review);

      final relearning = scheduler
          .review(
            reviewCard,
            Rating.again,
            now: now.add(const Duration(days: 17)),
          )
          .card;
      expect(relearning.state, CardState.relearning);
      expect(relearning.step, 0);
      expect(relearning.due, now.add(const Duration(days: 17, minutes: 10)));
    });

    test('Good из relearning завершает переобучение (review)', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final reviewCard = scheduler.review(card, Rating.easy, now: now).card;
      final afterAgain = scheduler
          .review(
            reviewCard,
            Rating.again,
            now: now.add(const Duration(days: 17)),
          )
          .card;
      final afterGood = scheduler
          .review(
            afterAgain,
            Rating.good,
            now: now.add(const Duration(days: 17, minutes: 10)),
          )
          .card;

      expect(afterGood.state, CardState.review);
      expect(afterGood.step, isNull);
    });
  });

  group('FsrsScheduler: UTC-нормализация', () {
    test('локальный now приводится к UTC в reviewedAt и due', () {
      final scheduler = FsrsScheduler();
      final card = SchedulingCard.newCard(cardId: 'card-1', now: now);
      final localNow = DateTime(2026, 11, 11, 15); // локальное время хоста

      final outcome = scheduler.review(card, Rating.good, now: localNow);

      expect(outcome.reviewedAt.isUtc, isTrue);
      expect(outcome.reviewedAt, localNow.toUtc());
      expect(outcome.card.due.isUtc, isTrue);
      expect(
        outcome.card.due,
        localNow.toUtc().add(const Duration(minutes: 10)),
      );
    });
  });
}
