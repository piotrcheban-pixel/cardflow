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
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
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
          overline: Text(l10n.statisticsOverline.toUpperCase()),
          subtitle: Text(l10n.statisticsSubtitle),
        ),
        slivers: <Widget>[
          snapshot.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.huge),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (Object error, StackTrace stackTrace) => AppErrorState(
              message: l10n.statisticsErrorTitle,
              retryLabel: l10n.retry,
              onRetry: () => ref.invalidate(statisticsProvider),
            ),
            data: (StatisticsSnapshot statistics) => statistics.isEmpty
                ? AppEmptyState(
                    icon: Icons.insights_outlined,
                    title: l10n.statisticsEmptyTitle,
                    message: l10n.statisticsEmptyMessage,
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

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.statistics, required this.settings});

  final StatisticsSnapshot statistics;
  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
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

    final Widget kpi = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final int columns = constraints.maxWidth >= 1024
            ? 4
            : constraints.maxWidth >= 520
            ? 2
            : 1;
        final double gap = AppSpacing.md;
        final double width =
            (constraints.maxWidth - gap * (columns - 1)) / columns;
        final ThemeData theme = Theme.of(context);
        final ColorScheme scheme = theme.colorScheme;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: <Widget>[
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-streak'),
                label: l10n.statisticsKpiStreak,
                value: l10n.statisticsDays(streak),
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
                    ? '$retentionPercent'
                    : l10n.statisticsRetentionNoData,
                unit: retentionMeasurable ? '%' : null,
                icon: Icons.verified_outlined,
                iconColor: scheme.secondary,
                helper: Text(
                  retentionMeasurable
                      ? l10n.statisticsRetentionBasedOn(retentionSample)
                      : l10n.statisticsRetentionThreshold,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: retentionMeasurable
                        ? scheme.secondary
                        : scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-reviews'),
                label: l10n.statisticsKpiReviews,
                value: '${statistics.totalReviewsYear}',
                icon: Icons.repeat,
                iconColor: scheme.primary,
              ),
            ),
            SizedBox(
              width: width,
              child: AppStatTile(
                key: const ValueKey<String>('statistics-kpi-active-days'),
                label: l10n.statisticsKpiActiveDays,
                value: '$activeDays',
                icon: Icons.calendar_month_outlined,
                iconColor: scheme.primary,
                helper: Text(
                  l10n.statisticsActiveDaysValue(
                    activeDays,
                    statistics.heatmap.length,
                  ),
                ),
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
      headerTrailing: AppStatusChip(
        label: '$heatmapPercent%',
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
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: <Widget>[
              Text(
                l10n.statisticsLegendLess,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              for (final double alpha in <double>[0.15, 0.4, 0.7, 1.0])
                Padding(
                  padding: const EdgeInsets.only(right: 3),
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary
                          .withValues(alpha: alpha),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                l10n.statisticsLegendMore,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );

    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
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
              dense: true,
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

    final Widget forecastPanel = AppSectionCard(
      title: l10n.statisticsForecastTitle,
      subtitle: l10n.statisticsForecastSubtitle,
      icon: Icons.event_available_outlined,
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      child: _ForecastChart(forecast: statistics.forecast),
    );

    final Widget weakTopics = AppSectionCard(
      title: l10n.statisticsWeakTopicsTitle,
      subtitle: l10n.statisticsWeakTopicsSubtitle,
      icon: Icons.warning_amber_outlined,
      accentColor: Theme.of(context).colorScheme.tertiary,
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
      contentPadding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
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
              height: 120,
            ),
    );

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= 1024;
        final Widget top = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 2, child: heatmap),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: retentionPanel),
                ],
              )
            : Column(
                children: <Widget>[
                  heatmap,
                  const SizedBox(height: AppSpacing.md),
                  retentionPanel,
                ],
              );
        final Widget middle = wide
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(flex: 3, child: forecastPanel),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(flex: 2, child: weakTopics),
                ],
              )
            : Column(
                children: <Widget>[
                  forecastPanel,
                  const SizedBox(height: AppSpacing.md),
                  weakTopics,
                ],
              );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            kpi,
            const SizedBox(height: AppSpacing.md),
            top,
            const SizedBox(height: AppSpacing.md),
            middle,
            const SizedBox(height: AppSpacing.md),
            weekPanel,
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
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadii.input),
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
                        const SizedBox(height: 2),
                        Text(
                          l10n.statisticsWeakTopicStats(
                            topic.errors,
                            topic.reviews,
                          ),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs + 2),
                        AppProgressBar(
                          value: topic.errorRate,
                          color: scheme.tertiary,
                          height: 4,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    l10n.statisticsRetentionValue(
                      (topic.errorRate * 100).round(),
                    ),
                    style: AppTypography.numeric(
                      context,
                      color: scheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  FilledButton(
                    key: ValueKey<String>('weak-topic-train-${topic.tag}'),
                    onPressed: () => context.push(
                      '${AppRoutes.constructorPath}'
                      '?tag=${Uri.encodeQueryComponent(topic.tag)}',
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                    ),
                    child: Text(l10n.statisticsWeakTopicTrain),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Прогноз нагрузки на 7 дней (реальные `due` из планировщика).
class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.forecast});

  final List<ForecastDay> forecast;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool empty = forecast.every((ForecastDay day) => day.due == 0);
    if (empty) {
      // D7: ряд нулей не несёт информации — показываем пустое сообщение.
      return SizedBox(
        key: const ValueKey<String>('statistics-forecast'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
          child: Text(
            l10n.statisticsForecastEmpty,
            key: const ValueKey<String>('statistics-forecast-empty'),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    final int maxDue = forecast
        .map((ForecastDay day) => day.due)
        .reduce((int a, int b) => a > b ? a : b);
    final List<String> labels = <String>[
      for (int index = 0; index < forecast.length; index++)
        _label(l10n, forecast[index].day, index),
    ];
    return SizedBox(
      key: const ValueKey<String>('statistics-forecast'),
      height: 168,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int index = 0; index < forecast.length; index++)
            Expanded(
              child: _ForecastBar(
                index: index,
                day: forecast[index],
                label: labels[index],
                semantics: l10n.statisticsForecastSemantics(
                  labels[index],
                  forecast[index].due,
                ),
                fraction: maxDue == 0 ? 0 : forecast[index].due / maxDue,
                color: index == 0 ? scheme.primary : scheme.primaryContainer,
              ),
            ),
        ],
      ),
    );
  }

  static String _label(AppLocalizations l10n, DateTime day, int index) {
    if (index == 0) return l10n.statisticsForecastToday;
    if (index == 1) return l10n.statisticsForecastTomorrow;
    // D7: краткая форма ru (Пн…Вс); `narrowWeekdays` для ru — одна буква.
    return statisticsWeekdayLabel(day);
  }
}

