/// Оценки повторения карточки (SPEC A7.2): «Не знаю» / «Сложно» / «Знаю» / «Легко».
///
/// Числовые значения 1..4 совпадают с пакетом `fsrs` и колонкой
/// `review_logs.rating` (SPEC A5): 1 Again, 2 Hard, 3 Good, 4 Easy.
enum Rating {
  /// «Не знаю» — оценка Again.
  again(1),

  /// «Сложно» — оценка Hard.
  hard(2),

  /// «Знаю» — оценка Good.
  good(3),

  /// «Легко» — оценка Easy.
  easy(4);

  const Rating(this.value);

  /// Числовое значение для хранения в БД и FSRS.
  final int value;

  /// Восстанавливает оценку по значению 1..4.
  static Rating fromValue(int value) => switch (value) {
    1 => Rating.again,
    2 => Rating.hard,
    3 => Rating.good,
    4 => Rating.easy,
    _ => throw ArgumentError('Недопустимая оценка: $value'),
  };
}
