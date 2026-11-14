/// Экран «Статистика» (SPEC A6.5, ADR-019 §4).
///
/// Блоки: удержание за 30 дней с waveform, годовой календарь повторений,
/// недельный прогресс, слабые темы с переходом в конструктор по тегу и
/// прогноз нагрузки на 7 дней. Данные — `StatisticsSnapshot`; сырые ошибки
/// пользователю не показываются (только ARB).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/statistics/statistics_charts.dart';

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
    return Scaffold(
      appBar: AppBar(title: Text(l10n.statisticsTitle)),
      body: snapshot.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) =>
            _StatisticsError(onRetry: () => ref.invalidate(statisticsProvider)),
        data: (StatisticsSnapshot statistics) => statistics.isEmpty
            ? const _StatisticsEmpty()
            : _StatisticsContent(statistics: statistics),
      ),
    );
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({required this.statistics});

  final StatisticsSnapshot statistics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    final List<int> weekCounts = <int>[
      for (final DayCount day in statistics.week) day.count,
    ];
    final int weekTotal = weekCounts.fold<int>(0, (int a, int b) => a + b);
    final int yearTotal = statistics.heatmap.fold<int>(
      0,
      (int sum, DayCount day) => sum + day.count,
    );
    final double? retention = statistics.retention30;
    final int retentionPercent = retention == null
        ? 0
        : (retention * 100).round();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      children: <Widget>[
        _SectionCard(
          title: l10n.statisticsRetentionTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                retention == null
                    ? l10n.statisticsRetentionNoData
                    : l10n.statisticsRetentionValue(retentionPercent),
                key: const ValueKey<String>('statistics-retention'),
                style: retention == null
                    ? theme.textTheme.titleMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : theme.textTheme.displayMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                      ),
              ),
              const SizedBox(height: 12),
              StatisticsWaveform(
                values: weekCounts,
                semanticsLabel: l10n.statisticsWeekSemantics(weekTotal),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: l10n.statisticsHeatmapTitle,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Semantics(
                label: l10n.statisticsChartSemantics(yearTotal),
                image: true,
                child: StatisticsHeatmap(days: statistics.heatmap),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _WeakTopicsSection(topics: statistics.weakTopics),
        const SizedBox(height: 16),
        _SectionCard(
          title: l10n.statisticsForecastTitle,
          child: _ForecastChart(forecast: statistics.forecast),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: l10n.statisticsWeekTitle,
          child: StatisticsWaveform(
            key: const ValueKey<String>('statistics-week'),
            values: weekCounts,
            semanticsLabel: l10n.statisticsWeekSemantics(weekTotal),
            height: 72,
          ),
        ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _WeakTopicsSection extends StatelessWidget {
  const _WeakTopicsSection({required this.topics});

  final List<WeakTopic> topics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return _SectionCard(
      title: l10n.statisticsWeakTopicsTitle,
      child: topics.isEmpty
          ? Text(
              l10n.statisticsWeakTopicsEmpty,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : Column(
              children: <Widget>[
                for (final WeakTopic topic in topics)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Text(
                                topic.tag,
                                key: ValueKey<String>(
                                  'weak-topic-${topic.tag}',
                                ),
                                style: theme.textTheme.titleSmall,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                l10n.statisticsWeakTopicStats(
                                  topic.errors,
                                  topic.reviews,
                                ),
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          key: ValueKey<String>(
                            'weak-topic-train-${topic.tag}',
                          ),
                          onPressed: () => context.push(
                            '${AppRoutes.constructorPath}'
                            '?tag=${Uri.encodeQueryComponent(topic.tag)}',
                          ),
                          child: Text(l10n.statisticsWeakTopicTrain),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ForecastChart extends StatelessWidget {
  const _ForecastChart({required this.forecast});

  final List<ForecastDay> forecast;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final int maxDue = forecast.isEmpty
        ? 0
        : forecast
              .map((ForecastDay day) => day.due)
              .reduce((int a, int b) => a > b ? a : b);
    return SizedBox(
      key: const ValueKey<String>('statistics-forecast'),
      height: 140,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          for (int index = 0; index < forecast.length; index++)
            Expanded(
              child: _ForecastBar(
                day: forecast[index],
                label: _label(l10n, localizations, forecast[index].day, index),
                semantics: l10n.statisticsForecastSemantics(
                  _label(l10n, localizations, forecast[index].day, index),
                  forecast[index].due,
                ),
                fraction: maxDue == 0 ? 0 : forecast[index].due / maxDue,
                color: scheme.primary,
              ),
            ),
        ],
      ),
    );
  }

  static String _label(
    AppLocalizations l10n,
    MaterialLocalizations localizations,
    DateTime day,
    int index,
  ) {
    if (index == 0) return l10n.statisticsForecastToday;
    if (index == 1) return l10n.statisticsForecastTomorrow;
    // narrowWeekdays идут с воскресенья; DateTime.weekday — с понедельника.
    return localizations.narrowWeekdays[day.weekday % 7];
  }
}

class _ForecastBar extends StatelessWidget {
  const _ForecastBar({
    required this.day,
    required this.label,
    required this.semantics,
    required this.fraction,
    required this.color,
  });

  final ForecastDay day;
  final String label;
  final String semantics;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Semantics(
      label: semantics,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(
              day.due.toString(),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: FractionallySizedBox(
                  heightFactor: fraction.clamp(0.04, 1.0),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: const BorderRadius.vertical(
                        top: Radius.circular(6),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Text(label, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _StatisticsEmpty extends StatelessWidget {
  const _StatisticsEmpty();

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(
              Icons.insights_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              l10n.statisticsEmptyTitle,
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              l10n.statisticsEmptyMessage,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatisticsError extends StatelessWidget {
  const _StatisticsError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.error_outline, size: 48, color: theme.colorScheme.error),
            const SizedBox(height: 12),
            Text(l10n.statisticsErrorTitle, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            TextButton(onPressed: onRetry, child: Text(l10n.retry)),
          ],
        ),
      ),
    );
  }
}
