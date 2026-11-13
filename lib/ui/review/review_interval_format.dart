/// Форматирование прогноза интервала над кнопками оценок (SPEC A7.2).
///
/// Домен отдаёт `Duration`; пользователю показываем короткую запись без
/// падежных проблем: «<1 мин», «N мин», «N ч», «N д». Точные значения
/// вычисляет планировщик — здесь только округление для отображения.
library;

/// Единица отображения прогноза.
enum ReviewIntervalUnit {
  /// Меньше минуты.
  lessThanMinute,

  /// Минуты.
  minutes,

  /// Часы.
  hours,

  /// Дни.
  days,
}

/// Текст прогноза: единица + число (для [ReviewIntervalUnit.lessThanMinute]
/// число не используется и равно 0).
class ReviewIntervalText {
  /// Создаёт текст прогноза.
  const ReviewIntervalText(this.unit, this.count);

  /// Единица.
  final ReviewIntervalUnit unit;

  /// Число единиц (округлённое).
  final int count;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReviewIntervalText &&
          other.unit == unit &&
          other.count == count;

  @override
  int get hashCode => Object.hash(unit, count);

  @override
  String toString() => 'ReviewIntervalText($unit, $count)';
}

/// Округляет [interval] для подписи над кнопкой.
ReviewIntervalText formatReviewInterval(Duration interval) {
  return const ReviewIntervalText(ReviewIntervalUnit.lessThanMinute, 0);
}
