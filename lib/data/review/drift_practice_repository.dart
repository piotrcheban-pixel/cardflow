// Drift-реализация порта тренировки (ADR-025, итерация 7.11).
//
// Тренировка не трогает расписание FSRS: в БД появляется только строка
// `review_logs` с `mode = 'practice'` (rating фиксируется, `scheduled_days` и
// `actual_days` остаются NULL). Undo удаляет эту строку — карточка и её
// состояние не менялись, поэтому компенсировать больше нечего.
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/review/practice_repository.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/scheduling/rating.dart';

/// Запись оценок тренировки поверх drift-БД.
class DriftPracticeRepository implements PracticeRepository {
  /// Создаёт репозиторий поверх БД.
  DriftPracticeRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  static const Uuid _uuid = Uuid();

  @override
  Future<String> recordPractice({
    required String cardId,
    required Rating rating,
    required DateTime reviewedAt,
    Duration? elapsed,
  }) {
    final DateTime utcReviewedAt = reviewedAt.toUtc();
    return database.transaction<String>(() async {
      final CardRow? row = await (database.select(
        database.cards,
      )..where((table) => table.id.equals(cardId))).getSingleOrNull();
      if (row == null) {
        throw StateError('Карточка не найдена: $cardId');
      }
      final String logId = _uuid.v4();
      await database
          .into(database.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              id: logId,
              cardId: cardId,
              rating: rating.value,
              reviewedAt: toEpochMs(utcReviewedAt),
              mode: reviewModePractice,
              recognitionFlag: const Value<int>(0),
              scheduledDays: const Value<double?>(null),
              actualDays: const Value<double?>(null),
              elapsedMs: Value<int?>(elapsed?.inMilliseconds),
            ),
          );
      return logId;
    });
  }

  @override
  Future<void> undoPractice(String logId) {
    return database.transaction<void>(() async {
      final int deleted =
          await (database.delete(database.reviewLogs)..where(
                (table) =>
                    table.id.equals(logId) &
                    table.mode.equals(reviewModePractice),
              ))
              .go();
      if (deleted != 1) {
        throw StateError('Запись тренировки не найдена: $logId');
      }
    });
  }

  @override
  String toString() => 'DriftPracticeRepository(${database.hashCode})';
}
