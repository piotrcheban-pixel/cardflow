/// Графики экрана статистики (SPEC A6.5, ADR-019 §4).
///
/// Без сторонних библиотек: столбчатые графики и годовая тепловая карта
/// собираются на токенах темы. Значения — данные калькулятора, подписи дат —
/// краткие формы CLDR через `intl` (локаль ru).
///
/// Аудит v4 (V13/V14): оба столбчатых графика экрана («Недельный прогресс» и
/// «Прогноз нагрузки») собирает **один** компонент [StatisticsBarChart] —
/// числа над столбцами, одинаковая ширина столбцов, общая ось и подписи не
/// мельче `AppTypography.caption` (13). Нулевой день — видимый нулевой столбик
/// с подписью «0», а не волосок. Ячейка тепловой карты — 16 px с шагом 20,
/// подписи месяцев — 13 px, единый формат «янв фев мар …».
library;

import 'dart:math' as math;

import 'package:intl/intl.dart' show DateFormat;
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Ширина столбца столбчатого графика при любой ширине колонки.
///
/// Находка D5 аудита: столбец растягивался на всю ячейку (≈153 px), и максимум
/// выглядел «кляксой». Ширина ограничена 12–20 px — на экране 390 px и на
/// широком мониторе столбик остаётся узким. С V13 функцию используют оба
/// графика, поэтому столбцы недели и прогноза одной ширины.
@visibleForTesting
double statisticsWeekBarWidth(double columnWidth) =>
    (columnWidth * 0.45).clamp(12.0, 20.0);

/// Высота графика вместе с числами и подписями дней (V13).
///
/// F32: на 2K/4K график выше (120 → 174), поэтому столбцы читаются так же,
/// как на FullHD.
const double _statisticsChartHeight = 120;

/// Максимальная ширина графика: на широком экране 7 столбцов не растягиваются
/// на всю карточку, а остаются компактной группой.
const double _maxChartWidth = 480;

/// Толщина общей оси столбчатых графиков.
const double _axisHeight = AppSizes.borderWidth;

/// Высота нулевого столбца (V13).
///
/// Пустой день — видимый скруглённый столбик высотой 6 px с подписью «0», а не
/// двухпиксельный волосок базовой линии.
const double _zeroColumnHeight = 6;

/// Минимальная высота ненулевого столбца: одно повторение должно быть заметно
/// выше нулевого столбика.
const double _minBarHeight = 10;

/// Сторона ячейки тепловой карты (V14): было 5–11 px, карта не читалась.
const double _heatmapCell = 16;

/// Шаг сетки тепловой карты: ячейка + зазор 4 px (V14: 18–20 px).
const double _heatmapStep = 20;

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

/// Единый столбчатый график статистики (аудит v4, V13).
///
/// Один визуальный язык для «Недельного прогресса» и «Прогноза нагрузки»:
///
/// * число стоит над своим столбцом (нулевой день — «0»);
/// * столбец 12–20 px (`statisticsWeekBarWidth`), нулевой — видимый столбик;
/// * одна общая ось `outlineVariant` под всеми столбцами;
/// * подписи — `AppTypography.caption` (13 px и крупнее с адаптивной шкалой).
class StatisticsBarChart extends StatelessWidget {
  /// Создаёт столбчатый график.
  const StatisticsBarChart({
    required this.values,
    required this.labels,
    required this.semantics,
    required this.keyPrefix,
    this.emphasisIndex,
    this.height = _statisticsChartHeight,
    this.semanticsLabel,
    super.key,
  });

  /// Значения столбцов (ноль допустим), старые → новые.
  final List<int> values;

  /// Подписи под столбцами (`labels[i]` для `values[i]`).
  final List<String> labels;

  /// Семантика каждого столбца (`statistics[i]` для `values[i]`).
  final List<String> semantics;

  /// Префикс ключей (`<prefix>-value-i`, `-bar-i`, `-baseline-i`, `-label-i`).
  final String keyPrefix;

  /// Столбец «сегодня» (акцентный).
  final int? emphasisIndex;

  /// Высота всего графика вместе с числами и подписями.
  final double height;

