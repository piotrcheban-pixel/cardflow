import 'package:intl/date_symbol_data_local.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/statistics/statistics_charts.dart';

/// A6.5/ADR-019: подписи месяцев карты и геометрия недельного графика.
void main() {
  setUpAll(() async {
    // Подписи дней недели берутся из CLDR через `intl` (см.
    // `statisticsWeekdayLabel`); в приложении эти данные грузит делегат
    // Material-локализации, в чистом тесте — явно.
    await initializeDateFormatting('ru');
  });

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

  // Аудит 2.0: прежний предел 20 px давал на широкой карточке (ячейка ≈68 px)
  // «спички»; столбец стал половиной ячейки (14–32 px), но по-прежнему не
  // занимает её целиком — исходная находка D5 про «кляксу» 153 px закрыта.
  test('ширина столбца недельного графика — 14–32 px на любой ширине (D5)', () {
    for (final double columnWidth in <double>[0, 20, 30, 45, 80, 172, 400]) {
      expect(
        statisticsWeekBarWidth(columnWidth),
        inInclusiveRange(14.0, 32.0),
        reason: 'columnWidth=$columnWidth',
      );
    }
    expect(statisticsWeekBarWidth(172), 32.0);
    expect(statisticsWeekBarWidth(20), 14.0);
    expect(
      statisticsWeekBarWidth(68),
      lessThan(68 * 0.6),
      reason: 'столбец не занимает всю ячейку',
    );
  });

  test('подписи дней недели — краткая форма ru, а не одна буква (D7)', () {
    // 23.11.2026 — понедельник, далее по календарю до воскресенья.
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 23)), 'Пн');
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 24)), 'Вт');
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 25)), 'Ср');
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 26)), 'Чт');
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 27)), 'Пт');
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 28)), 'Сб');
    expect(statisticsWeekdayLabel(DateTime(2026, 11, 29)), 'Вс');
  });
}
