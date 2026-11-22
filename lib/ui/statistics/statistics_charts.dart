/// Графики экрана статистики (SPEC A6.5, ADR-019 §4).
///
/// Без сторонних библиотек: недельный бар-чарт и годовая тепловая карта
/// собираются на токенах темы. Значения — данные калькулятора, подписи дат —
/// краткие формы CLDR через `intl` (локаль ru).
library;

import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Ширина столбца недельного графика при любой ширине колонки.
///
/// Находка D5 аудита: столбец растягивался на всю ячейку (≈153 px), и максимум
/// выглядел «кляксой». Ширина ограничена 12–20 px — на экране 390 px и на
/// широком мониторе столбик остаётся узким.
@visibleForTesting
double statisticsWeekBarWidth(double columnWidth) =>
    (columnWidth * 0.45).clamp(12.0, 20.0);

/// Толщина базовой линии под нулевым днём (D5/D7).
const double _baselineHeight = 2;

/// Минимальная высота ненулевого столбца: он должен быть заметно выше
/// базовой линии, иначе одно повторение не отличить от нуля.
const double _minBarHeight = 4;

/// Максимальная ширина недельного графика: на широком экране 7 столбцов
/// не растягиваются на всю карточку, а остаются компактной группой.
const double _maxWeekChartWidth = 480;

final DateFormat _weekdayFormat = DateFormat('E', 'ru');

/// Краткая подпись дня недели для графиков (Пн, Вт, …, Вс).
///
/// `MaterialLocalizations` в `material_ui` даёт только `narrowWeekdays`, а для
/// локали `ru` это одна буква (В/П/В/С/Ч/П/С) — ровно находка D7 аудита.
/// Поэтому берём краткую форму CLDR через `intl` (та же локаль ru, что и у
/// подписей месяцев карты) и поднимаем регистр первой буквы.
String statisticsWeekdayLabel(DateTime day) {
  final String label = _weekdayFormat.format(day);
  if (label.isEmpty) return label;
  return label.substring(0, 1).toUpperCase() + label.substring(1);
}

/// Недельный бар-чарт: 7 узких столбцов с подписями дней и значений (D5).
///
/// Столбцы стоят на общей базовой линии: нулевой день виден тонкой линией, а
/// не 4-пиксельной чёрточкой; значения — над столбцами, подписи дней — под
/// ними. Высота 96–120 px, ширина столбца 12–20 px (`statisticsWeekBarWidth`).
class StatisticsWaveform extends StatelessWidget {
  /// Создаёт недельный график.
  const StatisticsWaveform({
    required this.values,
    required this.labels,
    this.semanticsLabel,
    this.height = 120,
    super.key,
  });

  /// Значения столбцов (ноль допустим), старые → сегодня.
  final List<int> values;

  /// Подписи дней под столбцами (`labels[i]` для `values[i]`).
  final List<String> labels;

  /// Семантика графика для screen-reader.
  final String? semanticsLabel;

