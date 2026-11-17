/// Экран «Статистика» (SPEC A6.5, ADR-019 §4; REDESIGN-SPEC §9.15).
///
/// Блоки: удержание за 30 дней, недельный прогресс, годовой календарь
/// повторений, прогноз нагрузки на 7 дней и слабые темы с переходом в
/// конструктор по тегу. Данные — `StatisticsSnapshot`; сырые ошибки
/// пользователю не показываются (только ARB). Оформление — `NcTopBar`,
/// `NcSurface`, `NcIcon3D`, `NcSection`, `NcBadge`, `NcProgressLine`; цвета
/// графиков приходят из `NcTheme`.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/statistics/statistics_charts.dart';

/// Экран статистики обучения.
class StatisticsScreen extends ConsumerStatefulWidget {
  /// Создаёт экран.
  const StatisticsScreen({super.key});

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final AsyncValue<StatisticsSnapshot> snapshot = ref.watch(
      statisticsProvider,
    );
    return NcGlassGroup(
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              NcTopBar(
                title: l10n.statisticsTitle,
                largeTitle: l10n.statisticsTitle,
                scrollController: _scrollController,
              ),
              Expanded(
                child: snapshot.when(
                  loading: () => const _StatisticsSkeleton(),
                  error: (Object error, StackTrace stackTrace) => NcErrorState(
                    message: l10n.statisticsErrorTitle,
                    retryLabel: l10n.retry,
                    onRetry: () => ref.invalidate(statisticsProvider),
                  ),
                  data: (StatisticsSnapshot statistics) => statistics.isEmpty
                      ? Center(
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: NcEmptyState(
                              iconName: 'empty_stats',
                              title: l10n.statisticsEmptyTitle,
                              message: l10n.statisticsEmptyMessage,
                            ),
                          ),
                        )
                      : _StatisticsContent(
                          statistics: statistics,
                          controller: _scrollController,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatisticsContent extends StatelessWidget {
  const _StatisticsContent({
    required this.statistics,
    required this.controller,
  });

  final StatisticsSnapshot statistics;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final List<int> weekCounts = <int>[
      for (final DayCount day in statistics.week) day.count,
    ];
    final int weekTotal = weekCounts.fold<int>(0, (int a, int b) => a + b);
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double content = constraints.maxWidth - 32;
        final double cardWidth = constraints.maxWidth >= 1024
            ? (content - 16) / 2
            : content;
        return ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            _RetentionCard(statistics: statistics),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: <Widget>[
                SizedBox(
                  width: cardWidth,
                  child: _WeekCard(
                    week: statistics.week,
                    values: weekCounts,
                    total: weekTotal,
                  ),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _HeatmapCard(statistics: statistics),
                ),
                SizedBox(
                  width: cardWidth,
                  child: _ForecastCard(forecast: statistics.forecast),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _WeakTopicsSection(topics: statistics.weakTopics),
          ],
        );
      },
    );
  }
}

/// Базовая карточка блока статистики на `NcSurface` (§9.15).
class _StatsCard extends StatelessWidget {
  const _StatsCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return NcSurface(
      radius: NcRadii.l,
      level: 1,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            title,
            style: theme.typography.overline.copyWith(
              color: theme.colors.textTertiary,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Удержание за 30 дней: `target` 56, процент `displayXL`, waveform.
class _RetentionCard extends StatelessWidget {
  const _RetentionCard({required this.statistics});

  final StatisticsSnapshot statistics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final List<int> weekCounts = <int>[
      for (final DayCount day in statistics.week) day.count,
    ];
    final int weekTotal = weekCounts.fold<int>(0, (int a, int b) => a + b);
    final double? retention = statistics.retention30;
    final int percent = retention == null ? 0 : (retention * 100).round();
    return _StatsCard(
      title: l10n.statisticsRetentionTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              const NcIcon3D(name: 'target', size: 56, showShadow: false),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      retention == null
                          ? l10n.statisticsRetentionNoData
                          : l10n.statisticsRetentionValue(percent),
                      key: const ValueKey<String>('statistics-retention'),
                      style: retention == null
                          ? theme.typography.bodyS.copyWith(
                              color: theme.colors.textSecondary,
                            )
                          : theme.typography.displayXL.copyWith(
                              color: theme.colors.aurum,
                              fontFeatures: const <FontFeature>[
                                FontFeature.tabularFigures(),
                              ],
                            ),
                    ),
                    if (retention != null)
                      Text(
                        l10n.statisticsRetentionCaption,
                        style: theme.typography.bodyS.copyWith(
                          color: theme.colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          StatisticsWaveform(
            values: weekCounts,
            empty: retention == null,
            semanticsLabel: l10n.statisticsWeekSemantics(weekTotal),
          ),
        ],
      ),
    );
  }
}

/// Недельный прогресс: waveform 7 столбиков, подписи дней, `streak_flame`.
class _WeekCard extends StatelessWidget {
  const _WeekCard({
    required this.week,
    required this.values,
    required this.total,
  });

