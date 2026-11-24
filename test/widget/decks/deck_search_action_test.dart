import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// «Найти колоду» в боковой панели (находка владельца: кнопка не работала).
///
/// Кнопка должна открыть поиск экрана «Колоды», передать фокус полю и
/// фильтровать список сразу при вводе — на десктопе и в мобильном ящике.
void main() {
  List<Override> overrides() {
    return decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(id: 'deck-1', name: 'Испанский'),
          makeSummary(id: 'deck-2', name: 'История'),
          makeSummary(id: 'deck-3', name: 'География'),
        ],
      ),
    );
  }

  Finder searchField() =>
      find.byKey(const ValueKey<String>('decks-search-field'));

  bool fieldHasFocus(WidgetTester tester) =>
      tester.widget<TextField>(searchField()).focusNode?.hasFocus ?? false;

  testWidgets('десктоп: кнопка открывает поиск и отдаёт фокус полю', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: overrides(),
        initialLocation: AppRoutes.decksPath,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('shell-search-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(searchField(), findsOneWidget);
    expect(
      fieldHasFocus(tester),
      isTrue,
      reason: 'пользователь должен сразу печатать запрос',
    );

    // Ввод без тапа по полю — сразу фильтрует список.
    await tester.enterText(searchField(), 'Исп');
    await tester.pumpAndSettle();
    expect(find.text('Испанский'), findsOneWidget);
    expect(find.text('История'), findsNothing);
    expect(find.text('География'), findsNothing);

    // Пустой результат — понятное состояние, а не пустой экран.
    await tester.enterText(searchField(), 'нет такой колоды');
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.decksFilterEmptyHint), findsOneWidget);
  });

  testWidgets('мобильный: поиск из ящика открывается и получает фокус', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: overrides(),
        initialLocation: AppRoutes.decksPath,
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byTooltip(l10n.shellOpenNavTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('shell-search-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpAndSettle();

    expect(searchField(), findsOneWidget);
    expect(fieldHasFocus(tester), isTrue);
    await tester.enterText(searchField(), 'Исп');
    await tester.pumpAndSettle();
    expect(find.text('Испанский'), findsOneWidget);
  });
}
