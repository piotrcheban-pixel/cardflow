import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/ui/review/review_interval_format.dart';

/// Красная фаза итерации 2: форматирование прогноза интервала над кнопками
/// (SPEC A7.2).
void main() {
  test('меньше минуты — lessThanMinute', () {
    expect(
      formatReviewInterval(const Duration(seconds: 30)),
      const ReviewIntervalText(ReviewIntervalUnit.lessThanMinute, 0),
    );
    expect(
      formatReviewInterval(Duration.zero),
      const ReviewIntervalText(ReviewIntervalUnit.lessThanMinute, 0),
    );
  });

  test('минуты округляются до ближайшей', () {
    expect(
      formatReviewInterval(const Duration(minutes: 1)),
      const ReviewIntervalText(ReviewIntervalUnit.minutes, 1),
    );
    expect(
      formatReviewInterval(const Duration(minutes: 5, seconds: 30)),
      const ReviewIntervalText(ReviewIntervalUnit.minutes, 6),
    );
    expect(
      formatReviewInterval(const Duration(minutes: 45)),
      const ReviewIntervalText(ReviewIntervalUnit.minutes, 45),
    );
  });

  test('часы и дни', () {
    expect(
      formatReviewInterval(const Duration(minutes: 90)),
      const ReviewIntervalText(ReviewIntervalUnit.hours, 2),
    );
    expect(
      formatReviewInterval(const Duration(days: 16)),
      const ReviewIntervalText(ReviewIntervalUnit.days, 16),
    );
    expect(
      formatReviewInterval(const Duration(days: 1)),
      const ReviewIntervalText(ReviewIntervalUnit.days, 1),
    );
  });

  test('равные значения равны и имеют одинаковый hashCode', () {
    const a = ReviewIntervalText(ReviewIntervalUnit.days, 7);
    const b = ReviewIntervalText(ReviewIntervalUnit.days, 7);
    expect(a, b);
    expect(a.hashCode, b.hashCode);
    expect(a.toString(), contains('days'));
  });
}