  final List<DayCount> week;
  final List<int> values;
  final int total;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    return _StatsCard(
      title: l10n.statisticsWeekTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: StatisticsWaveform(
                  key: const ValueKey<String>('statistics-week'),
                  values: values,
                  semanticsLabel: l10n.statisticsWeekSemantics(total),
                  height: 72,
                ),
              ),
              const SizedBox(width: 8),
              const NcIcon3D(name: 'streak_flame', size: 40, showShadow: false),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: <Widget>[
              for (var index = 0; index < week.length; index++)
                Expanded(
                  child: Center(
                    child: Text(
                      localizations.narrowWeekdays[week[index].day.weekday % 7],
                      style: theme.typography.labelM.copyWith(
                        color: index == week.length - 1
                            ? theme.colors.aurum
                            : theme.colors.textTertiary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Тепловая карта года и легенда «меньше … больше».
class _HeatmapCard extends StatelessWidget {
  const _HeatmapCard({required this.statistics});

  final StatisticsSnapshot statistics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final int yearTotal = statistics.heatmap.fold<int>(
      0,
      (int sum, DayCount day) => sum + day.count,
    );
    return _StatsCard(
      title: l10n.statisticsHeatmapTitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Semantics(
            label: l10n.statisticsChartSemantics(yearTotal),
            image: true,
            child: StatisticsHeatmap(days: statistics.heatmap),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              Text(
                l10n.statisticsHeatmapLess,
                style: theme.typography.labelM.copyWith(
                  color: theme.colors.textTertiary,
                ),
              ),
              const SizedBox(width: 6),
              for (var index = 0; index < 5; index++) ...<Widget>[
                Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: theme.colors.heat[index],
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ],
              const SizedBox(width: 6),
              Text(
                l10n.statisticsHeatmapMore,
                style: theme.typography.labelM.copyWith(
                  color: theme.colors.textTertiary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Прогноз нагрузки на 7 дней: столбики `r.xs`, сегодня — Aurum.
class _ForecastCard extends StatelessWidget {
  const _ForecastCard({required this.forecast});

  final List<ForecastDay> forecast;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final MaterialLocalizations localizations = MaterialLocalizations.of(
      context,
    );
    final int maxDue = forecast.isEmpty
        ? 0
        : forecast
              .map((ForecastDay day) => day.due)
              .reduce((int a, int b) => a > b ? a : b);
    return _StatsCard(
      title: l10n.statisticsForecastTitle,
      child: SizedBox(
        key: const ValueKey<String>('statistics-forecast'),
        height: 140,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: <Widget>[
            for (int index = 0; index < forecast.length; index++)
              Expanded(
                child: _ForecastBar(
                  index: index,
                  day: forecast[index],
                  label: _label(
                    l10n,
                    localizations,
                    forecast[index].day,
                    index,
                  ),
                  semantics: l10n.statisticsForecastSemantics(
                    _label(l10n, localizations, forecast[index].day, index),
                    forecast[index].due,
                  ),
                  fraction: maxDue == 0 ? 0 : forecast[index].due / maxDue,
                  today: index == 0,
                ),
              ),
          ],
        ),
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
    required this.index,
    required this.day,
    required this.label,
    required this.semantics,
    required this.fraction,
    required this.today,
  });

  final int index;
  final ForecastDay day;
  final String label;
  final String semantics;
  final double fraction;
  final bool today;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Semantics(
      label: semantics,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: <Widget>[
            Text(
              day.due.toString(),
              style: theme.typography.monoM.copyWith(
                color: theme.colors.textSecondary,
              ),
            ),
            const SizedBox(height: 4),
            Expanded(
              child: day.due == 0
                  ? Align(
                      alignment: Alignment.bottomCenter,
                      child: Container(
                        width: 4,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 2),
                        decoration: BoxDecoration(
                          color: theme.colors.aurum,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : Align(
                      alignment: Alignment.bottomCenter,
                      child: FractionallySizedBox(
                        heightFactor: fraction.clamp(0.04, 1.0),
                        child: Container(
                          key: ValueKey<String>(
                            'statistics-forecast-bar-$index',
                          ),
                          width: double.infinity,
                          decoration: BoxDecoration(
                            color: today
                                ? theme.colors.aurum
                                : theme.colors.ink5,
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(NcRadii.xs),
                            ),
                            border: today
                                ? null
                                : Border(
                                    top: BorderSide(
                                      color: theme.colors.aurum,
                                      width: 1.5,
                                    ),
                                  ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.labelM.copyWith(
                color: today ? theme.colors.aurum : theme.colors.textTertiary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Слабые темы: тег, доля ошибок бейджем, мини-полоска и «Тренировать».
class _WeakTopicsSection extends StatelessWidget {
  const _WeakTopicsSection({required this.topics});

  final List<WeakTopic> topics;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    if (topics.isEmpty) {
      return _StatsCard(
        title: l10n.statisticsWeakTopicsTitle,
        child: Text(
          l10n.statisticsWeakTopicsEmpty,
          style: theme.typography.bodyS.copyWith(
            color: theme.colors.textSecondary,
          ),
        ),
      );
    }
    return NcSection(
      title: l10n.statisticsWeakTopicsTitle,
      children: <Widget>[
        for (var index = 0; index < topics.length; index++)
          _WeakTopicRow(
            topic: topics[index],
            showDivider: index < topics.length - 1,
          ),
      ],
    );
  }
}

class _WeakTopicRow extends StatelessWidget {
  const _WeakTopicRow({required this.topic, required this.showDivider});

  final WeakTopic topic;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final AppLocalizations l10n = AppLocalizations.of(context);
    final NcTheme theme = NcTheme.of(context);
    final double share = topic.reviews == 0 ? 0 : topic.errors / topic.reviews;
    return NcListRow(
      showDivider: showDivider,
      title: Text(
        topic.tag,
        key: ValueKey<String>('weak-topic-${topic.tag}'),
        style: theme.typography.titleS.copyWith(
          color: theme.colors.textPrimary,
        ),
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            NcBadge(
              label: l10n.statisticsWeakTopicStats(topic.errors, topic.reviews),
              tone: NcBadgeTone.ember,
            ),
            const SizedBox(height: 6),
            NcProgressLine(
              value: share.clamp(0.0, 1.0),
              color: theme.colors.ember,
            ),
            const SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: NcButton(
                key: ValueKey<String>('weak-topic-train-${topic.tag}'),
                label: l10n.statisticsWeakTopicTrain,
                variant: NcButtonVariant.secondary,
                size: NcButtonSize.s,
                onPressed: () => context.push(
                  '${AppRoutes.constructorPath}?tag=${Uri.encodeQueryComponent(topic.tag)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Загрузка статистики: skeleton-карточки.
class _StatisticsSkeleton extends StatelessWidget {
  const _StatisticsSkeleton();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: const <Widget>[
        NcSkeleton(height: 160, radius: NcRadii.l),
        SizedBox(height: 16),
        NcSkeleton(height: 180, radius: NcRadii.l),
        SizedBox(height: 16),
        NcSkeleton(height: 140, radius: NcRadii.l),
      ],
    );
  }
}
