/// Графики экрана статистики (SPEC A6.5, ADR-019 §4).
///
/// Без сторонних библиотек: waveform, годовая тепловая карта и недельный
/// прогресс рисуются `CustomPainter` на токенах темы. Значения — данные
/// калькулятора, подписи дат — `MaterialLocalizations` (локаль ru).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';

/// Waveform-индикатор на токенах темы (удержание/недельный прогресс).
class StatisticsWaveform extends StatelessWidget {
  /// Создаёт waveform.
  const StatisticsWaveform({
    required this.values,
    this.semanticsLabel,
    this.height = 56,
    super.key,
  });

  /// Значения столбцов (ноль допустим).
  final List<int> values;

  /// Семантика для screen-reader.
  final String? semanticsLabel;

  /// Высота графика.
  final double height;

  @override
  Widget build(BuildContext context) {
    final Color color = Theme.of(context).colorScheme.primary;
    final Widget canvas = CustomPaint(
      size: Size(double.infinity, height),
      painter: _WaveformPainter(values: values, color: color),
    );
    if (semanticsLabel == null) return canvas;
    return Semantics(label: semanticsLabel, image: true, child: canvas);
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty || size.width <= 0 || size.height <= 0) return;
    final int maxValue = values.reduce(math.max);
    final double gap = 4;
    final double barWidth =
        (size.width - gap * (values.length - 1)) / values.length;
    if (barWidth <= 0) return;
    final Paint paint = Paint()..color = color;
    for (int index = 0; index < values.length; index++) {
      final double fraction = maxValue == 0 ? 0 : values[index] / maxValue;
      final double barHeight = math.max(4, size.height * fraction);
      final RRect bar = RRect.fromRectAndRadius(
        Rect.fromLTWH(
          index * (barWidth + gap),
          size.height - barHeight,
          barWidth,
          barHeight,
        ),
        Radius.circular(barWidth / 2),
      );
      canvas.drawRRect(bar, paint);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
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
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final List<String> labels = List<String>.filled(
      math.max(1, (days.length / 7).ceil()),
      '',
    );
    int? lastMonth;
    for (int index = 0; index < days.length; index++) {
      final DateTime day = days[index].day;
      if (lastMonth == day.month) continue;
      lastMonth = day.month;
      final int column = index ~/ 7;
      if (column < labels.length) {
        labels[column] = _monthName(localizations, day);
      }
    }
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

  static String _monthName(MaterialLocalizations localizations, DateTime day) {
    final String formatted = localizations.formatMonthYear(day);
    return formatted.replaceFirst(RegExp(r'\s+\d{4}$'), '');
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
