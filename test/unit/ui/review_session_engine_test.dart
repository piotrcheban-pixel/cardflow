import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/review_fakes.dart';

/// Красная фаза итерации 2: движок классической сессии (SPEC A6.4, A7.2,
/// ADR-008) — очередь, раскрытие, оценки, undo, ошибки БД.
void main() {
  final start = DateTime.utc(2026, 11, 13, 12);

  late DateTime clockNow;
  late FakeReviewRepository repository;
  late ReviewSessionEngine engine;
  late List<Card> cards;

  DateTime now() => clockNow;

  void advance(Duration duration) => clockNow = clockNow.add(duration);

  setUp(() {
    clockNow = start;
    repository = FakeReviewRepository();
    cards = <Card>[
      makeCard(id: 'card-1', deckId: 'deck-1', front: 'Первый'),
      makeCard(
        id: 'card-2',
        deckId: 'deck-1',
        front: 'Второй',
        createdAt: start.add(const Duration(minutes: 1)),
      ),
    ];
    engine = ReviewSessionEngine(
      cards: cards,
      scheduler: FsrsScheduler(),
      reviewRepository: repository,
      clock: now,
    );
  });

  test('start строит очередь, готовит превью и первую карточку', () {
    engine.start();

    final state = engine.state;
    expect(state.total, 2);
    expect(state.index, 0);
    expect(state.current!.card.id, 'card-1');
    expect(state.revealed, isFalse);
    expect(state.busy, isFalse);
    expect(state.undoCount, 0);
    expect(state.preview, isNotNull);
    expect(state.preview!.keys.toList(), Rating.values);
    // Новые карточки: Again 1 мин, Good 10 мин (шаги обучения ADR-004).
    expect(state.preview![Rating.again], const Duration(minutes: 1));
    expect(state.preview![Rating.good], const Duration(minutes: 10));
    expect(ReviewQueue.build(cards, now: start).map((Card c) => c.id), <String>[
      'card-1',
      'card-2',
    ]);
  });

  test('повторный start не пересобирает сессию', () {
    engine.start();
    engine.reveal();
    engine.start();

    expect(engine.state.revealed, isTrue);
    expect(engine.state.current!.card.id, 'card-1');
  });

  test('reveal раскрывает ответ; повторный — no-op', () {
    engine.start();
    engine.reveal();
    expect(engine.state.revealed, isTrue);
    engine.reveal();
    expect(engine.state.revealed, isTrue);
  });

  test('rate пишет оценку и переходит к следующей карточке', () async {
    engine.start();
    repository.previousCard = cards.first;
    advance(const Duration(seconds: 5));

    final ok = await engine.rate(Rating.good);

    expect(ok, isTrue);
    expect(repository.ratings, <Rating>[Rating.good]);
    expect(repository.cardIds, <String>['card-1']);
    expect(repository.modes, <String>['classic']);
    expect(repository.reviewedAts, <DateTime>[
      start.add(const Duration(seconds: 5)),
    ]);
    expect(repository.elapsedTimes.single, const Duration(seconds: 5));
    expect(repository.outcomes.single.state, CardState.learning);
    expect(engine.state.index, 1);
    expect(engine.state.current!.card.id, 'card-2');
    expect(engine.state.revealed, isFalse);
    expect(engine.state.undoCount, 1);
    expect(engine.state.busy, isFalse);
  });

  test('rate на завершённой сессии возвращает false и не пишет', () async {
    engine.start();
    repository.previousCard = cards.first;
    await engine.rate(Rating.good);
    repository.previousCard = cards.last;
    await engine.rate(Rating.good);

    expect(engine.state.isCompleted, isTrue);
    expect(engine.state.current, isNull);
    expect(await engine.rate(Rating.good), isFalse);
    expect(repository.ratings, hasLength(2));
  });

  test('ошибка записи не двигает сессию и сбрасывает busy', () async {
    engine.start();
    repository.recordError = StateError('БД недоступна');

    await expectLater(engine.rate(Rating.good), throwsStateError);

    expect(engine.state.index, 0);
    expect(engine.state.busy, isFalse);
    expect(engine.state.current!.card.id, 'card-1');
    expect(engine.state.undoCount, 0);

    repository.recordError = null;
    repository.previousCard = cards.first;
    expect(await engine.rate(Rating.again), isTrue);
    expect(engine.state.index, 1);
  });

  test('undo откатывает оценку и возвращает карточку', () async {
    engine.start();
    repository.previousCard = cards.first;
    await engine.rate(Rating.good);
    advance(const Duration(seconds: 3));

    final ok = await engine.undo();

    expect(ok, isTrue);
    expect(repository.undone.single.previousCard, cards.first);
    expect(engine.state.index, 0);
    expect(engine.state.current!.card.id, 'card-1');
    expect(engine.state.revealed, isTrue, reason: 'ответ уже был показан');
    expect(engine.state.undoCount, 0);
  });

  test('undo без истории возвращает false', () async {
    engine.start();
    expect(await engine.undo(), isFalse);
    expect(repository.undone, isEmpty);
  });

  test('ошибка undo не меняет состояние', () async {
    engine.start();
    repository.previousCard = cards.first;
    await engine.rate(Rating.good);
    repository.undoError = StateError('нет связи');

    await expectLater(engine.undo(), throwsStateError);

    expect(engine.state.index, 1);
    expect(engine.state.undoCount, 1);
    expect(engine.state.busy, isFalse);
  });

  test('пустая очередь — завершённая сессия', () {
    final emptyEngine = ReviewSessionEngine(
      cards: const <Card>[],
      scheduler: FsrsScheduler(),
      reviewRepository: repository,
      clock: now,
    );

    emptyEngine.start();

    expect(emptyEngine.state.total, 0);
    expect(emptyEngine.state.isCompleted, isTrue);
    expect(emptyEngine.state.preview, isNull);
    expect(emptyEngine.state.current, isNull);
  });

  test('прогноз текущей карточки совпадает с фактическим due (A7.2)', () async {
    engine.start();
    final preview = engine.state.preview!;
    repository.previousCard = cards.first;

    await engine.rate(Rating.easy);

    final outcome = repository.outcomes.single;
    expect(
      outcome.due.difference(start),
      preview[Rating.easy],
      reason: 'прогноз и оценка — одна операция планировщика',
    );
  });

  test('очередь уважает ReviewQueue: suspended не попадает в сессию', () {
    final withSuspended = <Card>[
      cards.first,
      Card(
        id: 'suspended',
        deckId: 'deck-1',
        front: 'Не надо',
        back: 'Ответ',
        cardType: CardType.basic,
        state: CardState.newCard,
        suspended: true,
        createdAt: start,
        updatedAt: start,
      ),
    ];
    final suspendedEngine = ReviewSessionEngine(
      cards: withSuspended,
      scheduler: FsrsScheduler(),
      reviewRepository: repository,
      clock: now,
    );

    suspendedEngine.start();

    expect(suspendedEngine.state.total, 1);
    expect(suspendedEngine.state.current!.card.id, 'card-1');
  });
}
