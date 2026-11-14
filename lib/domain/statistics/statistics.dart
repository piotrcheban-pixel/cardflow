/// Статистика обучения (SPEC A6.5, ADR-019 §4).
///
/// Чистый домен без Flutter/БД: снимок агрегатов и калькулятор поверх
/// сэмплов повторений/тегов/дат `due`. Схема БД не меняется.
library;

/// Один сэмпл `review_logs` для статистики.
class ReviewSample {
  /// Создаёт сэмпл.
  const ReviewSample({
    required this.cardId,
    required this.rating,
    required this.reviewedAt,
  });

  /// Карточка.
  final String cardId;

  /// Оценка 1 Again … 4 Easy.
  final int rating;

  /// Момент повторения (любая зона; калькулятор приводит к локальной).
  final DateTime reviewedAt;
}

/// Число повторений за день.
class DayCount {
  /// Создаёт точку.
  const DayCount({required this.day, required this.count});

  /// Локальный день (полночь).
  final DateTime day;

  /// Число повторений.
  final int count;

  @override
  bool operator ==(Object other) =>
      other is DayCount && other.day == day && other.count == count;

  @override
  int get hashCode => Object.hash(day, count);

  @override
  String toString() => 'DayCount($day: $count)';
}

/// Карточки к повторению в конкретный день.
class ForecastDay {
  /// Создаёт точку прогноза.
  const ForecastDay({required this.day, required this.due});

  /// Локальный день (полночь).
  final DateTime day;

  /// Сколько карточек к повторению.
  final int due;

  @override
  bool operator ==(Object other) =>
      other is ForecastDay && other.day == day && other.due == due;

  @override
  int get hashCode => Object.hash(day, due);

  @override
  String toString() => 'ForecastDay($day: $due)';
}

/// Слабая тема: тег с высокой долей ошибок.
class WeakTopic {
  /// Создаёт тему.
  const WeakTopic({
    required this.tag,
    required this.reviews,
    required this.errors,
  });

  /// Тег.
  final String tag;

  /// Число повторений карточек с тегом.
  final int reviews;

  /// Число оценок Again.
  final int errors;

  /// Доля ошибок 0..1.
  double get errorRate => reviews == 0 ? 0 : errors / reviews;

  @override
  bool operator ==(Object other) =>
      other is WeakTopic &&
      other.tag == tag &&
      other.reviews == reviews &&
      other.errors == errors;

  @override
  int get hashCode => Object.hash(tag, reviews, errors);

  @override
  String toString() => 'WeakTopic($tag: $errors/$reviews)';
}

/// Снимок экрана «Статистика» (A6.5).
class StatisticsSnapshot {
  /// Создаёт снимок.
  const StatisticsSnapshot({
    required this.totalReviewsYear,
    required this.reviews30,
    required this.remembered30,
    required this.heatmap,
    required this.week,
    required this.weakTopics,
    required this.forecast,
    required this.tokensWeek,
  });

  /// Сколько повторений попало в окно года (для пустого состояния).
  final int totalReviewsYear;

  /// Число оценок за 30 дней.
  final int reviews30;

  /// Число «вспомнил» (rating > 1) за 30 дней.
  final int remembered30;

  /// 365 дней, старые → сегодня.
  final List<DayCount> heatmap;

  /// 7 дней, старые → сегодня.
  final List<DayCount> week;

  /// Слабые теги (топ-5).
  final List<WeakTopic> weakTopics;

  /// 7 дней прогноза, сегодня → +6.
  final List<ForecastDay> forecast;

  /// Токены генерации за неделю.
  final int tokensWeek;

  /// Удержание за 30 дней; `null` — оценок не было.
  double? get retention30 => reviews30 == 0 ? null : remembered30 / reviews30;

  /// На экране нет данных: не было повторений и нет прогноза.
  bool get isEmpty =>
      totalReviewsYear == 0 &&
      forecast.every((ForecastDay day) => day.due == 0);
}

/// Калькулятор статистики (ADR-019 §4).
abstract final class StatisticsCalculator {
  /// Окно удержания, дней.
  static const int retentionDays = 30;

  /// Годовое окно тепловой карты, дней.
  static const int heatmapDays = 365;

  /// Недельное окно, дней.
  static const int weekDays = 7;

  /// Горизонт прогноза, дней.
  static const int forecastDays = 7;

  /// Минимум повторений для слабого тега.
  static const int weakTopicMinReviews = 5;

  /// Минимальная доля ошибок для слабого тега.
  static const double weakTopicMinErrorRate = 0.2;

  /// Сколько слабых тем показываем.
  static const int maxWeakTopics = 5;

