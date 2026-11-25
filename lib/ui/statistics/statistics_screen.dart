/// Экран «Статистика» (SPEC A6.5, ADR-019 §4, ADR-038).
///
/// Блоки: KPI (серия, удержание, повторения за год, активные дни), годовая
/// карта повторений, удержание за 30 дней, слабые темы с переходом в
/// конструктор по тегу и прогноз нагрузки на 7 дней. Все значения — из
/// `StatisticsSnapshot` и настроек пользователя; сырые ошибки пользователю не
/// показываются (только ARB).
///
/// Находки D5–D7 аудита: недельный график живёт ровно в одном месте (карточка
/// «Недельный прогресс»), удержание показывается только при выборке не меньше
/// [_retentionMinSample] повторений за 30 дней, а прогноз подписывает дни
/// полными сокращениями и заменяет ряд нулей пустым сообщением.
///
/// Аудит v4 (V13–V15): оба графика экрана собраны одним компонентом
/// (`StatisticsBarChart`), тепловая карта читается (ячейка 16 px, подписи
/// месяцев 13 px), а слабая тема — одна кликабельная строка без отдельной
/// красной кнопки: процент обычным текстом, шкала акцентом, красный — только
/// при критичном удержании.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' show NumberFormat;
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_layout.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/statistics/statistics_charts.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Экран статистики обучения.
class StatisticsScreen extends ConsumerWidget {
  /// Создаёт экран.
  const StatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<StatisticsSnapshot> snapshot = ref.watch(
      statisticsProvider,
    );
    final AppSettings settings = ref.watch(effectiveAppSettingsProvider);
    return Scaffold(
      body: AppPageScaffold(
        header: AppPageHeader(
          title: l10n.statisticsTitle,
          // Аудит 2.0 (P3-11): служебный надзаголовок «Аналитический центр»
          // дублировал H1 — убран, как и «Нейросетевой модуль» в генерации.
          subtitle: Text(l10n.statisticsSubtitle),
        ),
        slivers: <Widget>[
          snapshot.when(
            loading: () => const _StatisticsLoading(),
            error: (Object error, StackTrace stackTrace) => AppErrorState(
              message: l10n.statisticsErrorTitle,
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(statisticsProvider),
            ),
            data: (StatisticsSnapshot statistics) => statistics.isEmpty
                ? SizedBox(
                    width: double.infinity,
                    child: AppEmptyState(
                      hero: true,
                      icon: Icons.insights_outlined,
                      title: l10n.statisticsEmptyTitle,
                      message: l10n.statisticsEmptyMessage,
                    ),
                  )
                : _StatisticsContent(
                    statistics: statistics,
                    settings: settings,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Минимальная выборка удержания: столько повторений за 30 дней (D6).
///
/// До порога процент статистически бессмысленен («100 %» по одному ответу),
/// поэтому показывается размер выборки, а не доля.
const int _retentionMinSample = 20;

/// Порог «критичного» удержания темы (V15): ниже 40 % тема подсвечивается
/// красным, остальные — нейтральным акцентом, а не тревогой в каждой строке.
const double _criticalTopicRetention = 0.4;

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.statistics, required this.settings});

  final StatisticsSnapshot statistics;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final NumberFormat number = NumberFormat.decimalPattern('ru');
    final List<int> weekCounts = <int>[
      for (final DayCount day in statistics.week) day.count,
    ];
    final List<String> weekLabels = <String>[
      for (final DayCount day in statistics.week)
        statisticsWeekdayLabel(day.day),
    ];
    final int weekTotal = weekCounts.fold<int>(0, (int a, int b) => a + b);
    final int activeDays = statistics.heatmap
        .where((DayCount day) => day.count > 0)
        .length;
    final int streak = _streakDays(statistics.heatmap);
    final double? retention = statistics.retention30;
    final int retentionSample = statistics.reviews30;
    final bool retentionMeasurable = retentionSample >= _retentionMinSample;
    final int retentionPercent = retention == null
        ? 0
        : (retention * 100).round();
    final int goalPercent = (settings.desiredRetention * 100).round();
    final int heatmapPercent = statistics.heatmap.isEmpty
        ? 0
        : ((activeDays / statistics.heatmap.length) * 100).round();
    final int forecastTotal = statistics.forecast.fold<int>(
      0,
      (int sum, ForecastDay day) => sum + day.due,
    );
    // F32: графики выше на 2K/4K — та же шкала, что у остальных размеров.
    final double chartHeight =
        120 * AppAdaptive.factorForContext(context).clamp(1.0, 1.45);

    // KPI (V13, KPI): одна форма у всех плиток — число + единица (% только у
    // удержания), пояснение не повторяет ни подпись, ни число. Колонок 2 на
    // узком экране и 4 на широком: плитки не вырождаются в одну колонку.
    final Widget kpi = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= AppSizes.sidebarBreakpoint
            ? 4
            : 2;
        final double gap = AppSpacing.md;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-streak'),
                label: l10n.statisticsKpiStreak,
                value: number.format(streak),
                // Аудит v4: у KPI есть единица измерения, а не «голое» число.
                unit: l10n.statisticsDaysUnit(streak),
                icon: Icons.local_fire_department_outlined,
                iconColor: scheme.tertiary,
              ),
            ),
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-retention'),
                label: l10n.statisticsKpiRetention,
                // D6: без минимальной выборки процент не показываем — «100 %»
                // по одному повторению выглядел уверенным KPI.
                value: retentionMeasurable
                    ? number.format(retentionPercent)
                    : l10n.statisticsRetentionNoData,
                unit: retentionMeasurable ? '%' : null,
                icon: Icons.verified_outlined,
                iconColor: scheme.secondary,
                // V13 (KPI): пояснение «на основе N повторений» дублировало
                // текст панели удержания — оно остаётся только там. У плитки
                // порога выборки подсказка своя (D6).
                helper: retentionMeasurable
                    ? null
                    : Text(l10n.statisticsRetentionThreshold),
              ),
            ),
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-reviews'),
                label: l10n.statisticsKpiReviews,
                value: number.format(statistics.totalReviewsYear),
                icon: Icons.repeat,
                iconColor: scheme.primary,
              ),
            ),
            // V13: пояснение «8 из 365» дублировало значение плитки; сводка
            // «активных дней из 365» остаётся в подзаголовке карты повторений.
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-active-days'),
                label: l10n.statisticsKpiActiveDays,
                value: number.format(activeDays),
                unit: l10n.statisticsDaysUnit(activeDays),
                icon: Icons.calendar_month_outlined,
                iconColor: scheme.primary,
              ),
            ),
          ],
        );
      },
    );

    final Widget heatmap = AppSectionCard(
      title: l10n.statisticsHeatmapTitle,
      subtitle: l10n.statisticsHeatmapSummary(
        activeDays,
        statistics.heatmap.length,
      ),
      icon: Icons.calendar_month_outlined,
      // Аудит 2.0 (P3-12): «2 %» без пояснения читалось как ошибка —
      // теперь подписано «2 % года».
      headerTrailing: AppStatusChip(
        label: l10n.statisticsCalendarYearShare(heatmapPercent),
        tone: AppStatusTone.neutral,
        dense: true,
      ),
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Semantics(
            label: l10n.statisticsChartSemantics(statistics.totalReviewsYear),
            image: true,
            child: StatisticsHeatmap(days: statistics.heatmap),
          ),
          const SizedBox(height: AppSpacing.sm),
          // V14: легенда — те же ступени прозрачности, что в painter (0,25–1,0),
          // подписи 13 px из AppTypography, а не локальный кегль.
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: <Widget>[
              Text(
                l10n.statisticsLegendLess,
                style: AppTypography.caption(
                  context,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  for (final double alpha in <double>[0.25, 0.5, 0.75, 1.0])
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.xxs),
                      child: Container(
                        width: AppSpacing.sm,
                        height: AppSpacing.sm,
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: alpha),
                          borderRadius: BorderRadius.circular(AppRadii.xs / 2),
                        ),
                      ),
                    ),
                ],
              ),
              Text(
                l10n.statisticsLegendMore,
                style: AppTypography.caption(
                  context,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final Widget retentionPanel = AppSectionCard(
      key: const ValueKey<String>('statistics-retention-panel'),
      title: l10n.statisticsRetentionTitle,
      subtitle: l10n.statisticsRetentionWindow,
      icon: Icons.show_chart,
      accentColor: scheme.secondary,
      // D6: цель и зелёный чип — только когда выборки хватает для процента.
      trailing: retentionMeasurable
          ? AppStatusChip(
              label: l10n.statisticsGoal(goalPercent),
              tone: AppStatusTone.success,
            )
          : null,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            !retentionMeasurable
                ? retentionSample == 0
                      ? l10n.statisticsRetentionNoData
                      : l10n.statisticsRetentionLowSample(retentionSample)
                : l10n.statisticsRetentionValue(retentionPercent),
            key: const ValueKey<String>('statistics-retention'),
            style: retentionMeasurable
                ? AppTypography.kpiLarge(context)
                      .copyWith(color: scheme.secondary)
                : theme.textTheme.titleMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (retentionMeasurable) ...<Widget>[
            Text(
              l10n.statisticsRetentionBasedOn(retentionSample),
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            AppProgressBar(
              key: const ValueKey<String>('statistics-retention-progress'),
              value: retention == null
                  ? 0
                  : (retention / settings.desiredRetention).clamp(0.0, 1.0),
              color: scheme.secondary,
            ),
          ] else
            Text(
              l10n.statisticsRetentionThreshold,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    // V13: тот же компонент, что и у недели, плюс итог в чипе заголовка — у
    // прогноза появились числа и общая ось, а не «график без масштаба».
    final Widget forecastPanel = AppSectionCard(
      title: l10n.statisticsForecastTitle,
      subtitle: l10n.statisticsForecastSubtitle,
      icon: Icons.event_available_outlined,
      headerTrailing: forecastTotal > 0
          ? AppStatusChip(
              label: l10n.statisticsForecastCount(forecastTotal),
              tone: AppStatusTone.neutral,
            )
          : null,
      // V13: графику нужна вся доступная ширина карточки — на 390 px столбцы
      // становятся 48–49 px, и 13-пиксельные подписи «Сегодня»/«Завтра» не
      // наезжают друг на друга. Заголовок карточки сохраняет свой отступ.
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      child: _ForecastChart(forecast: statistics.forecast, height: chartHeight),
    );

    final Widget weakTopics = AppSectionCard(
      title: l10n.statisticsWeakTopicsTitle,
      subtitle: l10n.statisticsWeakTopicsSubtitle,
      icon: Icons.warning_amber_outlined,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: _WeakTopicsSection(topics: statistics.weakTopics),
    );

    final Widget weekPanel = AppSectionCard(
      key: const ValueKey<String>('statistics-week-panel'),
      title: l10n.statisticsWeekTitle,
      subtitle: l10n.statisticsWeekTotal(weekTotal),
      icon: Icons.bar_chart,
      // Та же ширина контента, что у прогноза: два графика стоят одним
      // визуальным языком и на узком экране получают максимум места.
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.md,
        AppSpacing.xs,
        AppSpacing.md,
      ),
      // D5: недельный график — ровно в одном месте (карточка недели);
      // пустая неделя объясняется текстом, а не рядом нулей.
      child: weekTotal == 0
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Text(
                l10n.statisticsWeekEmpty,
                key: const ValueKey<String>('statistics-week-empty'),
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          : StatisticsWaveform(
              key: const ValueKey<String>('statistics-week'),
              values: weekCounts,
              labels: weekLabels,
              semanticsLabel: l10n.statisticsWeekSemantics(weekTotal),
              height: chartHeight,
            ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        // Аудит 2.0: при пороге 1024 два графика ставились друг под другом даже
        // на 1280-окне (контент ≈ 995 px) — карточки шли во всю ширину, а сами
        // диаграммы занимали 480 px по центру. Порог 900 даёт два столбца
        // карточек и диаграммы во всю их ширину.
        final bool wide = constraints.maxWidth >= 900;
        // V13/V14: карта повторений занимает всю ширину — 53 недели по 20 px
        // помещаются только так; два графика стоят рядом и читаются одним
        // языком, а удержание и слабые темы образуют вторую пару.
        final Widget charts = wide
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 3, child: forecastPanel),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 2, child: weekPanel),
                  ],
                ),
              )
            : Column(
                children: <Widget>[
                  forecastPanel,
                  const SizedBox(height: AppSpacing.md),
                  weekPanel,
                ],
              );
        final Widget details = wide
            ? IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Expanded(flex: 2, child: retentionPanel),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(flex: 3, child: weakTopics),
                  ],
                ),
              )
            : Column(
                children: <Widget>[
                  retentionPanel,
                  const SizedBox(height: AppSpacing.md),
                  weakTopics,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            kpi,
            const SizedBox(height: AppSpacing.md),
            heatmap,
            const SizedBox(height: AppSpacing.md),
            charts,
            const SizedBox(height: AppSpacing.md),
            details,
          ],
        );
      },
    );
  }

  /// Текущая серия: подряд идущие дни с повторениями до сегодня включительно.
  static int _streakDays(List<DayCount> heatmap) {
    int streak = 0;
    for (int index = heatmap.length - 1; index >= 0; index--) {
      if (heatmap[index].count <= 0) break;
      streak++;
    }
    return streak;
  }
}

