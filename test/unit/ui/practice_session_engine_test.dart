import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/review/practice_session_engine.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/review_fakes.dart';

/// Движок тренировки (ADR-025, итерация 7.11): очередь без FSRS, раскрытие,
/// оценки в журнал practice, undo, ошибки БД.
void main() {
  final start = DateTime.utc(2026, 11, 15, 19);

  late DateTime clockNow;
  late FakePracticeRepository repository;
  late PracticeSessionEngine engine;
  late List<Card> cards;

  DateTime now() => clockNow;

  void advance(Duration duration) => clockNow = clockNow.add(duration);

  setUp(() {
    clockNow = start;
    repository = FakePracticeRepository();
    cards = <Card>[
      makeCard(
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Первый',
        createdAt: DateTime.utc(2026, 11, 10),
      ),
      makeCard(
        id: 'card-2',
        deckId: 'deck-1',
        front: 'Второй',
        state: CardState.review,
        due: start.add(const Duration(days: 3)),
        createdAt: DateTime.utc(2026, 11, 11),
      ),
      makeCard(
        id: 'card-3',
        deckId: 'deck-1',
        front: 'Приостановлена',
        suspended: true,
        createdAt: DateTime.utc(2026, 11, 9),
      ),
    ];
    engine = PracticeSessionEngine(
      cards: cards,
      practiceRepository: repository,
      clock: now,
    );
  });

  test('start: очередь без FSRS-фильтра, приостановленные исключены', () {
    engine.start();

    final state = engine.state;
    expect(state.total, 2);
    expect(state.current!.id, 'card-1', reason: 'createdAt ASC');
    expect(state.revealed, isFalse);
    expect(state.isCompleted, isFalse);
  });

  test('reveal раскрывает ответ; повторный — no-op', () {
    engine.start();
    engine.reveal();
    expect(engine.state.revealed, isTrue);
    engine.reveal();
    expect(engine.state.revealed, isTrue);
  });

  test('rate пишет practice-оценку и переходит к следующей карточке', () async {
    engine.start();
    engine.reveal();
    advance(const Duration(seconds: 5));
    final bool rated = await engine.rate(Rating.good);

    expect(rated, isTrue);
    expect(repository.cardIds, <String>['card-1']);
    expect(repository.ratings, <Rating>[Rating.good]);
    expect(repository.elapsedTimes.single, const Duration(seconds: 5));
    expect(engine.state.index, 1);
    expect(engine.state.current!.id, 'card-2');
    expect(engine.state.revealed, isFalse);
    expect(engine.state.undoCount, 1);
  });

  test('rate на завершённой тренировке — false, без записи', () async {
    engine.start();
    await engine.rate(Rating.easy);
    await engine.rate(Rating.easy);
    expect(engine.state.isCompleted, isTrue);

    expect(await engine.rate(Rating.good), isFalse);
    expect(repository.ratings, <Rating>[Rating.easy, Rating.easy]);
  });

  test('undo возвращает на предыдущую карточку и удаляет запись', () async {
    engine.start();
    final bool rated = await engine.rate(Rating.hard);
    expect(rated, isTrue);

    final bool undone = await engine.undo();

    expect(undone, isTrue);
    expect(repository.undoneLogIds, <String>['practice-log-1']);
    expect(engine.state.index, 0);
    expect(engine.state.revealed, isTrue);
    expect(engine.state.undoCount, 0);
  });

  test('undo без оценок — false', () async {
    engine.start();
    expect(await engine.undo(), isFalse);
  });

  test('ошибка записи: busy сбрасывается, состояние не двигается', () async {
    repository.recordError = StateError('БД');
    engine.start();

    await expectLater(engine.rate(Rating.good), throwsStateError);
    expect(engine.state.index, 0);
    expect(engine.state.busy, isFalse);
  });

  test('busy во время записи: повторная оценка не проходит', () async {
    final Completer<void> gate = Completer<void>();
    repository.recordGate = gate;
    engine.start();

    final Future<bool> pending = engine.rate(Rating.good);
    expect(engine.state.busy, isTrue);
    expect(await engine.rate(Rating.easy), isFalse);

    gate.complete();
    expect(await pending, isTrue);
    expect(repository.ratings, <Rating>[Rating.good]);
  });

  test('повторный start не пересобирает очередь', () {
    engine.start();
    engine.reveal();
    engine.start();
    expect(engine.state.revealed, isTrue);
    expect(engine.state.total, 2);
  });
}