  /// Высота всего графика вместе с подписями значений и дней.
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int maxValue = values.isEmpty ? 0 : values.reduce(math.max);
    final Widget chart = Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWeekChartWidth),
        child: SizedBox(
          height: height,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = math.max(1, values.length);
              final double columnWidth = constraints.maxWidth / columns;
              final double barWidth = statisticsWeekBarWidth(columnWidth);
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  for (int index = 0; index < values.length; index++)
                    Expanded(
                      child: _WeekBarColumn(
                        index: index,
                        value: values[index],
                        maxValue: maxValue,
                        label: index < labels.length ? labels[index] : '',
                        barWidth: barWidth,
                        barColor: scheme.primary,
                        baselineColor: scheme.outlineVariant,
                        isToday: index == values.length - 1,
                        semantics: l10n.statisticsChartBarSemantics(
                          index < labels.length ? labels[index] : '',
                          values[index],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );
    if (semanticsLabel == null) return chart;
    return Semantics(label: semanticsLabel, image: true, child: chart);
  }
}

class _WeekBarColumn extends StatelessWidget {
  const _WeekBarColumn({
    required this.index,
    required this.value,
    required this.maxValue,
    required this.label,
    required this.barWidth,
    required this.barColor,
    required this.baselineColor,
    required this.isToday,
    required this.semantics,
  });

  final int index;
  final int value;
  final int maxValue;
  final String label;
  final double barWidth;
  final Color barColor;
  final Color baselineColor;
  final bool isToday;
  final String semantics;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(
              value.toString(),
              key: ValueKey<String>('statistics-week-value-$index'),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Expanded(
              child: LayoutBuilder(
                builder: (BuildContext context, BoxConstraints constraints) {
                  final double areaHeight = constraints.maxHeight;
                  final double fraction = maxValue == 0 ? 0 : value / maxValue;
                  final double barHeight = value == 0
                      ? 0
                      : math.max(_minBarHeight, areaHeight * fraction);
                  return Stack(
                    alignment: Alignment.bottomCenter,
                    children: <Widget>[
                      SizedBox(
                        key: ValueKey<String>(
                          'statistics-week-baseline-$index',
                        ),
                        width: barWidth,
                        height: _baselineHeight,
                        child: ColoredBox(color: baselineColor),
                      ),
                      if (value > 0)
                        Container(
                          key: ValueKey<String>('statistics-week-bar-$index'),
                          width: barWidth,
                          height: barHeight,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadii.xs),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              label,
              key: ValueKey<String>('statistics-week-label-$index'),
              maxLines: 1,
              softWrap: false,
              style: theme.textTheme.labelSmall?.copyWith(
                color: isToday ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: isToday ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Годовая тепловая карта повторений (A6.5).
class StatisticsHeatmap extends StatelessWidget {
  /// Создаёт карту.
  const StatisticsHeatmap({required this.days, super.key});

  /// 365 дней, старые → сегодня.
  final List<DayCount> days;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<String> labels = heatmapMonthLabels(
      days,
      (DateTime day) => _monthName(day),
    );
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;
        final double cell = width <= 0
            ? 8
            : ((width - 40) / 53).clamp(5.0, 11.0);
        return CustomPaint(
          key: const ValueKey<String>('statistics-heatmap'),
          size: Size(width, 7 * (cell + 2) + 16),
          painter: _HeatmapPainter(
            days: days,
            monthLabels: labels,
            cell: cell,
            emptyColor: scheme.surfaceContainerHighest,
            color: scheme.primary,
            labelStyle: Theme.of(context).textTheme.labelSmall
                ?.copyWith(fontSize: 9, color: scheme.onSurfaceVariant),
          ),
        );
      },
    );
  }

  /// Короткое название месяца для подписи колонки карты (янв., фев., …).
  static String _monthName(DateTime day) {
    // MaterialLocalizations не даёт месяц без года: берём краткую форму intl
    // для русской локали (символы дат поставляются пакетом, без сети).
    return DateFormat('LLL', 'ru').format(day);
  }

  /// Подписи месяцев по колонкам карты: только чётные месяцы.
  ///
  /// Колонка карты на узком экране — 5–11 px; подпись каждого месяца
  /// перекрывала бы соседнюю. Январь/март/май/… дают зазор в 8–9 колонок.
  @visibleForTesting
  static List<String> heatmapMonthLabels(
    List<DayCount> days,
    String Function(DateTime day) format,
  ) {
    final int columns = math.max(1, (days.length / 7).ceil());
    final List<String> labels = List<String>.filled(columns, '');
    int? lastMonth;
    for (int index = 0; index < days.length; index++) {
      final DateTime day = days[index].day;
      if (lastMonth == day.month) continue;
      lastMonth = day.month;
      if (day.month.isOdd) continue;
      final int column = index ~/ 7;
      if (column < labels.length) labels[column] = format(day);
    }
    return labels;
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.days,
    required this.monthLabels,
    required this.cell,
    required this.emptyColor,
    required this.color,
    this.labelStyle,
  });

  final List<DayCount> days;
  final List<String> monthLabels;
  final double cell;
  final Color emptyColor;
  final Color color;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final int maxCount = days.map((DayCount day) => day.count).reduce(math.max);
    final double step = cell + 2;
    final Paint paint = Paint();
    final double top = 14;
    for (int index = 0; index < days.length; index++) {
      final int column = index ~/ 7;
      final int row = index % 7;
      final int count = days[index].count;
      paint.color = count == 0
          ? emptyColor
          : color.withValues(
              alpha: 0.25 + 0.75 * (maxCount == 0 ? 0 : count / maxCount),
            );
      final RRect cellRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(column * step, top + row * step, cell, cell),
        const Radius.circular(2),
      );
      canvas.drawRRect(cellRect, paint);
    }
    final TextStyle style = labelStyle ?? const TextStyle(fontSize: 9);
    for (int column = 0; column < monthLabels.length; column++) {
      final String label = monthLabels[column];
      if (label.isEmpty) continue;
      final TextPainter painter = TextPainter(
        text: TextSpan(text: label, style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      painter.paint(canvas, Offset(column * step, 0));
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.cell != cell ||
      oldDelegate.color != color;
}