class _ForecastBar extends StatelessWidget {
  const _ForecastBar({
    required this.index,
    required this.day,
    required this.label,
    required this.semantics,
    required this.fraction,
    required this.color,
  });

  final int index;
  final ForecastDay day;
  final String label;
  final String semantics;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return Semantics(
      label: semantics,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(
              day.due.toString(),
              style: AppTypography.numeric(context, color: scheme.onSurface),
            ),
            const SizedBox(height: AppSpacing.xxs),
            Expanded(
              child: Stack(
                alignment: Alignment.bottomCenter,
                children: <Widget>[
                  // D7: тонкая базовая линия видна и у нулевых дней; столбик
                  // рисуется только для ненулевой нагрузки.
                  SizedBox(
                    key: ValueKey<String>(
                      'statistics-forecast-baseline-$index',
                    ),
                    height: 2,
                    width: double.infinity,
                    child: ColoredBox(color: scheme.outlineVariant),
                  ),
                  if (day.due > 0)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: fraction.clamp(0.04, 1.0),
                        widthFactor: 1,
                        child: Container(
                          key: ValueKey<String>(
                            'statistics-forecast-bar-$index',
                          ),
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(AppRadii.xs),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xxs + 2),
            // D7: подпись не обрезается до одной буквы — FittedBox сохраняет
            // всё слово, уменьшая кегль под ширину колонки.
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                key: ValueKey<String>('statistics-forecast-label-$index'),
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: index == 0 ? scheme.primary : scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
