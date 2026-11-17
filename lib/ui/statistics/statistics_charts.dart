/// Графики экрана статистики (SPEC A6.5, ADR-019 §4; REDESIGN §9.15).
///
/// Без сторонних библиотек: waveform, годовая тепловая карта и прогноз
/// рисуются `CustomPainter` на токенах `NcTheme`. Значения — данные
/// калькулятора, подписи дат — `MaterialLocalizations` (локаль ru).
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/motion.dart';

/// Waveform-индикатор на токенах темы (удержание/недельный прогресс).
///
/// Столбики-капсулы с градиентом `aurumDeep→aurum`; последний столбик ярче и
/// с точкой-glow. Появление — рост от нуля (каскад, §9.15).
class StatisticsWaveform extends StatelessWidget {
  /// Создаёт waveform.
  const StatisticsWaveform({
    required this.values,
    this.semanticsLabel,
    this.height = 56,
    this.empty = false,
    super.key,
  });

  /// Значения столбцов (ноль допустим).
  final List<int> values;

  /// Семантика для screen-reader.
  final String? semanticsLabel;

  /// Высота графика.
  final double height;

  /// Нет данных — пунктирная линия вместо столбиков.
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Widget canvas = TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: MediaQuery.of(context).disableAnimations
          ? Duration.zero
          : AppMotion.base,
      curve: AppMotion.baseCurve,
      builder: (BuildContext context, double progress, Widget? _) =>
          CustomPaint(
            size: Size(double.infinity, height),
            painter: _WaveformPainter(
              values: values,
              progress: progress,
              start: theme.colors.aurumDeep,
              end: theme.colors.aurumBright,
              emptyColor: theme.colors.hairlineStrong,
              empty: empty,
            ),
          ),
    );
    if (semanticsLabel == null) return canvas;
    return Semantics(label: semanticsLabel, image: true, child: canvas);
  }
}

class _WaveformPainter extends CustomPainter {
  _WaveformPainter({
    required this.values,
    required this.progress,
    required this.start,
    required this.end,
    required this.emptyColor,
    required this.empty,
  });

  final List<int> values;
  final double progress;
  final Color start;
  final Color end;
  final Color emptyColor;
  final bool empty;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    if (empty || values.isEmpty) {
      final Paint dashed = Paint()
        ..color = emptyColor
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final double y = size.height / 2;
      for (double x = 0; x < size.width; x += 10) {
        canvas.drawLine(
          Offset(x, y),
          Offset(math.min(x + 5, size.width), y),
          dashed,
        );
      }
      return;
    }
    final int maxValue = values.reduce(math.max);
    final double gap = 4;
    final double barWidth =
        (size.width - gap * (values.length - 1)) / values.length;
    if (barWidth <= 0) return;
    final Paint paint = Paint();
    for (int index = 0; index < values.length; index++) {
      final bool last = index == values.length - 1;
      final double fraction = maxValue == 0 ? 0 : values[index] / maxValue;
      final double barHeight = math.max(4, size.height * fraction) * progress;
      paint.shader =
          LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: <Color>[start, last ? end : end.withValues(alpha: 0.75)],
          ).createShader(
            Rect.fromLTWH(
              index * (barWidth + gap),
              size.height - barHeight,
              barWidth,
              barHeight,
            ),
          );
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
      if (last && barHeight > 0) {
        final Offset dot = Offset(
          index * (barWidth + gap) + barWidth / 2,
          size.height - barHeight - 5,
        );
        canvas.drawCircle(
          dot,
          4,
          Paint()
            ..color = end.withValues(alpha: 0.35)
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawCircle(dot, 2.4, Paint()..color = end);
      }
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.progress != progress ||
      oldDelegate.start != start ||
      oldDelegate.end != end ||
      oldDelegate.empty != empty;
}

/// Годовая тепловая карта повторений (A6.5): ячейки 10–12 px, шкала `heat0–4`.
///
/// На телефоне карта прокручивается горизонтально и автоматически
/// прокручена к сегодняшнему дню.
class StatisticsHeatmap extends StatefulWidget {
  /// Создаёт карту.
  const StatisticsHeatmap({required this.days, super.key});

  /// 365 дней, старые → сегодня.
  final List<DayCount> days;

  @override
  State<StatisticsHeatmap> createState() => _StatisticsHeatmapState();

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

class _StatisticsHeatmapState extends State<StatisticsHeatmap> {
  final ScrollController _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _jumpToToday());
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _jumpToToday() {
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpTo(_controller.position.maxScrollExtent);
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final List<String> labels = StatisticsHeatmap.heatmapMonthLabels(
      widget.days,
      (DateTime day) => _monthName(localizations, day),
    );
    const double cell = 10;
    const double step = 13;
    final int columns = math.max(1, (widget.days.length / 7).ceil());
    final double width = columns * step;
    final double height = 7 * step + 16;
    return SingleChildScrollView(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      child: CustomPaint(
        key: const ValueKey<String>('statistics-heatmap'),
        size: Size(width, height),
        painter: _HeatmapPainter(
          days: widget.days,
          monthLabels: labels,
          cell: cell,
          step: step,
          heat: theme.colors.heat,
          labelStyle: theme.typography.labelM.copyWith(
            fontSize: 9,
            color: theme.colors.textTertiary,
          ),
        ),
      ),
    );
  }

  static String _monthName(MaterialLocalizations localizations, DateTime day) {
    // Локаль ru: `formatMonthYear` → «январь 2026 г.». Для колонки карты
    // нужна короткая подпись (3 буквы), иначе метки перекрывают друг друга.
    final String formatted = localizations.formatMonthYear(day);
    final String month = formatted.split(' ').first;
    return month.length <= 3 ? month : month.substring(0, 3);
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.days,
    required this.monthLabels,
    required this.cell,
    required this.step,
    required this.heat,
    this.labelStyle,
  });

  final List<DayCount> days;
  final List<String> monthLabels;
  final double cell;
  final double step;
  final List<Color> heat;
  final TextStyle? labelStyle;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final int maxCount = days.map((DayCount day) => day.count).reduce(math.max);
    final Paint paint = Paint();
    const double top = 16;
    for (int index = 0; index < days.length; index++) {
      final int column = index ~/ 7;
      final int row = index % 7;
      final int count = days[index].count;
      final int level = count == 0 || maxCount == 0
          ? 0
          : 1 + ((count / maxCount) * 3).round().clamp(0, 3);
      paint.color = heat[level.clamp(0, heat.length - 1)];
      final RRect cellRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(column * step, top + row * step, cell, cell),
        const Radius.circular(3),
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
      oldDelegate.step != step ||
      oldDelegate.heat != heat;
}
