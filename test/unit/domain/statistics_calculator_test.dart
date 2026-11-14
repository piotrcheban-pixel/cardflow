import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/statistics/statistics.dart';

void main() {
  final DateTime now = DateTime(2026, 11, 14, 12);
  final DateTime today = DateTime(2026, 11, 14);

  ReviewSample review(String cardId, int rating, DateTime at) =>
      ReviewSample(cardId: cardId, rating: rating, reviewedAt: at);

  group('StatisticsCalculator — пустые данные', () {
    test('нулевые блоки, retention нет, окна корректных размеров', () {
      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: const <ReviewSample>[],
        tagsByCard: const <String, List<String>>{},
        dueDates: const <DateTime>[],
        now: now,
        tokensWeek: 42,
      );

      expect(snapshot.retention30, isNull);
      expect(snapshot.totalReviewsYear, 0);
      expect(snapshot.heatmap.length, StatisticsCalculator.heatmapDays);
      expect(snapshot.heatmap.first.day, DateTime(2025, 11, 15));
      expect(snapshot.heatmap.last.day, today);
      expect(snapshot.heatmap.every((DayCount day) => day.count == 0), isTrue);
      expect(snapshot.week.length, StatisticsCalculator.weekDays);
      expect(snapshot.week.first.day, DateTime(2026, 11, 8));
      expect(snapshot.week.last.day, today);
      expect(snapshot.weakTopics, isEmpty);
      expect(snapshot.forecast.length, StatisticsCalculator.forecastDays);
      expect(
        snapshot.forecast.every((ForecastDay day) => day.due == 0),
        isTrue,
      );
      expect(snapshot.tokensWeek, 42);
      expect(snapshot.isEmpty, isTrue);
    });
  });

  group('StatisticsCalculator — удержание', () {
    test('окно 30 дней включительно; Again — ошибка', () {
      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: <ReviewSample>[
          review('a', 1, today),
          review('b', 3, DateTime(2026, 11, 13, 9)),
          review('c', 4, DateTime(2026, 10, 16, 9)), // today - 29
          review('d', 1, DateTime(2026, 10, 15, 9)), // today - 30 — вне окна
          review('e', 3, DateTime(2026, 10, 14, 9)), // today - 31 — вне окна
        ],
        tagsByCard: const <String, List<String>>{},
        dueDates: const <DateTime>[],
        now: now,
      );

      expect(snapshot.totalReviewsYear, 5);
      expect(snapshot.reviews30, 3);
      expect(snapshot.remembered30, 2);
      expect(snapshot.retention30, closeTo(2 / 3, 1e-9));
    });

    test('все верно — 100 %, все Again — 0 %', () {
      final StatisticsSnapshot good = StatisticsCalculator.build(
        reviews: <ReviewSample>[review('a', 3, today)],
        tagsByCard: const <String, List<String>>{},
        dueDates: const <DateTime>[],
        now: now,
      );
      expect(good.retention30, 1.0);

      final StatisticsSnapshot bad = StatisticsCalculator.build(
        reviews: <ReviewSample>[review('a', 1, today)],
        tagsByCard: const <String, List<String>>{},
        dueDates: const <DateTime>[],
        now: now,
      );
      expect(bad.retention30, 0.0);
    });
  });

  group('StatisticsCalculator — тепловая карта и неделя', () {
    test('год: порядок старые→сегодня, границы года, счётчики', () {
      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: <ReviewSample>[
          review('a', 3, today),
          review('b', 2, today.add(const Duration(hours: 1))),
          review('c', 3, DateTime(2026, 11, 13, 9)),
          review('d', 3, DateTime(2025, 11, 15, 9)), // today - 364
          review('e', 3, DateTime(2025, 11, 14, 9)), // today - 365 — вне окна
        ],
        tagsByCard: const <String, List<String>>{},
        dueDates: const <DateTime>[],
        now: now,
      );

      expect(snapshot.heatmap.length, 365);
      expect(snapshot.heatmap[364].count, 2);
      expect(snapshot.heatmap[363].count, 1);
      expect(snapshot.heatmap[0].count, 1);
      expect(snapshot.heatmap[0].day, DateTime(2025, 11, 15));

      expect(snapshot.week.length, 7);
      expect(snapshot.week[6].count, 2);
      expect(snapshot.week[5].count, 1);
      expect(snapshot.week.take(5).every((DayCount d) => d.count == 0), isTrue);
    });
  });

  group('StatisticsCalculator — слабые темы', () {
    test('порог 5 повторов и 20 % ошибок', () {
      final Map<String, List<String>> tags = <String, List<String>>{
        'math': <String>['алгебра'],
        'bio': <String>['биология'],
        'exam': <String>['экзамен'],
      };
      final List<ReviewSample> reviews = <ReviewSample>[
        for (int i = 0; i < 3; i++)
          review('math', i < 1 ? 1 : 3, today.subtract(Duration(days: i))),
        for (int i = 0; i < 5; i++)
          review('bio', i < 1 ? 1 : 3, today.subtract(Duration(days: i))),
        for (int i = 0; i < 4; i++)
          review('exam', 1, today.subtract(Duration(days: i))),
      ];

      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: reviews,
        tagsByCard: tags,
        dueDates: const <DateTime>[],
        now: now,
      );

      expect(snapshot.weakTopics.length, 1);
      final WeakTopic topic = snapshot.weakTopics.single;
      expect(topic.tag, 'биология');
      expect(topic.reviews, 5);
      expect(topic.errors, 1);
    });

    test('сортировка по доле ошибок, затем по числу ошибок, затем по тегу', () {
      final Map<String, List<String>> tags = <String, List<String>>{
        for (final String tag in <String>['a', 'b', 'c', 'd'])
          'card_$tag': <String>[tag],
      };
      final List<ReviewSample> reviews = <ReviewSample>[
        for (int i = 0; i < 5; i++)
          review('card_a', i < 2 ? 1 : 3, today), // 40 %
        for (int i = 0; i < 5; i++)
          review('card_b', i < 4 ? 1 : 3, today), // 80 %
        for (int i = 0; i < 5; i++)
          review('card_c', i < 4 ? 1 : 3, today), // 80 %, тег c
        for (int i = 0; i < 5; i++)
          review('card_d', i < 1 ? 1 : 3, today), // 20 %
      ];

      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: reviews,
        tagsByCard: tags,
        dueDates: const <DateTime>[],
        now: now,
      );

      expect(
        snapshot.weakTopics.map((WeakTopic topic) => topic.tag).toList(),
        <String>['b', 'c', 'a', 'd'],
      );
    });

    test('не больше пяти тем; несколько тегов карточки учитываются', () {
      final Map<String, List<String>> tags = <String, List<String>>{
        'card_0': <String>['t0', 'shared'],
        for (int i = 1; i < 7; i++) 'card_$i': <String>['t$i'],
      };
      final List<ReviewSample> reviews = <ReviewSample>[
        for (int i = 0; i < 5; i++) review('card_0', 1, today),
        for (int i = 1; i < 7; i++)
          for (int j = 0; j < 5; j++) review('card_$i', 1, today),
      ];

      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: reviews,
        tagsByCard: tags,
        dueDates: const <DateTime>[],
        now: now,
      );

      expect(snapshot.weakTopics.length, StatisticsCalculator.maxWeakTopics);
      final WeakTopic shared = snapshot.weakTopics.firstWhere(
        (WeakTopic topic) => topic.tag == 'shared',
      );
      expect(shared.reviews, 5);
      expect(shared.errors, 5);
      expect(snapshot.weakTopics.map((WeakTopic t) => t.tag), contains('t0'));
    });

    test('карточка без тегов и повторения вне года не попадают', () {
      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: <ReviewSample>[
          for (int i = 0; i < 5; i++)
            review('card_old', 1, DateTime(2025, 1, 1, 9)),
          for (int i = 0; i < 5; i++) review('card_untagged', 1, today),
        ],
        tagsByCard: <String, List<String>>{
          'card_old': <String>['old'],
        },
        dueDates: const <DateTime>[],
        now: now,
      );

      expect(snapshot.weakTopics, isEmpty);
    });
  });

  group('StatisticsCalculator — прогноз', () {
    test('просроченные → сегодня, только 7 дней', () {
      final StatisticsSnapshot snapshot = StatisticsCalculator.build(
        reviews: const <ReviewSample>[],
        tagsByCard: const <String, List<String>>{},
        dueDates: <DateTime>[
          DateTime(2026, 11, 11, 8), // просрочено
          DateTime(2026, 11, 13, 8), // просрочено
          today.add(const Duration(hours: 18)),
          DateTime(2026, 11, 16, 9), // today + 2
          DateTime(2026, 11, 16, 20),
          DateTime(2026, 11, 21, 9), // today + 7 — вне прогноза
        ],
        now: now,
      );

      expect(snapshot.forecast.length, 7);
      expect(snapshot.forecast[0].due, 3);
      expect(snapshot.forecast[2].due, 2);
      expect(snapshot.forecast[6].due, 0);
      expect(snapshot.forecast[0].day, today);
    });
  });
}
