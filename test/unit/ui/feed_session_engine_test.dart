import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/review_fakes.dart';

/// Красная фаза итерации 4: движок ленты (SPEC A7.3, ADR-016) — очередь,
/// листание без оценки, оценки/undo, авто-продвижение, завершение, ошибки БД.
void main() {
  final DateTime start = DateTime.utc(2026, 11, 14, 12);

  late DateTime clockNow;
  late FakeReviewRepository repository;
  late FeedSessionEngine engine;
  late List<Card> cards;

  DateTime now() => clockNow;

  void advanceClock(Duration duration) => clockNow = clockNow.add(duration);

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
      makeCard(
        id: 'card-3',
        deckId: 'deck-1',
        front: 'Третий',
        createdAt: start.add(const Duration(minutes: 2)),
      ),
    ];
    engine = FeedSessionEngine(
      cards: cards,
      scheduler: FsrsScheduler(),
      reviewRepository: repository,
      clock: now,
    );
  });

  test('start строит очередь и показывает первую карточку', () {
    engine.start();

    final FeedSessionState state = engine.state;
    expect(state.total, 3);
    expect(state.index, 0);
    expect(state.current!.card.id, 'card-1');
    expect(state.current!.revealed, isFalse);
    expect(state.current!.rated, isFalse);
    expect(state.ratedCount, 0);
    expect(state.busy, isFalse);
    expect(state.undoCount, 0);
    expect(state.isCompleted, isFalse);
  });

  test('повторный start не пересобирает сессию', () {
    engine.start();
    engine.toggleReveal();
    engine.start();

    expect(engine.state.current!.card.id, 'card-1');
    expect(engine.state.current!.revealed, isTrue);
  });

  test('visit переключает страницу без записи в БД', () {
    engine.start();

    engine.visit(2);

    expect(engine.state.index, 2);
    expect(engine.state.current!.card.id, 'card-3');
    expect(repository.ratings, isEmpty, reason: 'листание не засчитывается');
    expect(repository.cardIds, isEmpty);
  });

  test('visit вне диапазона игнорируется', () {
    engine.start();
    engine.visit(2);
    engine.visit(-1);
    expect(engine.state.index, 2);
    engine.visit(99);
    expect(engine.state.index, 2);
  });

  test('toggleReveal раскрывает и скрывает ответ', () {
    engine.start();

    engine.toggleReveal();
    expect(engine.state.current!.revealed, isTrue);
    engine.toggleReveal();
    expect(engine.state.current!.revealed, isFalse);
    expect(repository.ratings, isEmpty);
  });

  test('toggleReveal не раскрывает оценённую и не оценивает', () async {
    engine.start();
    repository.previousCard = cards.first;
    await engine.rate(Rating.good);
    engine.visit(0);

    engine.toggleReveal();

    expect(engine.state.current!.rated, isTrue);
    expect(engine.state.current!.revealed, isFalse);
  });

  test(
    'rate пишет mode=feed, elapsed и переходит к следующей карточке',
    () async {
      engine.start();
      repository.previousCard = cards.first;
      advanceClock(const Duration(seconds: 4));

      final bool ok = await engine.rate(Rating.good);

      expect(ok, isTrue);
      expect(repository.ratings, <Rating>[Rating.good]);
      expect(repository.cardIds, <String>['card-1']);
      expect(repository.modes, <String>[reviewModeFeed]);
      expect(repository.reviewedAts, <DateTime>[
        start.add(const Duration(seconds: 4)),
      ]);
      expect(repository.elapsedTimes.single, const Duration(seconds: 4));
      expect(repository.outcomes.single.state, CardState.learning);

      final FeedSessionState state = engine.state;
      expect(state.ratedCount, 1);
      expect(state.index, 1);
      expect(state.current!.card.id, 'card-2');
      expect(state.current!.revealed, isFalse);
      expect(state.busy, isFalse);
      expect(state.undoCount, 1);
    },
  );

  test('оценка помечает карточку и не даёт оценить её повторно', () async {
    engine.start();
    repository.previousCard = cards.first;
    await engine.rate(Rating.good);

    engine.visit(0);
    repository.previousCard = cards.first;
    final bool again = await engine.rate(Rating.easy);

    expect(again, isFalse);
    expect(repository.ratings, <Rating>[Rating.good]);
    expect(engine.state.ratedCount, 1);
  });

  test('оценка последней неоценённой карточки завершает сессию', () async {
    engine.start();
    for (final Card card in cards) {
      repository.previousCard = card;
      expect(await engine.rate(Rating.good), isTrue);
    }

    final FeedSessionState state = engine.state;
    expect(state.ratedCount, 3);
    expect(state.isCompleted, isTrue);
    expect(state.current, isNull);
    expect(await engine.rate(Rating.good), isFalse);
  });

  test('ошибка записи не двигает ленту и сбрасывает busy', () async {
    engine.start();
    repository.recordError = StateError('БД недоступна');

    await expectLater(engine.rate(Rating.good), throwsStateError);

    final FeedSessionState state = engine.state;
    expect(state.index, 0);
    expect(state.busy, isFalse);
    expect(state.current!.card.id, 'card-1');
    expect(state.current!.rated, isFalse);
    expect(state.ratedCount, 0);
    expect(state.undoCount, 0);

    repository.recordError = null;
    repository.previousCard = cards.first;
    expect(await engine.rate(Rating.again), isTrue);
    expect(engine.state.ratedCount, 1);
  });

  test('undo откатывает оценку, возвращает карточку раскрытой', () async {
    engine.start();
    repository.previousCard = cards.first;
    await engine.rate(Rating.good);
    advanceClock(const Duration(seconds: 3));

    final bool ok = await engine.undo();

    expect(ok, isTrue);
    expect(repository.undone.single.previousCard, cards.first);
    final FeedSessionState state = engine.state;
    expect(state.index, 0);
    expect(state.current!.card.id, 'card-1');
    expect(state.current!.revealed, isTrue);
    expect(state.current!.rated, isFalse);
    expect(state.current!.rating, isNull);
    expect(state.ratedCount, 0);
    expect(state.undoCount, 0);
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
    expect(engine.state.ratedCount, 1);
    expect(engine.state.undoCount, 1);
    expect(engine.state.busy, isFalse);
  });

  test('advance переходит к следующей карточке без оценки', () {
    engine.start();
    advanceClock(const Duration(seconds: 2));

    final bool moved = engine.advance();

    expect(moved, isTrue);
    expect(engine.state.index, 1);
    expect(engine.state.current!.card.id, 'card-2');
    expect(engine.state.current!.revealed, isFalse);
    expect(
      repository.ratings,
      isEmpty,
      reason: 'авто-продвижение не оценивает',
    );
    expect(engine.state.ratedCount, 0);
  });

  test('advance пропускает оценённые и не выходит за границы', () async {
    engine.start();
    repository.previousCard = cards[1];
    engine.visit(1);
    await engine.rate(Rating.good);

    engine.visit(0);
    expect(engine.advance(), isTrue);
    expect(engine.state.index, 2, reason: 'карточка 1 уже оценена');

    expect(engine.advance(), isFalse);
    expect(engine.state.index, 2);
  });

  test('advance на завершённой сессии возвращает false', () async {
    engine.start();
    for (final Card card in cards) {
      repository.previousCard = card;
      await engine.rate(Rating.good);
    }

    expect(engine.advance(), isFalse);
    expect(repository.ratings, hasLength(3));
  });

  test('оценка на завершённой сессии возвращает false', () async {
    engine.start();
    for (final Card card in cards) {
      repository.previousCard = card;
      await engine.rate(Rating.good);
    }

    expect(await engine.rate(Rating.good), isFalse);
    expect(repository.ratings, hasLength(3));
  });

  test('пустая очередь — завершённая сессия', () {
    final FeedSessionEngine empty = FeedSessionEngine(
      cards: const <Card>[],
      scheduler: FsrsScheduler(),
      reviewRepository: repository,
      clock: now,
    );

    empty.start();

    expect(empty.state.total, 0);
    expect(empty.state.isCompleted, isTrue);
    expect(empty.state.current, isNull);
    expect(empty.state.ratedCount, 0);
  });

  test('очередь уважает ReviewQueue: suspended не попадает в ленту', () {
    final List<Card> withSuspended = <Card>[
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
    final FeedSessionEngine filtered = FeedSessionEngine(
      cards: withSuspended,
      scheduler: FsrsScheduler(),
      reviewRepository: repository,
      clock: now,
    );

    filtered.start();

    expect(filtered.state.total, 1);
    expect(filtered.state.current!.card.id, 'card-1');
  });

  test('dispose во время записи не дёргает notifyListeners', () async {
    engine.start();
    repository.previousCard = cards.first;

    final Future<bool> pending = engine.rate(Rating.good);
    int notifications = 0;
    engine.addListener(() => notifications++);
    engine.dispose();

    await expectLater(pending, completion(isTrue));
    expect(
      notifications,
      0,
      reason: 'после dispose слушатели не должны вызываться',
    );
  });
}
