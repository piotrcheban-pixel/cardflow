// Drift-реализация порта записи повторений (SPEC A5, ADR-008).
//
// Ключевой инвариант итерации 2: `review_logs` и обновление
// `cards.state`/`fsrs_json`/`due` пишутся в одной транзакции; undo —
// компенсирующая транзакция (удалить лог + восстановить снимок карточки).
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/cards/card_row_mapper.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/scheduling/scheduling_card.dart';

/// Запись повторений поверх drift-БД.
class DriftReviewRepository implements ReviewRepository {
  /// Создаёт репозиторий поверх БД.
  DriftReviewRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  static const Uuid _uuid = Uuid();

  @override
  Future<ReviewUndo> recordReview({
    required String cardId,
    required Rating rating,
    required DateTime reviewedAt,
    required SchedulingCard outcome,
    required String mode,
    Duration? elapsed,
  }) {
    final DateTime utcReviewedAt = reviewedAt.toUtc();
    return database.transaction<ReviewUndo>(() async {
      final CardRow? row = await (database.select(
        database.cards,
      )..where((table) => table.id.equals(cardId))).getSingleOrNull();
      if (row == null) {
        throw StateError('Карточка не найдена: $cardId');
      }
      final Card previousCard = cardFromRow(row);
      final int written =
          await (database.update(
            database.cards,
          )..where((table) => table.id.equals(cardId))).write(
            CardsCompanion(
              state: Value<String>(outcome.state.wireName),
              fsrsJson: Value<String>(jsonEncode(outcome.toJson())),
              due: Value<int>(toEpochMs(outcome.due)),
              updatedAt: Value<int>(toEpochMs(utcReviewedAt)),
            ),
          );
      if (written != 1) {
        throw StateError('Карточка не обновлена: $cardId');
      }

      final SchedulingCard? previousScheduling = previousCard.fsrsJson == null
          ? null
          : SchedulingCard.fromJson(
              jsonDecode(previousCard.fsrsJson!) as Map<String, dynamic>,
            );
      final DateTime? lastReview = previousScheduling?.lastReview;
      final double scheduledDays =
          outcome.due.difference(utcReviewedAt).inMilliseconds /
          Duration.millisecondsPerDay;
      final double? actualDays = lastReview == null
          ? null
          : utcReviewedAt.difference(lastReview).inMilliseconds /
                Duration.millisecondsPerDay;

      final String logId = _uuid.v4();
      await database
          .into(database.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              id: logId,
              cardId: cardId,
              rating: rating.value,
              reviewedAt: toEpochMs(utcReviewedAt),
              mode: mode,
              recognitionFlag: const Value<int>(0),
              scheduledDays: Value<double>(scheduledDays),
              actualDays: Value<double?>(actualDays),
              elapsedMs: Value<int?>(elapsed?.inMilliseconds),
            ),
          );
      return ReviewUndo(logId: logId, previousCard: previousCard);
    });
  }

  @override
  Future<void> undoReview(ReviewUndo undo) {
    return database.transaction<void>(() async {
      final int deleted = await (database.delete(
        database.reviewLogs,
      )..where((table) => table.id.equals(undo.logId))).go();
      if (deleted != 1) {
        throw StateError('Запись review_logs не найдена: ${undo.logId}');
      }
      final int written =
          await (database.update(database.cards)
                ..where((table) => table.id.equals(undo.previousCard.id)))
              .write(cardToCompanion(undo.previousCard));
      if (written != 1) {
        throw StateError('Карточка не найдена: ${undo.previousCard.id}');
      }
    });
  }

  @override
  String toString() => 'DriftReviewRepository(${database.hashCode})';
}
