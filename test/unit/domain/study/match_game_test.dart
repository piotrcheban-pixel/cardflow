import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/match_game.dart';

/// Игровое состояние «Подбор пар» (7.16).
void main() {
  List<Card> cards({int count = 6}) {
    return <Card>[
      for (var index = 0; index < count; index++)
        Card(
          id: 'card-$index',
          deckId: 'deck-1',
          front: 'Вопрос $index',
          back: 'Ответ $index',
          cardType: CardType.basic,
          state: CardState.newCard,
          createdAt: DateTime.utc(2026, 11, 16),
          updatedAt: DateTime.utc(2026, 11, 16),
        ),
    ];
  }

  test('6 пар = 12 плиток, вопрос и ответ каждой карточки', () {
    final game = MatchGame.build(cards: cards(), seed: 1);
    expect(game.tiles, hasLength(12));
    expect(game.isPlayable, isTrue);
    for (final Card card in cards()) {
      final tiles = game.tiles.where((t) => t.cardId == card.id).toList();
      expect(tiles, hasLength(2));
      expect(
        tiles.map((t) => t.text),
        containsAll(<String>[card.front, card.back]),
      );
      expect(tiles.where((t) => t.isFront), hasLength(1));
    }
  });

  test('совпавшая пара исчезает, ход считается', () {
    final game = MatchGame.build(cards: cards(), seed: 2);
    final first = game.tiles.first;
    final second = game.tiles.firstWhere(
      (t) => t.cardId == first.cardId && t.index != first.index,
    );
    expect(game.select(first.index), MatchSelectionResult.selected);
    expect(game.select(second.index), MatchSelectionResult.matched);
    expect(game.matched, <int>{first.index, second.index});
    expect(game.moves, 1);
    expect(game.selected, isNull);
  });

  test('несовпадение: встряхивание и снятие выбора', () {
    final game = MatchGame.build(cards: cards(), seed: 3);
    final a = game.tiles.first;
    final b = game.tiles.firstWhere((t) => t.cardId != a.cardId);
    game.select(a.index);
    expect(game.select(b.index), MatchSelectionResult.mismatch);
    expect(game.mismatch, <int>{a.index, b.index});
    expect(game.matched, isEmpty);
    game.clearMismatch();
    expect(game.mismatch, isEmpty);
    expect(game.select(b.index), MatchSelectionResult.selected);
  });

  test('повторный тап по выбранной плитке снимает выбор', () {
    final game = MatchGame.build(cards: cards(), seed: 4);
    expect(game.select(0), MatchSelectionResult.selected);
    expect(game.select(0), MatchSelectionResult.ignored);
    expect(game.selected, isNull);
  });

  test('завершение после всех 6 пар', () {
    final game = MatchGame.build(cards: cards(), seed: 5);
    for (final Card card in cards()) {
      final pair = game.tiles.where((t) => t.cardId == card.id).toList();
      game.select(pair[0].index);
      expect(game.select(pair[1].index), MatchSelectionResult.matched);
    }
    expect(game.isCompleted, isTrue);
    expect(game.matched, hasLength(12));
  });

  test('меньше 6 карточек — игра недоступна', () {
    final game = MatchGame.build(cards: cards(count: 5), seed: 6);
    expect(game.tiles, hasLength(10));
    expect(game.isPlayable, isFalse);
  });

  test('cloze-карточка не участвует (нет отдельного ответа)', () {
    final deck = cards(count: 5)
      ..add(
        Card(
          id: 'cloze',
          deckId: 'deck-1',
          front: 'Столица {{c1::Париж}}',
          back: '',
          cardType: CardType.cloze,
          state: CardState.newCard,
          createdAt: DateTime.utc(2026, 11, 16),
          updatedAt: DateTime.utc(2026, 11, 16),
        ),
      );
    final game = MatchGame.build(cards: deck, seed: 7);
    expect(game.tiles.any((t) => t.cardId == 'cloze'), isFalse);
  });

  test('одинаковый seed — одинаковый порядок плиток', () {
    final first = MatchGame.build(cards: cards(), seed: 42);
    final second = MatchGame.build(cards: cards(), seed: 42);
    expect(
      first.tiles.map((t) => '${t.cardId}:${t.isFront}').toList(),
      second.tiles.map((t) => '${t.cardId}:${t.isFront}').toList(),
    );
  });
}