  /// Семантика графика для screen-reader.
  final String? semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double factor = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.45);
    final int maxValue = values.isEmpty
        ? 0
        : values.reduce((int a, int b) => a > b ? a : b);
    final TextStyle valueStyle = AppTypography.caption(context).copyWith(
      fontFeatures: AppTypography.tabularFigures,
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );
    final Widget chart = Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: _maxChartWidth * factor),
        child: SizedBox(
          height: height * factor,
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final int columns = math.max(1, values.length);
              final double columnWidth = constraints.maxWidth / columns;
              final double barWidth = statisticsWeekBarWidth(columnWidth);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Expanded(
                    child: Stack(
                      children: <Widget>[
                        // F32: тихая сетка 25/50/75 % — столбцы читаются по
                        // общей шкале, а не «висят» в пустом поле.
                        for (final double level in <double>[0.25, 0.5, 0.75])
                          Positioned(
                            left: 0,
                            right: 0,
                            bottom: constraints.maxHeight * level,
                            child: SizedBox(
                              height: AppSizes.borderWidth,
                              child: ColoredBox(
                                color: scheme.outlineVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                          ),
                        // Одна общая ось под всеми столбцами (V13).
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: SizedBox(
                            key: ValueKey<String>('$keyPrefix-axis'),
                            height: _axisHeight,
                            child: ColoredBox(color: scheme.outline),
                          ),
                        ),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            for (int index = 0; index < values.length; index++)
                              Expanded(
                                child: _BarColumn(
                                  index: index,
                                  value: values[index],
                                  maxValue: maxValue,
                                  barWidth: barWidth,
                                  barColor: index == emphasisIndex
                                      ? scheme.primary
                                      : scheme.primaryContainer,
                                  zeroColor: scheme.outlineVariant,
                                  valueStyle: valueStyle,
                                  semantics: index < semantics.length
                                      ? semantics[index]
                                      : '',
                                  keyPrefix: keyPrefix,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Row(
                    children: <Widget>[
                      for (int index = 0; index < values.length; index++)
                        Expanded(
                          child: _ChartLabel(
                            text: index < labels.length ? labels[index] : '',
                            emphasized: index == emphasisIndex,
                            textKey: ValueKey<String>(
                              '$keyPrefix-label-$index',
                            ),
                          ),
                        ),
                    ],
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

/// Столбец графика: число над столбцом, нулевой столбик и сам столбец.
class _BarColumn extends StatelessWidget {
  const _BarColumn({
    required this.index,
    required this.value,
    required this.maxValue,
    required this.barWidth,
    required this.barColor,
    required this.zeroColor,
    required this.valueStyle,
    required this.semantics,
    required this.keyPrefix,
  });

  final int index;
  final int value;
  final int maxValue;
  final double barWidth;
  final Color barColor;
  final Color zeroColor;
  final TextStyle valueStyle;
  final String semantics;
  final String keyPrefix;

  /// Резерв под число над столбцом: строка кегля + зазор + пиксель запаса
  /// (округление строки в текстовом движке).
  static double _valueBandHeight(TextStyle style) =>
      (style.fontSize ?? 13) * (style.height ?? 1.35) + 1 + AppSpacing.xxs;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: semantics,
      child: ExcludeSemantics(
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final double area = math.max(0, constraints.maxHeight);
            final double maxBar = math.max(
              0,
              area - _valueBandHeight(valueStyle),
            );
            final double fraction = maxValue <= 0 ? 0 : value / maxValue;
            // Ноль — видимый столбик фиксированной высоты; ненулевое значение
            // не ниже _minBarHeight и не выше доступной площади.
            final double barHeight = value <= 0
                ? _zeroColumnHeight
                : math.max(math.min(_minBarHeight, maxBar), maxBar * fraction);
            // Stack, а не Column: число и столбец выровнены по низу без
            // RenderFlex-переполнения на любой шкале текста (V13).
            return Stack(
              clipBehavior: Clip.none,
              children: <Widget>[
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Center(
                    child: SizedBox(
                      key: ValueKey<String>('$keyPrefix-baseline-$index'),
                      width: barWidth,
                      height: _zeroColumnHeight,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: zeroColor,
                          borderRadius: BorderRadius.circular(AppRadii.xs / 2),
                        ),
                      ),
                    ),
                  ),
                ),
                if (value > 0)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Center(
                      child: SizedBox(
                        key: ValueKey<String>('$keyPrefix-bar-$index'),
                        width: barWidth,
                        height: barHeight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadii.xs / 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom:
                      (value > 0 ? barHeight : _zeroColumnHeight) +
                      AppSpacing.xxs,
                  child: Text(
                    value.toString(),
                    key: ValueKey<String>('$keyPrefix-value-$index'),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    softWrap: false,
                    style: valueStyle,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// Подпись столбца под осью.
///
/// Кегль — `AppTypography.caption` (13 px, с адаптивной шкалой); трекинг
/// обнулён, чтобы длинное «Сегодня» умещалось в узкую ячейку телефона и
/// соседние подписи не слипались. `FittedBox(scaleDown)` — только страховка
/// при очень крупном системном масштабе текста: подпись ужимается вместо
/// наложения на соседнюю.
class _ChartLabel extends StatelessWidget {
  const _ChartLabel({
    required this.text,
    required this.emphasized,
    required this.textKey,
  });

  final String text;
  final bool emphasized;
  final Key textKey;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final TextStyle style =
        AppTypography.caption(
          context,
          color: emphasized ? scheme.primary : scheme.onSurfaceVariant,
        ).copyWith(
          fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
          letterSpacing: 0,
        );
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        key: textKey,
        textAlign: TextAlign.center,
        maxLines: 1,
        softWrap: false,
        style: style,
      ),
    );
  }
}

/// Недельный бар-чарт: 7 столбцов с числами и подписями дней (D5, V13).
///
/// Тонкая обёртка над общим [StatisticsBarChart]: компонент один на оба графика
/// экрана, а имя сохранено — на него опираются виджет-тесты и экран.
class StatisticsWaveform extends StatelessWidget {
  /// Создаёт недельный график.
  const StatisticsWaveform({
    required this.values,
    required this.labels,
    this.semanticsLabel,
    this.height = _statisticsChartHeight,
    super.key,
  });

  /// Значения столбцов (ноль допустим), старые → сегодня.
  final List<int> values;

  /// Подписи дней под столбцами (`labels[i]` для `values[i]`).
  final List<String> labels;

  /// Семантика графика для screen-reader.
  final String? semanticsLabel;

  /// Высота всего графика вместе с числами и подписями дней.
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    return StatisticsBarChart(
      values: values,
      labels: labels,
      semantics: <String>[
        for (int index = 0; index < values.length; index++)
          l10n.statisticsChartBarSemantics(
            index < labels.length ? labels[index] : '',
            values[index],
          ),
      ],
      keyPrefix: 'statistics-week',
      emphasisIndex: values.isEmpty ? null : values.length - 1,
      height: height,
      semanticsLabel: semanticsLabel,
    );
  }
}

/// Годовая тепловая карта повторений (A6.5, V14).
///
/// Ячейка 16 px, шаг 20 px, подписи месяцев — `AppTypography.caption` (13 px).
/// Если карточка уже сетки года (узкий экран), карта прокручивается по
/// горизонтали и открывается на сегодняшней неделе (`reverse`), а не сжимается
/// до нечитаемых 5–11 px.
class StatisticsHeatmap extends StatefulWidget {
  /// Создаёт карту.
  const StatisticsHeatmap({required this.days, super.key});

  /// 365 дней, старые → сегодня.
  final List<DayCount> days;

  /// Подписи месяцев по колонкам карты (см. реализацию в состоянии).
  @visibleForTesting
  static List<String> heatmapMonthLabels(
    List<DayCount> days,
    String Function(DateTime day) format,
  ) => _StatisticsHeatmapState.heatmapMonthLabels(days, format);

  @override
  State<StatisticsHeatmap> createState() => _StatisticsHeatmapState();
}

class _StatisticsHeatmapState extends State<StatisticsHeatmap> {
  final ScrollController _scroll = ScrollController();
  bool _canScroll = false;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<DayCount> days = widget.days;
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final List<String> labels = heatmapMonthLabels(days, _monthName);
    final TextStyle labelStyle = AppTypography.caption(
      context,
      color: scheme.onSurfaceVariant,
    );
    final TextScaler textScaler = MediaQuery.textScalerOf(context);
    final double labelHeight =
        textScaler.scale(labelStyle.fontSize ?? 13) *
        (labelStyle.height ?? 1.35);
    // F31: ячейка растёт вместе с масштабом экрана (16 → 19,8 → 23,2),
    // пустой день контрастнее — карта читается как календарь.
    final double factor = AppAdaptive.factorForContext(context)
        .clamp(1.0, 1.45);
    final double cell = (_heatmapCell * factor).clamp(16.0, 24.0);
    final int columns = math.max(1, (days.length / 7).ceil());
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double available = constraints.maxWidth;
        // Аудит 2.0 (P2-22): при шаге 20 px год не помещался в 960 px, карта
        // прокручивалась и первая подпись месяца выглядела обрезанной. Шаг
        // подстраивается под доступную ширину (не меньше cell + 1,5), поэтому
        // на десктопе карта видна целиком, а на телефоне остаётся прокрутка.
        final double maxStep = cell + (_heatmapStep - _heatmapCell);
        final double fitStep = available.isFinite && available > 0
            ? available / columns
            : maxStep;
        final double step = fitStep.clamp(cell + 1.5, maxStep);
        final double chartWidth = columns * step;
        final double chartHeight = labelHeight + AppSpacing.xxs + 7 * step;
        final Widget sized = SizedBox(
          width: chartWidth,
          height: chartHeight,
          child: CustomPaint(
            key: const ValueKey<String>('statistics-heatmap'),
            size: Size(chartWidth, chartHeight),
            painter: _HeatmapPainter(
              days: days,
              monthLabels: labels,
              cell: cell,
              step: step,
              top: labelHeight + AppSpacing.xxs,
              emptyColor: scheme.outlineVariant,
              color: scheme.primary,
              labelStyle: labelStyle,
              textScaler: textScaler,
            ),
          ),
        );
        if (!available.isFinite || available >= chartWidth) {
          return Center(child: sized);
        }
        // Узкий экран: год не помещается — горизонтальная прокрутка от
        // сегодняшней недели (обратный порядок), вместо сжатия ячеек.
        // Аудит v5 (V5-14): прокрутка имеет видимый индикатор.
        return NotificationListener<ScrollMetricsNotification>(
          onNotification: (ScrollMetricsNotification notification) {
            final bool canScroll = notification.metrics.maxScrollExtent > 0.5;
            if (canScroll != _canScroll) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && canScroll != _canScroll) {
                  setState(() => _canScroll = canScroll);
                }
              });
            }
            return false;
          },
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: _canScroll,
            child: SingleChildScrollView(
              controller: _scroll,
              scrollDirection: Axis.horizontal,
              reverse: true,
              child: sized,
            ),
          ),
        );
      },
    );
  }

  /// Короткое название месяца для подписи колонки карты: «янв», «фев», … (V14).
  ///
  /// Форматирует CLDR (`DateFormat('LLLL', 'ru')` — именительный падеж, без
  /// точек), а затем обрезает до трёх букв. Так формат единый у всех месяцев
  /// («янв фев мар апр май июн июл авг сен окт ноя дек»), а не смесь «дек.» с
  /// «июнь». Русских литералов в виджете нет — строку даёт `intl`.
  static String _monthName(DateTime day) {
    final String full = DateFormat('LLLL', 'ru').format(day).trim();
    if (full.length <= 3) return full;
    return full.substring(0, 3);
  }

  /// Подписи месяцев по колонкам карты: каждый чётный месяц (6 подписей).
  ///
  /// Колонка карты — одна неделя; подпись каждого месяца (12) шла бы вплотную
  /// друг к другу. Чётные месяцы дают зазор в 8–9 колонок — подписи 13 px не
  /// наезжают друг на друга. Формат подписи единый и без точек (V14).
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
    required this.step,
    required this.top,
    required this.emptyColor,
    required this.color,
    required this.labelStyle,
    required this.textScaler,
  });

  final List<DayCount> days;
  final List<String> monthLabels;
  final double cell;
  final double step;
  final double top;
  final Color emptyColor;
  final Color color;
  final TextStyle labelStyle;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    if (days.isEmpty) return;
    final int maxCount = days
        .map((DayCount day) => day.count)
        .reduce((int a, int b) => a > b ? a : b);
    final double radius = AppRadii.xs / 2;
    final Paint paint = Paint();
    for (int index = 0; index < days.length; index++) {
      final int column = index ~/ 7;
      final int row = index % 7;
      final int count = days[index].count;
      paint.color = count == 0
          ? emptyColor
          : color.withValues(alpha: _heatmapAlpha(count, maxCount));
      final RRect cellRect = RRect.fromRectAndRadius(
        Rect.fromLTWH(column * step, top + row * step, cell, cell),
        Radius.circular(radius),
      );
      canvas.drawRRect(cellRect, paint);
    }
    for (int column = 0; column < monthLabels.length; column++) {
      final String label = monthLabels[column];
      if (label.isEmpty) continue;
      final TextPainter painter = TextPainter(
        text: TextSpan(text: label, style: labelStyle),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      painter.paint(canvas, Offset(column * step, 0));
      painter.dispose();
    }
  }

  /// Прозрачность ячейки по числу повторений: 0,25 — минимум, 1,0 — максимум.
  static double _heatmapAlpha(int count, int maxCount) =>
      maxCount <= 0 ? 1 : 0.25 + 0.75 * (count / maxCount);

  @override
  bool shouldRepaint(_HeatmapPainter oldDelegate) =>
      oldDelegate.days != days ||
      oldDelegate.monthLabels != monthLabels ||
      oldDelegate.cell != cell ||
      oldDelegate.step != step ||
      oldDelegate.top != top ||
      oldDelegate.emptyColor != emptyColor ||
      oldDelegate.color != color ||
      oldDelegate.labelStyle != labelStyle ||
      oldDelegate.textScaler != textScaler;
}