  /// Строит снимок.
  static StatisticsSnapshot build({
    required List<ReviewSample> reviews,
    required Map<String, List<String>> tagsByCard,
    required List<DateTime> dueDates,
    required DateTime now,
    int tokensWeek = 0,
  }) {
    final DateTime today = _dayOf(now);
    final List<int> heatmapCounts = List<int>.filled(heatmapDays, 0);
    final List<int> weekCounts = List<int>.filled(weekDays, 0);
    final Map<String, _TopicAccumulator> topics = <String, _TopicAccumulator>{};
    int totalReviewsYear = 0;
    int reviews30 = 0;
    int remembered30 = 0;

    for (final ReviewSample review in reviews) {
      final int offset = _daysBetween(_dayOf(review.reviewedAt), today);
      if (offset < 0 || offset >= heatmapDays) continue;
      totalReviewsYear++;
      heatmapCounts[heatmapDays - 1 - offset] =
          heatmapCounts[heatmapDays - 1 - offset] + 1;
      if (offset < weekDays) {
        weekCounts[weekDays - 1 - offset] =
            weekCounts[weekDays - 1 - offset] + 1;
      }
      if (offset < retentionDays) {
        reviews30++;
        if (review.rating > 1) remembered30++;
      }
      final List<String> tags = tagsByCard[review.cardId] ?? const <String>[];
      final Set<String> uniqueTags = <String>{};
      for (final String tag in tags) {
        if (tag.trim().isEmpty || !uniqueTags.add(tag)) continue;
        final _TopicAccumulator accumulator =
            topics[tag] ?? _TopicAccumulator(tag);
        accumulator.reviews++;
        if (review.rating == 1) accumulator.errors++;
        topics[tag] = accumulator;
      }
    }

    final List<WeakTopic> weakTopics = <WeakTopic>[
      for (final _TopicAccumulator topic in topics.values)
        if (topic.reviews >= weakTopicMinReviews &&
            topic.errorRate >= weakTopicMinErrorRate)
          WeakTopic(
            tag: topic.tag,
            reviews: topic.reviews,
            errors: topic.errors,
          ),
    ];
    weakTopics.sort((WeakTopic a, WeakTopic b) {
      final int byRate = b.errorRate.compareTo(a.errorRate);
      if (byRate != 0) return byRate;
      final int byErrors = b.errors.compareTo(a.errors);
      if (byErrors != 0) return byErrors;
      final int byLower = a.tag.toLowerCase().compareTo(b.tag.toLowerCase());
      return byLower != 0 ? byLower : a.tag.compareTo(b.tag);
    });

    final List<int> forecastCounts = List<int>.filled(forecastDays, 0);
    for (final DateTime due in dueDates) {
      final int age = _daysBetween(_dayOf(due), today);
      if (age >= 0) {
        forecastCounts[0] = forecastCounts[0] + 1;
      } else if (-age < forecastDays) {
        forecastCounts[-age] = forecastCounts[-age] + 1;
      }
    }

    final List<DayCount> heatmap = <DayCount>[
      for (int index = 0; index < heatmapDays; index++)
        DayCount(
          day: _addDays(today, index - (heatmapDays - 1)),
          count: heatmapCounts[index],
        ),
    ];
    final List<DayCount> week = <DayCount>[
      for (int index = 0; index < weekDays; index++)
        DayCount(
          day: _addDays(today, index - (weekDays - 1)),
          count: weekCounts[index],
        ),
    ];
    final List<ForecastDay> forecast = <ForecastDay>[
      for (int index = 0; index < forecastDays; index++)
        ForecastDay(day: _addDays(today, index), due: forecastCounts[index]),
    ];

    return StatisticsSnapshot(
      totalReviewsYear: totalReviewsYear,
      reviews30: reviews30,
      remembered30: remembered30,
      heatmap: List<DayCount>.unmodifiable(heatmap),
      week: List<DayCount>.unmodifiable(week),
      weakTopics: List<WeakTopic>.unmodifiable(weakTopics.take(maxWeakTopics)),
      forecast: List<ForecastDay>.unmodifiable(forecast),
      tokensWeek: tokensWeek,
    );
  }

  static DateTime _dayOf(DateTime value) {
    final DateTime local = value.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static DateTime _addDays(DateTime day, int delta) =>
      DateTime(day.year, day.month, day.day + delta);

  /// Разница календарных дней независимо от перехода на летнее время.
  static int _daysBetween(DateTime from, DateTime to) {
    final DateTime utcFrom = DateTime.utc(from.year, from.month, from.day);
    final DateTime utcTo = DateTime.utc(to.year, to.month, to.day);
    return utcTo.difference(utcFrom).inDays;
  }
}

/// Накопитель по тегу внутри калькулятора.
class _TopicAccumulator {
  _TopicAccumulator(this.tag);

  final String tag;
  int reviews = 0;
  int errors = 0;

  double get errorRate => reviews == 0 ? 0 : errors / reviews;
}
