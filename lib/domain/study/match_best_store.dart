/// Хранилище лучшего времени «Подбора пар» (итерация 7.16).
///
/// Схема БД не меняется: результат — JSON v1 в существующей таблице
/// `app_settings` под ключом `study.match.best`:
/// `{"version":1,"decks":{"<deckId>":<ms>}}`.
library;

/// Порт лучшего времени игры по колоде.
abstract interface class MatchBestStore {
  /// Лучшее время в миллисекундах; `null` — ещё не играли.
  Future<int?> bestMs(String deckId);

  /// Сохраняет результат, если он лучше прежнего.
  Future<void> saveIfBetter(String deckId, int milliseconds);
}
