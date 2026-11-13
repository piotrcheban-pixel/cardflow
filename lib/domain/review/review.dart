import '../cards/card.dart';

/// Режим повторения, записываемый в `review_logs.mode` (SPEC A5).
///
/// В итерации 2 существует только классический режим (SPEC A7.2); «Лента» и
/// «Конструктор» добавят свои значения в итерациях 4/6.
const String reviewModeClassic = 'classic';

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
