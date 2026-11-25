import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// D5/D7: геометрия недельного графика и подписи прогноза на узком экране.
void main() {
  final DateTime now = DateTime.now();
  final DateTime today = DateTime(now.year, now.month, now.day);

  /// Неделя с повторениями каждый день: 7 непустых столбцов.
  StatisticsSnapshot fullWeekSnapshot() {
    return StatisticsCalculator.build(
      reviews: <ReviewSample>[
        for (int index = 0; index < 7; index++)
          ReviewSample(
            cardId: 'card-$index',
            rating: 3,
            reviewedAt: today.subtract(Duration(days: index)),
          ),
      ],
      tagsByCard: const <String, List<String>>{},
      dueDates: <DateTime>[today],
      now: today.add(const Duration(hours: 12)),
    );
  }

  /// В неделе было только сегодняшнее повторение: остальные дни — нули.
  StatisticsSnapshot sparseWeekSnapshot() {
    return StatisticsCalculator.build(
      reviews: <ReviewSample>[
        ReviewSample(cardId: 'card-only', rating: 3, reviewedAt: today),
      ],
      tagsByCard: const <String, List<String>>{},
      dueDates: <DateTime>[today],
      now: today.add(const Duration(hours: 12)),
    );
  }

  Future<void> pumpAtPhoneWidth(
    WidgetTester tester,
    StatisticsSnapshot snapshot,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithHome(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          statisticsRepository: FakeStatisticsRepository(snapshot: snapshot),
        ),
        home: const StatisticsScreen(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    '390 px: узкие столбцы, значения и подписи дней не обрезаны (D5)',
    (WidgetTester tester) async {
      await pumpAtPhoneWidth(tester, fullWeekSnapshot());
      final AppLocalizations l10n = l10nOf(tester);
      expect(tester.takeException(), isNull);

      final Finder chart = find.byKey(
        const ValueKey<String>('statistics-week'),
      );
      await tester.ensureVisible(chart);
      await tester.pumpAndSettle();

      // Высота графика в заданном диапазоне 96–120 px.
      expect(
        tester.getSize(chart).height,
        inInclusiveRange(96.0, 120.0),
        reason: 'высота недельного графика',
      );
      for (int index = 0; index < 7; index++) {
        final Finder bar = find.byKey(
          ValueKey<String>('statistics-week-bar-$index'),
        );
        expect(bar, findsOneWidget);
        // D5: столбец — половина ячейки, а не «клякса» на всю ширину.
        // Аудит 2.0: 20 px-й предел на широком экране (ячейка ≈68 px) давал
        // «спички»; теперь столбец 14–32 px (≈50 % ячейки).
        expect(
          tester.getSize(bar).width,
          inInclusiveRange(14.0, 32.0),
          reason: 'ширина столбца $index',
        );
        expect(
          find.byKey(ValueKey<String>('statistics-week-value-$index')),
          findsOneWidget,
        );
        expect(
          find.byKey(ValueKey<String>('statistics-week-label-$index')),
          findsOneWidget,
        );
      }
      // Семь подряд идущих дней покрывают все дни недели — подписи не режутся.
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
          find.descendant(of: chart, matching: find.text(label)),
          findsOneWidget,
          reason: 'подпись дня $label',
        );
      }
      expect(tester.takeException(), isNull);

      // D7: подписи прогноза не сокращаются до одной буквы и на 390 px.
      final Finder forecast = find.byKey(
        const ValueKey<String>('statistics-forecast'),
      );
      await tester.ensureVisible(forecast);
      await tester.pumpAndSettle();
      expect(find.text(l10n.statisticsForecastToday), findsOneWidget);
      expect(find.text(l10n.statisticsForecastTomorrow), findsOneWidget);
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
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('нулевые дни недели: базовая линия вместо «чёрточки» (D5)', (
    WidgetTester tester,
  ) async {
    await pumpAtPhoneWidth(tester, sparseWeekSnapshot());
    expect(tester.takeException(), isNull);

    final Finder chart = find.byKey(const ValueKey<String>('statistics-week'));
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();

    // Нулевые дни (0..5) — базовая линия и подпись 0, без столбца.
    for (int index = 0; index < 6; index++) {
      expect(
        find.byKey(ValueKey<String>('statistics-week-baseline-$index')),
        findsOneWidget,
      );
      expect(
        find.byKey(ValueKey<String>('statistics-week-bar-$index')),
        findsNothing,
      );
      expect(
        find.byKey(ValueKey<String>('statistics-week-value-$index')),
        findsOneWidget,
      );
    }
    expect(
      find.byKey(const ValueKey<String>('statistics-week-bar-6')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });
}
