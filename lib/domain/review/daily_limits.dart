/// Дневные лимиты A6.6 по локальному календарному дню (ADR-019 §8).
///
/// Разрыв L45: лимит применялся к очереди одной сессии, поэтому за день можно
/// было пройти лимит столько раз, сколько раз открыть сессию. Здесь — чистая
/// арифметика остатка; сам расход дня читает `DailyUsageRepository` из
/// `review_logs` (схема БД не меняется).
library;

/// Расход дневных лимитов за один локальный календарный день.
///
/// «Новые» — оценки карточек, которые до неё ещё ни разу не планировались
/// (`review_logs.actual_days IS NULL`); «повторные» — остальные оценки дня.
class DailyReviewUsage {
  /// Создаёт расход дня.
  const DailyReviewUsage({this.newCards = 0, this.repeats = 0});

  /// Ничего не оценено (начало дня).
  static const DailyReviewUsage empty = DailyReviewUsage();

  /// Сколько новых карточек введено сегодня.
  final int newCards;

  /// Сколько повторных оценок сделано сегодня.
  final int repeats;

  /// Всего оценок за день.
  int get total => newCards + repeats;

  @override
  bool operator ==(Object other) =>
      other is DailyReviewUsage &&
      other.newCards == newCards &&
      other.repeats == repeats;

  @override
  int get hashCode => Object.hash(newCards, repeats);

  @override
  String toString() => 'DailyReviewUsage(new: $newCards, repeats: $repeats)';
}

/// Остаток дневных лимитов для очереди новой сессии.
///
/// Три состояния остатка принципиальны:
/// - `null` — лимит в настройках выключен (`0`), очередь не ограничивается;
/// - `0` — лимит на сегодня исчерпан, карточек этого вида брать нельзя;
/// - `n` — можно взять не больше `n`.
class RemainingReviewLimits {
  /// Создаёт остаток.
  const RemainingReviewLimits({this.newCards, this.reviews});

  /// Остаток новых карточек; `null` — без ограничения.
  final int? newCards;

  /// Остаток повторных карточек; `null` — без ограничения.
  final int? reviews;

  /// Считает остаток из настроек и расхода дня.
  factory RemainingReviewLimits.of({
    required int newLimit,
    required int reviewLimit,
    required DailyReviewUsage usage,
  }) => RemainingReviewLimits(
    newCards: DailyLimits.remaining(newLimit, usage.newCards),
    reviews: DailyLimits.remaining(reviewLimit, usage.repeats),
  );

  /// Ничего не разрешено (обе части исчерпаны явно).
  bool get isEmpty => newCards == 0 && reviews == 0;

  @override
  bool operator ==(Object other) =>
      other is RemainingReviewLimits &&
      other.newCards == newCards &&
      other.reviews == reviews;

  @override
  int get hashCode => Object.hash(newCards, reviews);

  @override
  String toString() =>
      'RemainingReviewLimits(new: $newCards, reviews: $reviews)';
}

/// Чистые правила дневных лимитов (SPEC A6.6, ADR-019 §8).
abstract final class DailyLimits {
  /// Границы локального календарного дня [now] в UTC, полуинтервал `[from, to)`.
  ///
  /// Считаются по локальным полуночам: переход на летнее/зимнее время не
  /// разъезжается, а граница дня остаётся ожидаемой для пользователя.
  static ({DateTime from, DateTime to}) localDayUtc(DateTime now) {
    final DateTime local = now.toLocal();
    return (
      from: DateTime(local.year, local.month, local.day).toUtc(),
      to: DateTime(local.year, local.month, local.day + 1).toUtc(),
    );
  }

  /// Остаток лимита [configured] (`0` — лимита нет) после [used] оценок.
  ///
  /// `null` — ограничения нет; `0` — исчерпан; иначе — сколько осталось.
  static int? remaining(int configured, int used) {
    if (configured <= 0) return null;
    final int left = configured - used;
    return left > 0 ? left : 0;
  }
}
