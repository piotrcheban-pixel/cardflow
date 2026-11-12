// Преобразование времени БД ↔ `DateTime` (SPEC A5: INTEGER = epoch ms).
//
// Домен и репозитории работают с `DateTime` в UTC; в БД SQLite (INTEGER)
// хранятся миллисекунды эпохи. Одна пара функций на весь data-слой, чтобы
// формат не разъезжался между таблицами.
library;

/// `DateTime` → epoch миллисекунды (UTC), как INTEGER в SPEC A5.
int toEpochMs(DateTime value) => value.toUtc().millisecondsSinceEpoch;

/// epoch миллисекунды (UTC) → `DateTime` в UTC.
///
/// В БД время всегда хранится в UTC, поэтому чтение возвращает UTC-момент.
DateTime fromEpochMs(int value) =>
    DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
