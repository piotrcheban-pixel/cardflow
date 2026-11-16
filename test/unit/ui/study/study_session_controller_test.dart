import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/study/study_mode.dart';
import 'package:cardflow/ui/study/study_session_controller.dart';

import '../../../helpers/decks_fakes.dart';
import '../../../helpers/review_fakes.dart';

/// Общий контроллер новых режимов: FSRS только для due (7.15).
void main() {
  final DateTime now = DateTime.utc(2026, 11, 16, 12);

  Card card(String id, {CardState state = CardState.newCard, DateTime? due}) {
    return makeCard(
      id: id,
      deckId: 'deck-1',
      front: 'Вопрос $id?',
      back: 'Ответ $id',
      state: state,
      due: due,
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
    );
  }

  StudySessionController controllerWith(
    List<Card> cards, {
    StudyMode mode = StudyMode.test,
    FakeReviewRepository? reviewRepository,
    FakePracticeRepository? practiceRepository,
  }) {
    return StudySessionController(
      cards: cards,
      mode: mode,
      scheduler: FsrsScheduler(),
      reviewRepository:
          reviewRepository ??
          (FakeReviewRepository()..previousCard = cards.first),
      practiceRepository: practiceRepository ?? FakePracticeRepository(),
      clock: () => now,
    );
  }

  test('due/новая карточка пишет FSRS с mode теста', () async {
    final reviews = FakeReviewRepository()..previousCard = card('new');
    final practice = FakePracticeRepository();
    final controller = controllerWith(
      <Card>[card('new')],
      reviewRepository: reviews,
      practiceRepository: practice,
    )..start();

    expect(controller.state.total, 1);
    expect(controller.state.current!.writesFsrs, isTrue);
    await controller.answer(rating: Rating.good, wasCorrect: true);

    expect(reviews.cardIds, <String>['new']);
    expect(reviews.modes, <String>['test']);
    expect(practice.cardIds, isEmpty);
    expect(controller.state.isCompleted, isTrue);
    expect(controller.state.correctCount, 1);
    expect(controller.state.accuracy, 100);
  });

  test('карточка с due в будущем — как тренировка, без FSRS', () async {
    final future = card(
      'future',
      state: CardState.review,
      due: now.add(const Duration(days: 3)),
    );
    final reviews = FakeReviewRepository()..previousCard = future;
    final practice = FakePracticeRepository();
    final controller = controllerWith(
      <Card>[future],
      reviewRepository: reviews,
      practiceRepository: practice,
    )..start();

    expect(controller.state.current!.writesFsrs, isFalse);
    await controller.answer(rating: Rating.again, wasCorrect: false);

    expect(practice.cardIds, <String>['future']);
    expect(practice.modes, <String>['test']);
    expect(reviews.cardIds, isEmpty);
    expect(controller.state.wrongCount, 1);
  });

  test('режим Тренировка/Пары не пишет FSRS даже для due', () async {
    final reviews = FakeReviewRepository()
      ..previousCard = card('due', state: CardState.review, due: now);
    final practice = FakePracticeRepository();
    final controller = controllerWith(
      <Card>[card('due', state: CardState.review, due: now)],
      mode: StudyMode.practice,
      reviewRepository: reviews,
      practiceRepository: practice,
    )..start();

    await controller.answer(rating: Rating.good, wasCorrect: true);
    expect(reviews.cardIds, isEmpty);
    expect(practice.modes, <String>['practice']);
  });

  test('undo откатывает запись FSRS и счётчики', () async {
    final reviews = FakeReviewRepository()..previousCard = card('new');
    final controller = controllerWith(<Card>[
      card('new'),
    ], reviewRepository: reviews)..start();

    await controller.answer(rating: Rating.good, wasCorrect: true);
    expect(controller.state.index, 1);
    final bool undone = await controller.undo();

    expect(undone, isTrue);
    expect(reviews.undone, hasLength(1));
    expect(controller.state.index, 0);
    expect(controller.state.correctCount, 0);
    expect(controller.state.isCompleted, isFalse);
  });

  test('undo в тренировочной ветке удаляет запись журнала', () async {
    final future = card(
      'future',
      state: CardState.review,
      due: now.add(const Duration(days: 1)),
    );
    final practice = FakePracticeRepository();
    final controller = controllerWith(<Card>[
      future,
    ], practiceRepository: practice)..start();

    await controller.answer(rating: Rating.hard, wasCorrect: true);
    await controller.undo();
    expect(practice.undoneLogIds, <String>['practice-log-1']);
    expect(practice.undoModes, <String>[
      'test',
    ], reason: 'undo в режиме ищет запись своего mode');
    expect(controller.state.index, 0);
  });

  test('ошибка записи не сдвигает очередь и снимает busy', () async {
    final reviews = FakeReviewRepository()..previousCard = card('new');
    reviews.recordError = StateError('БД недоступна');
    final controller = controllerWith(<Card>[
      card('new'),
    ], reviewRepository: reviews)..start();

    await expectLater(
      controller.answer(rating: Rating.good, wasCorrect: true),
      throwsStateError,
    );
    expect(controller.state.index, 0);
    expect(controller.state.busy, isFalse);
  });

  test('«Повторить ошибки» оставляет только неверные карточки', () async {
    final cards = <Card>[card('a'), card('b'), card('c')];
    final reviews = FakeReviewRepository()..previousCard = cards.first;
    final controller = controllerWith(cards, reviewRepository: reviews)
      ..start();

    await controller.answer(rating: Rating.good, wasCorrect: true);
    await controller.answer(rating: Rating.again, wasCorrect: false);
    await controller.answer(rating: Rating.again, wasCorrect: false);
    expect(controller.state.isCompleted, isTrue);
    expect(controller.wrongCards.map((Card c) => c.id), <String>['b', 'c']);

    controller.repeatMistakes();
    expect(controller.state.total, 2);
    expect(controller.state.index, 0);
    expect(controller.state.correctCount, 0);
    expect(controller.state.wrongCount, 0);
  });

  test('прогресс и точность считаются по ответам', () async {
    final cards = <Card>[card('a'), card('b'), card('c'), card('d')];
    final reviews = FakeReviewRepository()..previousCard = cards.first;
    final controller = controllerWith(cards, reviewRepository: reviews)
      ..start();

    await controller.answer(rating: Rating.good, wasCorrect: true);
    await controller.answer(rating: Rating.good, wasCorrect: true);
    await controller.answer(rating: Rating.again, wasCorrect: false);

    expect(controller.state.answeredCount, 3);
    expect(controller.state.total, 4);
    expect(controller.state.accuracy, 67);
    expect(controller.state.current!.card.id, 'd');
  });
}
