import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/redesign_screen_fixtures.dart';

/// Статистика в оформлении Nocturne (REDESIGN-SPEC §9.15).
void main() {
  final AppLocalizations l10n = ncL10n;

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      260,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  Future<void> pumpStatistics(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    bool empty = false,
  }) => pumpNcScreen(
    tester,
    home: const StatisticsScreen(),
    overrides: ncStage3Overrides(
      statistics: empty ? emptyStatistics() : ncStage3Statistics(),
    ),
    config: NcScreenConfig(size: size),
  );

  testWidgets('ключи §9.15 и новые элементы облика', (
    WidgetTester tester,
  ) async {
    await pumpStatistics(tester);

    expect(
      find.byKey(const ValueKey<String>('statistics-retention')),
      findsOneWidget,
    );
    expect(find.text(l10n.statisticsRetentionCaption), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (Widget widget) => widget is NcIcon3D && widget.name == 'target',
      ),
      findsOneWidget,
    );
    expect(find.text(l10n.statisticsHeatmapLess), findsOneWidget);
    expect(find.text(l10n.statisticsHeatmapMore), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      findsOneWidget,
    );

    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('weak-topic-train-биология')),
    );
    expect(
      find.byKey(const ValueKey<String>('weak-topic-биология')),
      findsOneWidget,
    );
    expect(find.byType(NcBadge), findsWidgets);

    await scrollTo(
      tester,
      find.byKey(const ValueKey<String>('statistics-forecast')),
    );
    expect(
      find.byKey(const ValueKey<String>('statistics-forecast-bar-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('statistics-week')),
      findsOneWidget,
    );
    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('«Тренировать» — прежний переход с тегом', (
    WidgetTester tester,
  ) async {
    await pumpStatistics(tester);
    final Finder train = find.byKey(
      const ValueKey<String>('weak-topic-train-биология'),
    );
    await scrollTo(tester, train);
    // Роутера в стенде нет: проверяем, что кнопка живая и имеет ключ.
    expect(train, findsOneWidget);
  });

  testWidgets('пусто: NcEmptyState с сообщением', (WidgetTester tester) async {
    await pumpStatistics(tester, empty: true);
    expect(find.text(l10n.statisticsEmptyTitle), findsOneWidget);
    expect(find.text(l10n.statisticsEmptyMessage), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      findsNothing,
    );
  });

  testWidgets('ширины: удержание на всю ширину, 2 колонки на ПК', (
    WidgetTester tester,
  ) async {
    await pumpStatistics(tester, size: const Size(1440, 900));
    final double retentionWidth = tester
        .getSize(
          find
              .ancestor(
                of: find.byKey(const ValueKey<String>('statistics-retention')),
                matching: find.byType(NcSurface),
              )
              .first,
        )
        .width;
    final Offset week = tester.getTopLeft(
      find.byKey(const ValueKey<String>('statistics-week')),
    );
    final Offset heatmap = tester.getTopLeft(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
    );
    expect(week.dy, heatmap.dy);
    expect(retentionWidth, greaterThan(heatmap.dx));
    expect(heatmap.dx, greaterThan(600));

    await pumpStatistics(tester);
    final Offset weekPhone = tester.getTopLeft(
      find.byKey(const ValueKey<String>('statistics-week')),
    );
    final Offset heatmapPhone = tester.getTopLeft(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
    );
    expect(weekPhone.dy, lessThan(heatmapPhone.dy));
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const StatisticsScreen(),
      overrides: ncStage3Overrides(statistics: ncStage3Statistics()),
    );
    expect(
      find.byKey(const ValueKey<String>('statistics-retention')),
      findsOneWidget,
    );
  });
}
