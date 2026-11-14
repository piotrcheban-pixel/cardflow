import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/review/feed_swipe.dart';

/// Красная фаза итерации 4: пороги свайпов-оценок ленты (SPEC A7.3, ADR-016).
void main() {
  const double width = 600;

  group('feedSwipeRating: короткий свайп', () {
    test('вправо быстрый (≥80 px и ≥300 px/с) — «Знаю»', () {
      expect(feedSwipeRating(dx: 80, velocity: 300, width: width), Rating.good);
      expect(
        feedSwipeRating(dx: 240, velocity: 1200, width: width),
        Rating.good,
      );
    });

    test('вправо медленный — оценка не засчитывается', () {
      expect(feedSwipeRating(dx: 120, velocity: 0, width: width), isNull);
      expect(feedSwipeRating(dx: 359, velocity: 299, width: width), isNull);
    });

    test('вправо короче 80 px — даже при огромной скорости null', () {
      expect(feedSwipeRating(dx: 79.9, velocity: 5000, width: width), isNull);
    });

    test('влево быстрый (≥80 px и ≤−300 px/с) — «Не знаю»', () {
      expect(
        feedSwipeRating(dx: -80, velocity: -300, width: width),
        Rating.again,
      );
      expect(
        feedSwipeRating(dx: -240, velocity: -1200, width: width),
        Rating.again,
      );
    });

    test('влево медленный или с положительной скоростью — null', () {
      expect(feedSwipeRating(dx: -120, velocity: 0, width: width), isNull);
      expect(feedSwipeRating(dx: -120, velocity: 1000, width: width), isNull);
    });
  });

  group('feedSwipeRating: долгий свайп (>60% ширины)', () {
    test('вправо ровно 60% — «Легко», скорость не нужна', () {
      expect(
        feedSwipeRating(dx: width * 0.6, velocity: 0, width: width),
        Rating.easy,
      );
      expect(
        feedSwipeRating(dx: width, velocity: -500, width: width),
        Rating.easy,
      );
    });

    test('вправо меньше 60% при медленном жесте — null', () {
      expect(
        feedSwipeRating(dx: width * 0.6 - 0.1, velocity: 0, width: width),
        isNull,
      );
    });

    test('влево ровно 60% — «Сложно», скорость не нужна', () {
      expect(
        feedSwipeRating(dx: -width * 0.6, velocity: 0, width: width),
        Rating.hard,
      );
      expect(
        feedSwipeRating(dx: -width * 0.8, velocity: 500, width: width),
        Rating.hard,
      );
    });

    test('влево меньше 60% при медленном жесте — null', () {
      expect(
        feedSwipeRating(dx: -width * 0.6 + 0.1, velocity: 0, width: width),
        isNull,
      );
    });

    test('долгий свайп важнее порога 80 px на узкой карточке', () {
      expect(feedSwipeRating(dx: 70, velocity: 0, width: 100), Rating.easy);
      expect(feedSwipeRating(dx: -70, velocity: 0, width: 100), Rating.hard);
    });
  });

  group('feedSwipeRating: вырожденные случаи', () {
    test('нулевое смещение — null', () {
      expect(feedSwipeRating(dx: 0, velocity: 5000, width: width), isNull);
    });

    test('неизвестная ширина — null', () {
      expect(feedSwipeRating(dx: 200, velocity: 1000, width: 0), isNull);
      expect(feedSwipeRating(dx: 200, velocity: 1000, width: -1), isNull);
    });
  });
}