/// Скелетон статистики: панели графиков вместо голого спиннера (F22).
class _StatisticsLoading extends StatelessWidget {
  const _StatisticsLoading();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final int columns = constraints.maxWidth >= 1024 ? 4 : 2;
            final double gap = AppSpacing.md;
            final double width =
                (constraints.maxWidth - gap * (columns - 1)) / columns;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: <Widget>[
                for (int index = 0; index < 4; index++)
                  SizedBox(width: width, child: const AppSkeleton(height: 104)),
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.md),
        const AppSkeleton(height: 240),
        const SizedBox(height: AppSpacing.md),
        LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            if (constraints.maxWidth < 1024) {
              return const Column(
                children: <Widget>[
                  AppSkeleton(height: 180),
                  SizedBox(height: AppSpacing.md),
                  AppSkeleton(height: 180),
                ],
              );
            }
            return const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(flex: 3, child: AppSkeleton(height: 180)),
                SizedBox(width: AppSpacing.md),
                Expanded(flex: 2, child: AppSkeleton(height: 180)),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Слабые темы: по одной кликабельной строке на тему (V15).
class _WeakTopicsSection extends StatelessWidget {
  const _WeakTopicsSection({required this.topics});

  final List<WeakTopic> topics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    if (topics.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          l10n.statisticsWeakTopicsEmpty,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    return Column(
      children: <Widget>[
        for (final WeakTopic topic in topics)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xs),
            child: _WeakTopicRow(topic: topic),
          ),
      ],
    );
  }
}

