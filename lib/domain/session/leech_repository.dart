/// Счётчики провалов для фильтра «Пиявки» (SPEC A6.7/A7.17, ADR-018).
library;

/// Порог пиявки: 8+ провалов (A7.17).
const int leechFailureThreshold = 8;

/// Порт подсчёта провалов (`review_logs.rating = 1`) по карточкам.
abstract interface class LeechRepository {
  /// Число провалов по карточкам указанных колод.
  ///
  /// Возвращаются только карточки с хотя бы одним провалом; отсутствие
  /// карточки в карте означает 0 провалов.
  Future<Map<String, int>> failureCounts({required Iterable<String> deckIds});
}
