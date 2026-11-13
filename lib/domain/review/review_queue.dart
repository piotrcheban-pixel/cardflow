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
  /// - тай-брек — `id` ASC (детерминизм).
  static List<Card> build(List<Card> cards, {required DateTime now}) {
    return const <Card>[];
  }
}
