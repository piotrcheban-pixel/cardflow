import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';

import '../../helpers/decks_fakes.dart';

/// Движок «Ленты» — просмотр без FSRS (ADR-044).
///
/// Проверяются ровно те правила, которые отличают ленту от классики:
/// очередь из всех карточек (кроме приостановленных), стабильный порядок,
/// навигация без записи, независимое раскрытие ответа у каждой карточки.
void main() {
  List<Card> cards() => <Card>[
    makeCard(
      id: 'b',
      deckId: 'deck-1',
      front: 'Б',
      back: 'ответ Б',
      createdAt: DateTime.utc(2026, 11, 14, 10, 2),
    ),
    makeCard(
      id: 'a',
      deckId: 'deck-1',
      front: 'А',
      back: 'ответ А',
      createdAt: DateTime.utc(2026, 11, 14, 10, 1),
      suspended: true,
    ),
    makeCard(
      id: 'c',
      deckId: 'deck-1',
      front: 'В',
      back: 'ответ В',
      createdAt: DateTime.utc(2026, 11, 14, 10, 1),
      due: DateTime.utc(2030),
      state: CardState.review,
    ),
  ];

  test('очередь: все карточки, кроме приостановленных, по createdAt и id', () {
    final List<Card> queue = FeedSessionEngine.buildBrowseQueue(cards());
    expect(queue.map((Card card) => card.id), <String>['c', 'b']);
  });

  test('prebuilt сохраняет порядок конструктора и не фильтрует', () {
    final FeedSessionEngine engine = FeedSessionEngine(
      cards: cards(),
      prebuilt: true,
    )..start();
    // Приостановленная карточка пришла из конструктора — движок её не
    // пересобирает: план уже выбран пользователем (ADR-018).
    expect(
      engine.state.items.map((FeedSessionItem item) => item.card.id),
      <String>['b', 'a', 'c'],
    );
  });

  test('visit: границы индекса и повторный визит без notify', () {
    final FeedSessionEngine engine = FeedSessionEngine(cards: cards())..start();
    int notifications = 0;
    engine.addListener(() => notifications++);

    engine.visit(1);
    expect(engine.state.index, 1);
    expect(notifications, 1);
    engine.visit(1);
    expect(notifications, 1, reason: 'тот же индекс — без лишнего rebuild');
    engine.visit(-1);
    engine.visit(99);
    expect(engine.state.index, 1);
  });

  test('раскрытие ответа хранится по карточке и переживает переход', () {
    final FeedSessionEngine engine = FeedSessionEngine(cards: cards())..start();
    expect(engine.state.current!.revealed, isFalse);

    engine.toggleReveal();
    expect(engine.state.current!.revealed, isTrue);
    expect(
      engine.state.items[1].revealed,
      isFalse,
      reason: 'соседняя карточка не раскрыта',
    );

    engine.visit(1);
    expect(engine.state.current!.revealed, isFalse);
    engine.visit(0);
    expect(
      engine.state.current!.revealed,
      isTrue,
      reason: 'возврат к карточке сохраняет раскрытый ответ',
    );

    engine.toggleRevealAt(1);
    expect(engine.state.items[1].revealed, isTrue);
    engine.toggleRevealAt(99);
    expect(engine.state.items.length, 2);
  });

  test('canGoNext/canGoPrevious на краях', () {
    final FeedSessionEngine engine = FeedSessionEngine(cards: cards())..start();
    expect(engine.state.canGoPrevious, isFalse);
    expect(engine.state.canGoNext, isTrue);
    engine.visit(1);
    expect(engine.state.canGoPrevious, isTrue);
    expect(engine.state.canGoNext, isFalse);
  });

  test('пустая колода: total = 0, current = null', () {
    final FeedSessionEngine engine = FeedSessionEngine(cards: const <Card>[])
      ..start();
    expect(engine.state.total, 0);
    expect(engine.state.current, isNull);
    engine.toggleReveal();
    engine.visit(0);
    expect(engine.state.index, 0);
  });
}
