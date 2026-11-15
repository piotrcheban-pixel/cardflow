import '../cards/card.dart';
import 'daily_limits.dart';

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
  ///
  /// Исключение дневного лимита новых (ADR-028, итерация 7.12): карточки,
  /// созданные **в текущий локальный календарный день**, входят в очередь всегда.
  /// Пользователь, только что создавший или импортировавший пачку карточек,
  /// должен иметь возможность их пройти, даже если лимит новых на сегодня уже
  /// израсходован. Лимит новых продолжает ограничивать вчерашние и более ранние
  /// невыученные карточки.
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
    final ({List<Card> older, List<Card> createdToday}) split = _splitToday(
      fresh,
      now,
    );

    return List<Card>.unmodifiable(<Card>[
      ..._limited(due, reviewLimit),
      ..._limited(split.older, newLimit),
      // Сортировка `fresh` по `createdAt` ASC означает, что «сегодняшние» стоят
      // в конце: добавление их без лимита сохраняет порядок ADR-008.
      ...split.createdToday,
    ]);
  }

  /// Делит новые карточки на созданные сегодня и более ранние.
  ///
  /// День — локальный календарный (ADR-019 §8, ADR-028): границы считаются по
  /// локальным полуночам и переводятся в UTC, как и расход дневного лимита.
  static ({List<Card> older, List<Card> createdToday}) _splitToday(
    List<Card> fresh,
    DateTime now,
  ) {
    final ({DateTime from, DateTime to}) day = DailyLimits.localDayUtc(now);
    final older = <Card>[];
    final createdToday = <Card>[];
    for (final Card card in fresh) {
      final DateTime createdAt = card.createdAt.toUtc();
      final bool isToday =
          !createdAt.isBefore(day.from) && createdAt.isBefore(day.to);
      (isToday ? createdToday : older).add(card);
    }
    return (older: older, createdToday: createdToday);
  }

  /// Обрезает [cards] до остатка [limit] (`null` — без ограничения).
  static List<Card> _limited(List<Card> cards, int? limit) {
    if (limit == null || cards.length <= limit) return cards;
    // Остаток не бывает отрицательным, но защита от RangeError дешевле бага.
    return limit <= 0 ? const <Card>[] : cards.sublist(0, limit);
  }
}
