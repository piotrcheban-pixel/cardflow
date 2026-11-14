import 'daily_limits.dart';

/// Порт чтения дневного расхода оценок (SPEC A6.6, ADR-019 §8).
///
/// Расход считается по истории `review_logs` за локальный календарный день:
/// отдельного счётчика и столбца в схеме нет (схема БД не меняется).
abstract interface class DailyUsageRepository {
  /// Сколько новых и повторных карточек оценено в день, содержащий [now].
  ///
  /// День — локальный календарный: границы считает реализация по
  /// `DailyLimits.localDayUtc`.
  Future<DailyReviewUsage> usageOnDay(DateTime now);
}
