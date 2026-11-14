import '../cards/card.dart';

/// Построение очереди классической сессии (SPEC A7.2, ADR-008).
///
/// Чистая функция без Flutter и БД: репозиторий отдаёт все карточки колоды,
/// домен решает, что учить и в каком порядке.
abstract final class ReviewQueue {
  /// Собирает очередь карточек колоды на момент [now].
  ///
  /// Правила (ADR-008):
  /// - `suspended` и `buriedUntil > now` исключены;
  /// - входят просроченные (`due <= now`, кроме `new`) и новые (`state = new`);
  /// - порядок: просроченные по `due` ASC, затем новые по `createdAt` ASC;
  /// - тай-брек — `id` ASC (детерминизм);
  /// - [reviewLimit]/[newLimit] — **остаток** дневных лимитов на момент
  ///   открытия сессии (A6.6, ADR-019 §8): `null` — лимита нет; `0` — лимит на
  ///   сегодня исчерпан, брать нечего; `n` — не больше `n` карточек.
  static List<Card> build(
    List<Card> cards, {
    required DateTime now,
    int? newLimit,
    int? reviewLimit,
  }) {
    final DateTime utcNow = now.toUtc();
    final List<Card> eligible = cards
        .where((Card card) {
          if (card.suspended) return false;
          final DateTime? buried = card.buriedUntil;
          return buried == null || !buried.isAfter(utcNow);
        })
        .toList(growable: false);

    final List<Card> due = eligible
        .where((Card card) {
          if (card.state == CardState.newCard) return false;
          final DateTime? dueAt = card.due;
          return dueAt != null && !dueAt.isAfter(utcNow);
        })
        .toList(growable: false);
    due.sort((Card a, Card b) {
      final int byDue = a.due!.compareTo(b.due!);
      return byDue != 0 ? byDue : a.id.compareTo(b.id);
    });

    final List<Card> fresh = eligible
        .where((Card card) => card.state == CardState.newCard)
        .toList(growable: false);
    fresh.sort((Card a, Card b) {
      final int byCreated = a.createdAt.compareTo(b.createdAt);
      return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
    });

    return List<Card>.unmodifiable(<Card>[
      ..._limited(due, reviewLimit),
      ..._limited(fresh, newLimit),
    ]);
  }

  /// Обрезает [cards] до остатка [limit] (`null` — без ограничения).
  static List<Card> _limited(List<Card> cards, int? limit) {
    if (limit == null || cards.length <= limit) return cards;
    // Остаток не бывает отрицательным, но защита от RangeError дешевле бага.
    return limit <= 0 ? const <Card>[] : cards.sublist(0, limit);
  }
}
