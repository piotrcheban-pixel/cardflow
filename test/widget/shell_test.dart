import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// Оболочка навигации A6.1 (ADR-019 §3).
void main() {
  Widget appWidget() {
    return ProviderScope(
      overrides: decksOverrides(
        deckRepository: FakeDeckRepository(
          summaries: <DeckSummary>[
            makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 1),
          ],
        ),
        statisticsRepository: FakeStatisticsRepository(),
      ),
      child: const CardFlowApp(),
    );
  }

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  testWidgets('телефон: NavigationBar, переключение веток, «Сессия» скрыта', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(400, 800));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.text('Сессия'), findsNothing);

    await tester.tap(find.text(l10n.navStatistics));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      1,
    );

    await tester.tap(find.text(l10n.navSettings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex,
      2,
    );

    await tester.tap(find.text(l10n.navDecks));
    await tester.pumpAndSettle();
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.text('Испанский'), findsOneWidget);
  });

  testWidgets('планшет/ПК: NavigationRail вместо NavigationBar', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(DecksScreen), findsOneWidget);

    await tester.tap(find.text(l10n.navStatistics));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
  });
}
