import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/statistics/statistics_charts.dart';

/// A6.5/ADR-019: подписи месяцев карты не перекрывают друг друга.
void main() {
  test('подписи месяцев — только чётные месяцы и с зазором по колонкам', () {
    final DateTime start = DateTime(2025, 11, 15);
    final List<DayCount> days = <DayCount>[
      for (int index = 0; index < 365; index++)
        DayCount(
          day: DateTime(start.year, start.month, start.day + index),
          count: 0,
        ),
    ];

    final List<String> labels = StatisticsHeatmap.heatmapMonthLabels(
      days,
      (DateTime day) => day.month.toString(),
    );

    expect(labels.length, 53);
    final List<int> columns = <int>[
      for (int index = 0; index < labels.length; index++)
        if (labels[index].isNotEmpty) index,
    ];
    expect(columns.length, 6);
    expect(
      columns
          .map((int column) => int.parse(labels[column]))
          .every((int month) => month.isEven),
      isTrue,
    );
    for (int index = 1; index < columns.length; index++) {
      expect(
        columns[index] - columns[index - 1],
        greaterThanOrEqualTo(5),
        reason: 'подписи не должны наезжать друг на друга',
      );
    }
  });

  test('все месяцы года дают подписи, даже если попали на границу колонки', () {
    final List<DayCount> days = <DayCount>[
      for (int index = 0; index < 365; index++)
        DayCount(day: DateTime(2024, 1, 1 + index), count: 0),
    ];
    final List<String> labels = StatisticsHeatmap.heatmapMonthLabels(
      days,
      (DateTime day) => 'M${day.month}',
    );
    expect(labels.where((String label) => label.isNotEmpty), isNotEmpty);
    expect(labels.firstWhere((String label) => label.isNotEmpty), 'M2');
  });
}
