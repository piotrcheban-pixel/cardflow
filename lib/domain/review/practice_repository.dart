import '../scheduling/rating.dart';

/// Порт записи оценок режима «Тренировка» (ADR-025, итерация 7.11).
///
/// Тренировка не меняет расписание FSRS: `cards.state`, `cards.fsrs_json` и
/// `cards.due` остаются нетронутыми, поэтому оценка — это только строка
/// журнала `review_logs` с `mode = 'practice'` (`scheduled_days` и
/// `actual_days` — `NULL`: повторение не планировалось).
abstract interface class PracticeRepository {
  /// Записывает оценку [rating] карточки [cardId] в момент [reviewedAt].
  ///
  /// [elapsed] — время от показа карточки до оценки.
  /// Возвращает id строки журнала для отката.
  Future<String> recordPractice({
    required String cardId,
    required Rating rating,
    required DateTime reviewedAt,
    Duration? elapsed,
  });

  /// Удаляет запись тренировки [logId] (undo).
  Future<void> undoPractice(String logId);
}
