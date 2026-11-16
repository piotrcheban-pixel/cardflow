/// Игровое состояние «Подбор пар» (итерация 7.16).
///
/// Колода превращается в сетку из 6 пар: вопрос и ответ каждой карточки
/// перемешиваются. Игрок выбирает две плитки; совпавшая пара исчезает,
/// несовпавшая встряхивается. В FSRS ничего не пишется — режим игровой.
/// Домен без Flutter, таймер/анимации — в UI.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/cards/card.dart';

/// Число пар в игре (12 плиток).
const int kMatchPairs = 6;

/// Одна плитка сетки.
class MatchTile {
  /// Создаёт плитку.
  const MatchTile({
    required this.index,
    required this.cardId,
    required this.text,
    required this.isFront,
  });

  /// Позиция в сетке.
  final int index;

  /// Карточка, к которой относится плитка.
  final String cardId;

  /// Текст плитки (вопрос или ответ).
  final String text;

  /// `true` — вопрос (front), `false` — ответ (back).
  final bool isFront;
}

/// Итог выбора плитки.
enum MatchSelectionResult {
  /// Первая плитка выбрана.
  selected,

  /// Пара совпала и исчезла.
  matched,

  /// Пара не совпала (нужно встряхнуть и снять выбор).
  mismatch,

  /// Плитка уже совпала/недоступна.
  ignored,
}

/// Состояние игры «Подбор пар».
class MatchGame {
  MatchGame._(this.tiles);

  /// Строит игру из первых подходящих [pairs] карточек колоды.
  ///
  /// Подходят карточки с непустыми front и back, кроме cloze (у него нет
  /// отдельного ответа). Если подходящих карточек меньше [pairs] — плиток
  /// меньше, и экран покажет пустое состояние.
  factory MatchGame.build({
    required List<Card> cards,
    int seed = 0,
    int pairs = kMatchPairs,
  }) {
    final List<Card> suitable = cards
        .where(
          (Card card) =>
              card.cardType != CardType.cloze &&
              card.front.trim().isNotEmpty &&
              card.back.trim().isNotEmpty,
        )
        .take(pairs)
        .toList(growable: false);
    final List<({String cardId, String text, bool isFront})> raw =
        <({String cardId, String text, bool isFront})>[
          for (final Card card
              in suitable) ...<({String cardId, String text, bool isFront})>[
            (cardId: card.id, text: card.front, isFront: true),
            (cardId: card.id, text: card.back, isFront: false),
          ],
        ];
    raw.shuffle(math.Random(seed));
    final List<MatchTile> tiles = <MatchTile>[
      for (var index = 0; index < raw.length; index++)
        MatchTile(
          index: index,
          cardId: raw[index].cardId,
          text: raw[index].text,
          isFront: raw[index].isFront,
        ),
    ];
    return MatchGame._(
      List<MatchTile>.unmodifiable(<MatchTile>[
        for (var index = 0; index < tiles.length; index++)
          MatchTile(
            index: index,
            cardId: tiles[index].cardId,
            text: tiles[index].text,
            isFront: tiles[index].isFront,
          ),
      ]),
    );
  }

  /// Плитки в порядке сетки.
  final List<MatchTile> tiles;

  final Set<int> _matched = <int>{};
  final Set<int> _mismatch = <int>{};
  int? _selected;
  int _moves = 0;

  /// Совпавшие плитки.
  Set<int> get matched => Set<int>.unmodifiable(_matched);

  /// Несовпавшая пара (пока показывается встряхивание).
  Set<int> get mismatch => Set<int>.unmodifiable(_mismatch);

  /// Выбранная первая плитка.
  int? get selected => _selected;

  /// Число ходов (пар открытий).
  int get moves => _moves;

  /// Все пары найдены.
  bool get isCompleted => _matched.length == tiles.length && tiles.isNotEmpty;

  /// Игра возможна (6 пар).
  bool get isPlayable => tiles.length >= kMatchPairs * 2;

  /// Выбирает плитку [index].
  MatchSelectionResult select(int index) {
    if (index < 0 || index >= tiles.length) return MatchSelectionResult.ignored;
    if (_matched.contains(index) || _mismatch.contains(index)) {
      return MatchSelectionResult.ignored;
    }
    final int? first = _selected;
    if (first == null) {
      _selected = index;
      return MatchSelectionResult.selected;
    }
    if (first == index) {
      _selected = null;
      return MatchSelectionResult.ignored;
    }
    _moves++;
    final MatchTile a = tiles[first];
    final MatchTile b = tiles[index];
    final bool pair = a.cardId == b.cardId && a.isFront != b.isFront;
    _selected = null;
    if (pair) {
      _matched
        ..add(first)
        ..add(index);
      return MatchSelectionResult.matched;
    }
    _mismatch
      ..add(first)
      ..add(index);
    return MatchSelectionResult.mismatch;
  }

  /// Снимает подсветку несовпавшей пары (после анимации встряхивания).
  void clearMismatch() {
    _mismatch.clear();
  }
}
