import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// Экран «Статистика» (SPEC A6.5, ADR-019 §4): состояния и блоки.
void main() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  StatisticsSnapshot snapshot() {
    final List<ReviewSample> reviews = <ReviewSample>[
      for (int index = 0; index < 5; index++)
        ReviewSample(
          cardId: 'card-math',
          rating: index < 2 ? 1 : 3,
          reviewedAt: today.subtract(Duration(days: index)),
        ),
      for (int index = 0; index < 5; index++)
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

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
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

    expect(find.text(l10n.statisticsTitle), findsWidgets);
    expect(find.text(l10n.statisticsRetentionValue(80)), findsOneWidget);
    expect(find.text(l10n.statisticsHeatmapTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      findsOneWidget,
    );

    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('weak-topic-train-алгебра')),
    );
    expect(
      find.byKey(const ValueKey<String>('weak-topic-алгебра')),
      findsOneWidget,
    );
    expect(find.text(l10n.statisticsWeakTopicStats(2, 5)), findsOneWidget);
    expect(find.text(l10n.statisticsWeakTopicTrain), findsOneWidget);

    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('statistics-forecast')),
    );
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

    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('statistics-week')),
    );
    expect(
      find.byKey(const ValueKey<String>('statistics-week')),
      findsOneWidget,
    );
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
    await scrollTo(tester, train);
    await tester.tap(train);
    await tester.pumpAndSettle();

    expect(find.text('КОНСТРУКТОР'), findsOneWidget);
    expect(tag, 'алгебра');
  });
}
