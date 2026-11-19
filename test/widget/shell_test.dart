import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/shell/app_sidebar.dart';
import 'package:cardflow/ui/shell/app_top_header.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';
import '../helpers/settings_fakes.dart';

/// Оболочка навигации A6.1 (ADR-038): постоянная боковая панель на широком
/// экране, выдвижной ящик — на узком; нижней навигации больше нет.
void main() {
  Widget appWidget({int decks = 1}) {
    return ProviderScope(
      overrides: decksOverrides(
        deckRepository: FakeDeckRepository(
          summaries: <DeckSummary>[
            makeSummary(id: 'deck-1', name: 'Испанский', totalCards: 1),
            if (decks > 1)
              makeSummary(id: 'deck-2', name: 'История', totalCards: 2),
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

  testWidgets('телефон: выдвижная навигация, все разделы доступны', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(400, 800));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(AppTopHeader), findsOneWidget);
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.text('Сессия'), findsNothing);

    // Меню открывает тот же набор пунктов, что и постоянная панель.
    await tester.tap(find.byTooltip(l10n.shellOpenNavTooltip));
    await tester.pumpAndSettle();
    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.text(l10n.navDecks), findsOneWidget);
    expect(find.text(l10n.navAi), findsOneWidget);
    expect(find.text(l10n.navStatistics), findsOneWidget);
    expect(find.text(l10n.navSettings), findsOneWidget);

    await tester.tap(find.text(l10n.navStatistics));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(find.byType(DecksScreen), findsNothing);

    await tester.tap(find.byTooltip(l10n.shellOpenNavTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.navSettings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);

    await tester.tap(find.byTooltip(l10n.shellOpenNavTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.navDecks));
    await tester.pumpAndSettle();
    expect(find.byType(DecksScreen), findsOneWidget);
    // Ветка не только существует, но и отрисовала данные после возврата.
    expect(find.text('Испанский'), findsWidgets);
  });

  testWidgets('планшет/ПК: постоянная боковая панель и крошки раздела', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(AppSidebar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(NavigationBar), findsNothing);
    expect(find.byTooltip(l10n.shellOpenNavTooltip), findsNothing);
    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.text(l10n.shellBreadcrumb(l10n.navDecks)), findsOneWidget);

    await tester.tap(find.text(l10n.navStatistics));
    await tester.pumpAndSettle();
    expect(find.byType(StatisticsScreen), findsOneWidget);
    expect(find.text(l10n.shellBreadcrumb(l10n.navStatistics)), findsOneWidget);

    await tester.tap(find.text(l10n.navSettings));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('узкий экран: шапка ниже системного статус-бара', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(390, 800));
    tester.view.padding = const FakeViewPadding(top: 24);
    addTearDown(tester.view.resetPadding);
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();

    expect(
      tester.getTopLeft(find.byType(AppTopHeader)).dy,
      greaterThanOrEqualTo(24),
      reason: 'Без AppBar оболочка обязана учитывать SafeArea статус-бара',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('глобальное действие «Новая карточка»: выбор колоды', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(appWidget(decks: 2));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-new-card')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('shell-new-card-deck-deck-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('shell-new-card-deck-deck-2')),
      findsOneWidget,
    );
  });

  testWidgets('поиск в панели открывает поле поиска колод', (
    WidgetTester tester,
  ) async {
    await setSize(tester, const Size(1200, 800));
    await tester.pumpWidget(appWidget());
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.text(l10n.shellSearchHint));
    await tester.pumpAndSettle();

    expect(find.byType(DecksScreen), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });
}