/// Строка слабой темы (V15).
///
/// Один вход на строку: вся строка — `InkWell` с hover/focus, отдельной
/// `FilledButton` нет. Процент — обычный текст, шкала — акцент `primary`,
/// красный (`error`) только при действительно критичном удержании
/// ([_criticalTopicRetention]).
class _WeakTopicRow extends StatelessWidget {
  const _WeakTopicRow({required this.topic});

  final WeakTopic topic;

  void _openConstructor(BuildContext context) {
    context.push(
      '${AppRoutes.constructorPath}'
      '?tag=${Uri.encodeQueryComponent(topic.tag)}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final double errorRate = topic.errorRate.clamp(0.0, 1.0);
    final bool critical = 1 - errorRate < _criticalTopicRetention;
    final Color percentColor = critical ? scheme.error : scheme.onSurface;
    return Material(
      color: scheme.surfaceContainerLow,
      borderRadius: AppRadii.inputRadius,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Ключ строки сохранён для тестов навигации (V15: кнопки больше нет,
        // но клик по строке ведёт в конструктор с тем же тегом).
        key: ValueKey<String>('weak-topic-train-${topic.tag}'),
        onTap: () => _openConstructor(context),
        borderRadius: AppRadii.inputRadius,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      topic.tag,
                      key: ValueKey<String>('weak-topic-${topic.tag}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: AppSpacing.xxs / 2),
                    Text(
                      l10n.statisticsWeakTopicStats(
                        topic.errors,
                        topic.reviews,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.caption(
                        context,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    AppProgressBar(
                      value: errorRate,
                      color: critical ? scheme.error : scheme.primary,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(
                    l10n.statisticsRetentionValue(
                      (topic.errorRate * 100).round(),
                    ),
                    style: AppTypography.numeric(context, color: percentColor),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    l10n.statisticsWeakTopicTrain,
                    style: AppTypography.caption(
                      context,
                      color: scheme.primary,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              const SizedBox(width: AppSpacing.xxs),
              Icon(
                Icons.chevron_right,
                size: AppSizes.icon,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Прогноз нагрузки на 7 дней (реальные `due` из планировщика).
///
/// V13: тот же `StatisticsBarChart`, что и у недельного прогресса, — числа над
/// столбцами, общая ось, одинаковая ширина столбцов; нулевой день — нулевой
/// столбик с подписью «0».
class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.forecast, required this.height});

  final List<ForecastDay> forecast;

  /// Высота графика вместе с числами (масштабируется на 2K/4K).
  final double height;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool empty = forecast.every((ForecastDay day) => day.due == 0);
    if (empty) {
      // D7: ряд нулей не несёт информации — показываем пустое сообщение.
      return Padding(
        key: const ValueKey<String>('statistics-forecast'),
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
        child: Text(
          l10n.statisticsForecastEmpty,
          key: const ValueKey<String>('statistics-forecast-empty'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: scheme.onSurfaceVariant,
          ),
        ),
      );
    }
    final List<String> labels = <String>[
      for (int index = 0; index < forecast.length; index++)
        _label(l10n, forecast[index].day, index),
    ];
    return StatisticsBarChart(
      key: const ValueKey<String>('statistics-forecast'),
      values: <int>[for (final ForecastDay day in forecast) day.due],
      labels: labels,
      semantics: <String>[
        for (int index = 0; index < forecast.length; index++)
          l10n.statisticsForecastSemantics(labels[index], forecast[index].due),
      ],
      // Сегодня — акцентный столбец, как у недели крайний правый день.
      keyPrefix: 'statistics-forecast',
      emphasisIndex: 0,
      height: height,
    );
  }

  static String _label(AppLocalizations l10n, DateTime day, int index) {
    if (index == 0) return l10n.statisticsForecastToday;
    if (index == 1) return l10n.statisticsForecastTomorrow;
    // D7: краткая форма ru (Пн…Вс); `narrowWeekdays` для ru — одна буква.
    return statisticsWeekdayLabel(day);
  }
}
