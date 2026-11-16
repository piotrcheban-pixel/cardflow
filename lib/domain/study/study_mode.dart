/// Режимы изучения CardFlow (итерация 7.15).
///
/// `classic`, `feed` и `practice` существуют с прошлых итераций; `test` (Тест),
/// `typing` (Ввод ответа), `match` (Подбор пар) и `true_false` (Верно/Неверно)
/// добавлены в 7.15/7.16. `wireName` пишется в `review_logs.mode` без изменений
/// схемы БД.
///
/// Политика FSRS (ADR-032): режим пишет расписание только для карточек, которые
/// пора повторять (`StudyFsrsPolicy`); остальные карточки проходятся как
/// тренировка — журнал `review_logs` без `scheduled_days`/`actual_days`.
library;

/// Режим изучения.
enum StudyMode {
  /// Классическое повторение (SPEC A7.2).
  classic('classic'),

  /// Лента (SPEC A7.3).
  feed('feed'),

  /// Тренировка без FSRS (ADR-025).
  practice('practice'),

  /// Конструктор сессии — не сессия, а настройка (A6.7).
  constructor('classic'),

  /// Тест с вариантами ответа (7.15).
  test('test'),

  /// Ввод ответа (7.15).
  typing('typing'),

  /// Подбор пар (7.16): игровой режим, в FSRS ничего не пишется.
  match('match'),

  /// Верно/Неверно (7.16).
  trueFalse('true_false');

  const StudyMode(this.wireName);

  /// Значение для `review_logs.mode`.
  final String wireName;

  /// Пишет ли режим журнал оценок (match — только таймер/результат).
  bool get writesReviewLog => this != constructor && this != match;

  /// Может ли режим писать расписание FSRS для due-карточек.
  bool get canWriteFsrs => switch (this) {
    classic || feed || test || typing || trueFalse => true,
    practice || constructor || match => false,
  };

  /// Разбирает wire-значение; `null` — неизвестный режим.
  static StudyMode? tryParse(Object? value) {
    if (value is! String) return null;
    for (final StudyMode mode in values) {
      if (mode.wireName == value) return mode;
    }
    return null;
  }
}
