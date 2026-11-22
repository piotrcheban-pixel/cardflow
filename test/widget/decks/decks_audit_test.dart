import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Аудит 1.0 (D17/D18): пустой результат поиска и сообщения о пустой колоде.
void main() {
  Future<void> pumpDecks(
    WidgetTester tester, {
    required FakeDeckRepository repository,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(deckRepository: repository),
        routes: decksRoutes(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('D17: пустой результат поиска — запрос и «Сбросить поиск»', (
    WidgetTester tester,
  ) async {
    await pumpDecks(
      tester,
      repository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(id: 'deck-1', name: 'Ёжики'),
          makeSummary(id: 'deck-2', name: 'История'),
        ],
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byTooltip(l10n.decksSearchTooltip));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'to');
    await tester.pumpAndSettle();

    expect(find.text(l10n.decksNoResultsForQuery('to')), findsOneWidget);
    expect(find.text(l10n.decksSearchResetAction), findsOneWidget);
    expect(find.text(l10n.decksEmptyMessage), findsNothing);

    await tester.tap(find.text(l10n.decksSearchResetAction));
    await tester.pumpAndSettle();
    expect(find.text('Ёжики'), findsOneWidget);
    expect(find.text('История'), findsOneWidget);
  });

  testWidgets('D18: пустая колода — одно нейтральное сообщение', (
    WidgetTester tester,
  ) async {
    await pumpDecks(
      tester,
      repository: FakeDeckRepository(
        summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Пустая')],
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.deckCardsEmpty), findsOneWidget);
    expect(find.text(l10n.deckCardCount(0)), findsNothing);
    expect(find.text(l10n.deckDueCount(0)), findsNothing);
  });
}
