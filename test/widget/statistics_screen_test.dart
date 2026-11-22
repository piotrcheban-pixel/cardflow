import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';
import 'package:cardflow/ui/statistics/statistics_charts.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// Экран «Статистика» (SPEC A6.5, ADR-019 §4): состояния и блоки.
void main() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  /// Снимок с достаточной выборкой удержания: 20 повторений за 30 дней,
  /// 18 «вспомнил» → 90 %; слабая тема — «алгебра» (2 ошибки из 5).
  StatisticsSnapshot snapshot() {
    final List<ReviewSample> reviews = <ReviewSample>[
      for (int index = 0; index < 5; index++)
        ReviewSample(
          cardId: 'card-math',
          rating: index < 2 ? 1 : 3,
          reviewedAt: today.subtract(Duration(days: index)),
        ),
      for (int index = 0; index < 15; index++)
        ReviewSample(
          cardId: 'card-good',
          rating: 3,
          reviewedAt: today.subtract(Duration(days: index)),
        ),
    ];
    return StatisticsCalculator.build(
      reviews: reviews,
      tagsByCard: <String, List<String>>{
        'card-math': <String>['алгебра'],
        'card-good': <String>['язык'],
      },
      dueDates: <DateTime>[
        today,
        today.add(const Duration(days: 2, hours: 9)),
        today.add(const Duration(days: 2, hours: 18)),
      ],
      now: today.add(const Duration(hours: 12)),
    );
  }

  /// Снимок с малой выборкой: одно повторение за 30 дней (находка D6).
  StatisticsSnapshot lowSampleSnapshot() {
    return StatisticsCalculator.build(
      reviews: <ReviewSample>[
        ReviewSample(cardId: 'card-only', rating: 3, reviewedAt: today),
      ],
      tagsByCard: const <String, List<String>>{},
      dueDates: <DateTime>[today.add(const Duration(days: 1))],
      now: today.add(const Duration(hours: 12)),
    );
  }

  Future<void> pump(
    WidgetTester tester, {
    required FakeStatisticsRepository repository,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          statisticsRepository: repository,
        ),
        home: const StatisticsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('данные: удержание, карта, слабые темы, прогноз, неделя', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      repository: FakeStatisticsRepository(snapshot: snapshot()),
    );
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.statisticsTitle), findsOneWidget);
    // D6: выборка 20 повторений — процент удержания 90 % (18/20) правомерен.
    expect(find.text(l10n.statisticsRetentionValue(90)), findsOneWidget);
    expect(find.text(l10n.statisticsRetentionBasedOn(20)), findsWidgets);
    expect(find.text(l10n.statisticsHeatmapTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      findsOneWidget,
    );

    // D5/D6: в карточке удержания нет недельного графика, но есть полоса
    // прогресса до цели и подпись размера выборки.
    final Finder retentionPanel = find.byKey(
      const ValueKey<String>('statistics-retention-panel'),
    );
    expect(retentionPanel, findsOneWidget);
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.byType(StatisticsWaveform),
      ),
      findsNothing,
      reason: 'недельный график не относится к удержанию (D5)',
    );
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.byType(AppProgressBar),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.byKey(const ValueKey<String>('statistics-retention')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.text(l10n.statisticsGoal(90)),
      ),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('weak-topic-train-алгебра')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('weak-topic-алгебра')),
      findsOneWidget,
    );
    expect(find.text(l10n.statisticsWeakTopicStats(2, 5)), findsOneWidget);
    expect(find.text(l10n.statisticsWeakTopicTrain), findsOneWidget);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('statistics-forecast')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast')),
      findsOneWidget,
    );
    expect(find.text(l10n.statisticsForecastToday), findsOneWidget);
    expect(find.text(l10n.statisticsForecastTomorrow), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast-bar-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast-bar-1')),
      findsNothing,
      reason: 'на день без карточек столбца нет',
    );
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast-bar-2')),
      findsOneWidget,
    );
    // D7: у нулевого дня видна тонкая базовая линия, а не пустота.
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast-baseline-1')),
      findsOneWidget,
    );
    // D7: подписи дней — краткая форма (Пн…Вс), не одна буква и без ellipsis.
    final Text weekdayLabel = tester.widget<Text>(
      find.byKey(const ValueKey<String>('statistics-forecast-label-2')),
    );
    expect(const <String>{
      'Пн',
      'Вт',
      'Ср',
      'Чт',
      'Пт',
      'Сб',
      'Вс',
    }, contains(weekdayLabel.data));

    final Finder weekPanel = find.byKey(
      const ValueKey<String>('statistics-week-panel'),
    );
    await tester.ensureVisible(weekPanel);
    await tester.pumpAndSettle();
    // D5: график недели — ровно в одном месте, с итогом за неделю.
    expect(find.byType(StatisticsWaveform), findsOneWidget);
    expect(
      find.descendant(of: weekPanel, matching: find.byType(StatisticsWaveform)),
      findsOneWidget,
    );
    expect(find.text(l10n.statisticsWeekTotal(12)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-week')),
      findsOneWidget,
    );
    for (int index = 0; index < 7; index++) {
      expect(
        find.byKey(ValueKey<String>('statistics-week-bar-$index')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('statistics-week-label-$index')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('statistics-week-value-$index')),
        findsOneWidget,
      );
    }
    for (final String label in <String>[
      'Пн',
      'Вт',
      'Ср',
      'Чт',
      'Пт',
      'Сб',
      'Вс',
    ]) {
      expect(
        find.descendant(of: weekPanel, matching: find.text(label)),
        findsOneWidget,
        reason: 'у каждого из 7 дней есть подпись',
      );
    }
  });

  testWidgets('мало данных: процент удержания не показывается (D6)', (
    WidgetTester tester,
  ) async {
    await pump(
      tester,
      repository: FakeStatisticsRepository(snapshot: lowSampleSnapshot()),
    );
    final AppLocalizations l10n = l10nOf(tester);

    final Finder retentionPanel = find.byKey(
      const ValueKey<String>('statistics-retention-panel'),
    );
    expect(retentionPanel, findsOneWidget);
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.text(l10n.statisticsRetentionLowSample(1)),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.text(l10n.statisticsRetentionThreshold),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: retentionPanel,
        matching: find.byType(AppProgressBar),
      ),
      findsNothing,
      reason: 'без выборки полоса прогресса вводила бы в заблуждение',
    );
    // Плитка KPI тоже не показывает ложные 100 %.
    final Finder retentionKpi = find.byKey(
      const ValueKey<String>('statistics-kpi-retention'),
    );
    expect(
      find.descendant(
        of: retentionKpi,
        matching: find.text(l10n.statisticsRetentionNoData),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: retentionKpi,
        matching: find.text(l10n.statisticsRetentionThreshold),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: retentionKpi, matching: find.text('%')),
      findsNothing,
    );
    expect(find.text(l10n.statisticsRetentionValue(100)), findsNothing);
  });

  testWidgets('пустой прогноз: сообщение вместо ряда нулей (D7)', (
    WidgetTester tester,
  ) async {
    final StatisticsSnapshot emptyForecast = StatisticsCalculator.build(
      reviews: <ReviewSample>[
        ReviewSample(
          cardId: 'card-only',
          rating: 3,
          reviewedAt: today.subtract(const Duration(days: 10)),
        ),
      ],
      tagsByCard: const <String, List<String>>{},
      dueDates: const <DateTime>[],
      now: today.add(const Duration(hours: 12)),
    );
    await pump(
      tester,
      repository: FakeStatisticsRepository(snapshot: emptyForecast),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('statistics-forecast')),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.statisticsForecastEmpty), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast-bar-0')),
      findsNothing,
    );
    // Неделя тоже пуста: вместо графика — текст (D5).
    final Finder weekPanel = find.byKey(
      const ValueKey<String>('statistics-week-panel'),
    );
    await tester.ensureVisible(weekPanel);
    await tester.pumpAndSettle();
    expect(find.text(l10n.statisticsWeekEmpty), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('statistics-week')), findsNothing);
  });

  testWidgets('пусто: сообщение вместо блоков', (WidgetTester tester) async {
    await pump(tester, repository: FakeStatisticsRepository());
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.statisticsEmptyTitle), findsOneWidget);
    expect(find.text(l10n.statisticsEmptyMessage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      findsNothing,
    );
  });

  testWidgets('ошибка: сообщение и повтор запроса', (
    WidgetTester tester,
  ) async {
    final FakeStatisticsRepository repository = FakeStatisticsRepository()
      ..error = StateError('db down');
    await pump(tester, repository: repository);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.statisticsErrorTitle), findsOneWidget);
    repository.error = null;
    await tester.tap(find.text(l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text(l10n.statisticsEmptyTitle), findsOneWidget);
  });

  testWidgets('«Тренировать» открывает конструктор с тегом', (
    WidgetTester tester,
  ) async {
    String? tag;
    final List<GoRoute> routes = <GoRoute>[
      GoRoute(
        path: '/statistics',
        builder: (BuildContext context, GoRouterState state) =>
            const StatisticsScreen(),
      ),
      GoRoute(
        path: '/constructor',
        builder: (BuildContext context, GoRouterState state) {
          tag = state.uri.queryParameters['tag'];
          return const Scaffold(body: Text('КОНСТРУКТОР'));
        },
      ),
    ];
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          statisticsRepository: FakeStatisticsRepository(snapshot: snapshot()),
        ),
        routes: routes,
        initialLocation: '/statistics',
      ),
    );
    await tester.pumpAndSettle();

    final Finder train = find.byKey(
      const ValueKey<String>('weak-topic-train-алгебра'),
    );
    await tester.ensureVisible(train);
    await tester.pumpAndSettle();
    await tester.tap(train);
    await tester.pumpAndSettle();

    expect(find.text('КОНСТРУКТОР'), findsOneWidget);
    expect(tag, 'алгебра');
  });
}
