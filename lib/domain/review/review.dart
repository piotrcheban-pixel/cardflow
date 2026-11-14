import '../cards/card.dart';

/// Режим повторения, записываемый в `review_logs.mode` (SPEC A5).
///
/// Классический режим (SPEC A7.2) — [reviewModeClassic]; «Лента» (SPEC A7.3) —
/// [reviewModeFeed]. «Конструктор» добавит своё значение в итерации 6.
const String reviewModeClassic = 'classic';

/// Режим «Лента» (SPEC A7.3); пишется в `review_logs.mode` (ADR-016).
const String reviewModeFeed = 'feed';

/// Данные для отката одной оценки (undo, SPEC A6.4).
///
/// [previousCard] — полный снимок карточки до оценки, чтобы компенсирующая
/// транзакция восстановила `state`/`fsrs_json`/`due`/`updated_at` побитово.
class ReviewUndo {
  /// Создаёт токен отката.
  const ReviewUndo({required this.logId, required this.previousCard});

  /// Идентификатор строки `review_logs`, которую нужно удалить при откате.
  final String logId;

  /// Снимок карточки до оценки.
  final Card previousCard;

  @override
  String toString() => 'ReviewUndo(logId: $logId, cardId: ${previousCard.id})';
}
