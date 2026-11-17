import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/glass_budget.dart';
import '../helpers/nc_harness.dart';
import '../helpers/nc_screen_harness.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// Оболочка навигации A6.1 в оформлении Nocturne (REDESIGN-SPEC §9.1).
///
/// Тесты ищут пункты по ключам `shell-nav-*` (контракт), а раскладку — по
/// типу компонента: док < 600, рейл 600–1023, сайдбар ≥ 1024. Старые проверки
/// `NavigationBar`/`NavigationRail` переписаны на ключи отдельным коммитом.
void main() {
  final AppLocalizations l10n = ncL10n;

  List<Override> overrides() => decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 1),
      ],
    ),
    statisticsRepository: FakeStatisticsRepository(),
    appSettingsStore: FakeAppSettingsStore(),
  );

  Widget appWidget() {
    return ProviderScope(overrides: overrides(), child: const CardFlowApp());
  }

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Finder navKey(String branch) =>
      find.byKey(ValueKey<String>('shell-nav-$branch'));

  testWidgets('телефон 390: док на стекле, ключи всех трёх веток', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();

    expect(find.byType(NcNavDock), findsOneWidget);
    expect(find.byType(NcNavRail), findsNothing);
    expect(find.byType(NcNavSidebar), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(navKey('decks'), findsOneWidget);
    expect(navKey('statistics'), findsOneWidget);
    expect(navKey('settings'), findsOneWidget);
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.text('Сессия'), findsNothing);
    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('телефон: переключение веток и активная подпись', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(390, 844));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();

    // Подпись видна только у активного пункта.
    Finder dockText(String label) =>
        find.descendant(of: find.byType(NcNavDock), matching: find.text(label));
    expect(dockText(l10n.navDecks), findsOneWidget);
    expect(dockText(l10n.navStatistics), findsNothing);

    await tester.tap(navKey('statistics'));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(tester.widget<NcNavDock>(find.byType(NcNavDock)).selectedIndex, 1);
    expect(dockText(l10n.navStatistics), findsOneWidget);
    expect(dockText(l10n.navDecks), findsNothing);

    await tester.tap(navKey('settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(tester.widget<NcNavDock>(find.byType(NcNavDock)).selectedIndex, 2);

    await tester.tap(navKey('decks'));
    await tester.pumpAndSettle();
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.text('Испанский'), findsOneWidget);
  });

  testWidgets('планшет 800: рейл с логотипом вместо дока', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(800, 1000));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();

    expect(find.byType(NcNavRail), findsOneWidget);
    expect(find.byType(NcNavDock), findsNothing);
    expect(find.byType(NcNavSidebar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('nc-nav-logo')), findsWidgets);
    expectGlassBudget(tester, maxGroups: 2);

    await tester.tap(navKey('statistics'));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(tester.widget<NcNavRail>(find.byType(NcNavRail)).selectedIndex, 1);
  });

  testWidgets('ПК 1440: расширенный сайдбар 248 px с названием', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(1440, 900));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();

    expect(find.byType(NcNavSidebar), findsOneWidget);
    expect(find.byType(NcNavRail), findsNothing);
    expect(find.byType(NcNavDock), findsNothing);
    expect(find.text(l10n.appTitle), findsOneWidget);
    expect(navKey('settings'), findsOneWidget);
    expectGlassBudget(tester, maxGroups: 2);

    await tester.tap(navKey('settings'));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
    expect(
      tester.widget<NcNavSidebar>(find.byType(NcNavSidebar)).selectedIndex,
      2,
    );
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    // Пустые ветки: проверяется оболочка, а не Material-экраны этапа 3.2.
    final GoRouter router = shellOnlyRouter();
    addTearDown(router.dispose);
    await pumpNcScreenAtTextScale2(
      tester,
      router: router,
      overrides: overrides(),
    );

    expect(find.byType(NcNavDock), findsOneWidget);
    expect(navKey('decks'), findsOneWidget);
    expect(navKey('statistics'), findsOneWidget);
    expect(navKey('settings'), findsOneWidget);
  });
}
