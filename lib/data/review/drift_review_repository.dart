// Drift-реализация порта записи повторений (SPEC A5, ADR-008).
//
// Ключевой инвариант итерации 2: `review_logs` и обновление
// `cards.state`/`fsrs_json`/`due` пишутся в одной транзакции; undo —
// компенсирующая транзакция (удалить лог + восстановить снимок карточки).
import 'package:cardflow/data/db/app_database.dart';
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

  @override
  Future<ReviewUndo> recordReview({
    required String cardId,
    required Rating rating,
    required DateTime reviewedAt,
    required SchedulingCard outcome,
    required String mode,
    Duration? elapsed,
  }) {
    throw UnimplementedError(
      'DriftReviewRepository.recordReview: красная фаза итерации 2',
    );
  }

  @override
  Future<void> undoReview(ReviewUndo undo) {
    throw UnimplementedError(
      'DriftReviewRepository.undoReview: красная фаза итерации 2',
    );
  }

  @override
  String toString() => 'DriftReviewRepository(${database.hashCode})';
}
