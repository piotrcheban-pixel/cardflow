import '../cards/card.dart';

/// Очередь режима «Тренировка» (ADR-025, итерация 7.11).
///
/// Тренировка не спрашивает FSRS: в очередь входят **все** карточки колоды,
/// кроме приостановленных пользователем (`suspended`) — включая новые, а также
/// карточки с `due` в будущем. Порядок детерминированный (как список колоды):
/// `createdAt` ASC, тай-брек `id` ASC.
abstract final class PracticeQueue {
  /// Собирает очередь тренировки из снимка карточек колоды.
  static List<Card> build(List<Card> cards) {
    final List<Card> eligible =
        <Card>[
          for (final Card card in cards)
            if (!card.suspended) card,
        ]..sort((Card a, Card b) {
          final int byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
    return List<Card>.unmodifiable(eligible);
  }
}
