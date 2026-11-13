import '../scheduling/rating.dart';
import '../scheduling/scheduling_card.dart';
import 'review.dart';

/// Порт записи повторений (SPEC A5, A7.2, A6.4).
///
/// Реализация обязана писать `review_logs` и обновлять
/// `cards.state`/`cards.fsrs_json`/`cards.due` **в одной транзакции**:
/// расхождение — баг (SPEC A5).
abstract interface class ReviewRepository {
  /// Записывает оценку [rating] для карточки [cardId] в момент [reviewedAt].
  ///
  /// [outcome] — новое состояние планировщика (state, fsrs_json, due).
  /// [mode] — `review_logs.mode` (в итерации 2 — [reviewModeClassic]).
  /// [elapsed] — время от показа карточки до оценки (`review_logs.elapsed_ms`).
  ///
  /// Возвращает токен отката (id лога + снимок карточки до оценки).
  Future<ReviewUndo> recordReview({
    required String cardId,
    required Rating rating,
    required DateTime reviewedAt,
    required SchedulingCard outcome,
    required String mode,
    Duration? elapsed,
  });

  /// Откатывает оценку: удаляет лог и восстанавливает снимок карточки —
  /// одной транзакцией.
  Future<void> undoReview(ReviewUndo undo);
}
