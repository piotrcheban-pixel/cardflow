/// Расход дневных лимитов A6.6 из `review_logs` (ADR-019 §8, закрытие L45).
///
/// Схема БД не менялась: «новая vs повторная» выводится из уже записанных полей
/// журнала. Признак — `actual_days`: репозиторий записи повторений пишет его
/// только когда у карточки уже было состояние планировщика (`fsrs_json` с
/// `lastReview`, см. `DriftReviewRepository.recordReview`). Значит
/// `actual_days IS NULL` — это оценка карточки, которая до неё ни разу не
/// планировалась, то есть введение новой карточки; всё остальное — повторная.
///
/// Такой признак честно работает и для карточек с чужим состоянием без истории
/// в этом журнале (импорт колоды): они уже планировались — и считаются
/// повторными, а не новыми. Отдельного счётчика/столбца не нужно, один запрос
/// читает только строки нужного дня.
library;

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/review/daily_usage_repository.dart';

/// Дневной расход оценок поверх существующих таблиц.
class DriftDailyUsageRepository implements DailyUsageRepository {
  /// Создаёт репозиторий поверх БД [db].
  DriftDailyUsageRepository(this.db);

  /// БД приложения.
  final AppDatabase db;

  @override
  Future<DailyReviewUsage> usageOnDay(DateTime now) async {
    final ({DateTime from, DateTime to}) day = DailyLimits.localDayUtc(now);
    final QueryRow row = await db
        .customSelect(
          'SELECT COUNT(*) AS total, '
          'COALESCE(SUM(CASE WHEN actual_days IS NULL THEN 1 ELSE 0 END), 0) '
          'AS new_cards '
          'FROM review_logs '
          'WHERE reviewed_at >= ? AND reviewed_at < ?',
          variables: <Variable<Object>>[
            Variable<int>(toEpochMs(day.from)),
            Variable<int>(toEpochMs(day.to)),
          ],
        )
        .getSingle();
    final int total = row.read<int>('total');
    final int newCards = row.read<int>('new_cards');
    return DailyReviewUsage(newCards: newCards, repeats: total - newCards);
  }

  @override
  String toString() => 'DriftDailyUsageRepository(${db.hashCode})';
}
