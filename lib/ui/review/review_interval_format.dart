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
      other is ReviewIntervalText && other.unit == unit && other.count == count;

  @override
  int get hashCode => Object.hash(unit, count);

  @override
  String toString() => 'ReviewIntervalText($unit, $count)';
}

/// Округляет [interval] для подписи над кнопкой.
///
/// Правила (SPEC A7.2 — «прогноз интервала»):
/// меньше минуты → «<1 мин»; меньше часа → минуты; меньше суток → часы;
/// иначе — дни. Значение округляется до ближайшего; при округлении до 60 минут
/// или 24 часов единица переключается на старшую, чтобы не показывать
/// «60 мин» / «24 ч».
ReviewIntervalText formatReviewInterval(Duration interval) {
  if (interval < const Duration(minutes: 1)) {
    return const ReviewIntervalText(ReviewIntervalUnit.lessThanMinute, 0);
  }
  if (interval < const Duration(hours: 1)) {
    final int minutes = (interval.inSeconds / 60).round();
    if (minutes < 60) {
      return ReviewIntervalText(ReviewIntervalUnit.minutes, minutes);
    }
  }
  if (interval < const Duration(days: 1)) {
    final int hours = (interval.inMinutes / 60).round();
    if (hours < 24) {
      return ReviewIntervalText(ReviewIntervalUnit.hours, hours);
    }
  }
  final int days = (interval.inMinutes / Duration.minutesPerDay).round();
  return ReviewIntervalText(ReviewIntervalUnit.days, days < 1 ? 1 : days);
}
