import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Глобальный переход тостов (REDESIGN-PLAN, шаг 2.5): `showAppMessage` и
/// `showArchivedUndoSnackbar` показывают `NcToast`, а сигнатуры, тексты и
/// поведение undo остаются прежними.
void main() {
  Future<void> pumpDecks(
    WidgetTester tester,
    FakeDeckRepository repository,
  ) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(deckRepository: repository),
        routes: decksRoutes(),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('архив колоды показывает NcToast с «Отменить»', (
    WidgetTester tester,
  ) async {
    final FakeDeckRepository repository = FakeDeckRepository(
      summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
    );
    await pumpDecks(tester, repository);
    final l10n = l10nOf(tester);

    await tester.drag(
      find.byKey(const ValueKey<String>('deck-card-deck-1')),
      const Offset(-600, 0),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(NcToast),
      findsOneWidget,
      reason: 'Тост приложения — NcToast, а не M3ESnackbar',
    );
    expect(find.text(l10n.deckArchivedMessage), findsOneWidget);
    expect(find.text(l10n.undo), findsOneWidget);

    await tester.tap(find.text(l10n.undo));
    await tester.pumpAndSettle();
    expect(repository.unarchivedIds, <String>['deck-1']);
  });

  testWidgets('ошибка экспорта показывает NcToast', (
    WidgetTester tester,
  ) async {
    final FakeDeckRepository repository = FakeDeckRepository(
      summaries: <DeckSummary>[makeSummary(id: 'deck-1', name: 'Испанский')],
    );
    await pumpDecks(tester, repository);
    final l10n = l10nOf(tester);

    await tester.longPress(find.text('Испанский'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.deckExport));
    await tester.pumpAndSettle();

    expect(find.byType(NcToast), findsOneWidget);
  });
}
