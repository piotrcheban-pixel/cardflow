import 'package:cardflow/domain/decks/deck.dart';

/// Колода вместе со счётчиками карточек (SPEC A5/A6.2/A6.3).
///
/// Счётчики нужны карточкам списка колод, чипам фильтра и шапке экрана
/// колоды. Считаются репозиторием, чтобы UI не ходил в БД за каждым числом.
class DeckSummary {
  /// Создаёт сводку.
  const DeckSummary({
    required this.deck,
    this.totalCards = 0,
    this.newCards = 0,
    this.inProgressCards = 0,
    this.dueCards = 0,
  });

  /// Сама колода.
  final Deck deck;

  /// Всего карточек в колоде.
  final int totalCards;

  /// Карточки в состоянии `new`.
  final int newCards;

  /// Карточки в процессе изучения (`learning` + `relearning`).
  final int inProgressCards;

  /// Просроченные карточки (`due <= now`, не приостановленные/отложенные).
  final int dueCards;

  /// Есть ли в колоде карточки (для счётчиков экрана колоды).
  bool get hasCards => totalCards > 0;

  @override
  bool operator ==(Object other) {
    return other is DeckSummary &&
        other.deck == deck &&
        other.totalCards == totalCards &&
        other.newCards == newCards &&
        other.inProgressCards == inProgressCards &&
        other.dueCards == dueCards;
  }

  @override
  int get hashCode =>
      Object.hash(deck, totalCards, newCards, inProgressCards, dueCards);

  @override
  String toString() =>
      'DeckSummary(${deck.name}: total=$totalCards, new=$newCards, '
      'inProgress=$inProgressCards, due=$dueCards)';
}
