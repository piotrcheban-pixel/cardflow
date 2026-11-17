import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/design/design.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/redesign_screen_fixtures.dart';

/// «Мои колоды» в оформлении Nocturne (REDESIGN-SPEC §9.2).
///
/// Red-тесты шага 3.2: ключи §9, сводка из `deckSummaries`, сетка 1/2/3,
/// бюджет стекла, textScale 2,0, guard — в `legacy_material_guard_test.dart`.
void main() {
  final AppLocalizations l10n = ncL10n;

  Future<void> pumpDecks(
    WidgetTester tester, {
    List<DeckSummary>? summaries,
    Size size = const Size(390, 844),
    bool settle = true,
  }) => pumpNcScreen(
    tester,
    home: const DecksScreen(),
    overrides: ncStage3Overrides(summaries: summaries),
    config: NcScreenConfig(size: size),
    settle: settle,
  );

  testWidgets('ключи §9.2: плитки, split-меню, диалог имени, удаление', (
    WidgetTester tester,
  ) async {
    await pumpDecks(tester);

    expect(
      find.byKey(const ValueKey<String>('decks-create-split')),
      findsOneWidget,
    );
    for (final String id in <String>['deck-bio', 'deck-stat', 'deck-hist']) {
      expect(
        find.byKey(ValueKey<String>('deck-card-$id')),
        findsOneWidget,
        reason: 'Ключ deck-card-$id должен остаться на Dismissible',
      );
    }

    // Меню split-кнопки: пункт «Сгенерировать карточки» с ключом.
    await tester.tap(find.byTooltip(l10n.decksCreateMenuTooltip));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('decks-create-generate')),
      findsOneWidget,
    );
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    // Диалог имени: ключ подтверждения.
    await tester.tap(find.text(l10n.decksCreateDeckFab));
    await tester.pumpAndSettle();
    expect(find.text(l10n.deckCreateDialogTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('deck-name-submit')),
      findsOneWidget,
    );
    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    // Контекстное меню → удаление: ключи подтверждения и отмены.
    await tester.longPress(find.text('Биология'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.delete));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('delete-deck-confirm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('delete-deck-cancel')),
      findsOneWidget,
    );
  });

  testWidgets('импорт: предпросмотр с ключами import-confirm/cancel', (
    WidgetTester tester,
  ) async {
    await pumpNcScreen(
      tester,
      home: const DecksScreen(),
      overrides: ncStage3Overrides(),
    );

    await tester.tap(find.byTooltip(l10n.decksCreateMenuTooltip));
    await tester.pumpAndSettle();
    await tester.tap(find.text(l10n.decksImportZip));
    await tester.pumpAndSettle();

    expect(find.text(l10n.importPreviewTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('import-confirm')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('import-cancel')), findsOneWidget);
  });

  testWidgets('сводка в шапке и бейджи плиток из deckSummaries', (
    WidgetTester tester,
  ) async {
    await pumpDecks(tester);

    // due = 6 + 3 + 0 = 9, колод = 3 (UI-вычисление из фейков).
    expect(find.text(l10n.decksSummary(9, 3)), findsOneWidget);
    expect(find.text(l10n.deckDueCount(6)), findsOneWidget);
    expect(find.text(l10n.deckCardCount(18)), findsOneWidget);
    expect(find.text(l10n.deckCardCount(7)), findsOneWidget);
    // У «Истории искусства» due = 0 — тихая галочка без текста.
    expect(find.text(l10n.deckDueCount(0)), findsNothing);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('поиск и фильтр (ключи тумблеров сохранены)', (
    WidgetTester tester,
  ) async {
    await pumpDecks(tester);

    await tester.tap(find.byKey(const ValueKey<String>('decks-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(NcSearchField), findsOneWidget);
    await tester.enterText(find.byType(NcSearchField), 'биол');
    await tester.pumpAndSettle();
    expect(find.text('Биология'), findsOneWidget);
    expect(find.text('История искусства'), findsNothing);
    await tester.tap(find.byKey(const ValueKey<String>('decks-search-clear')));
    await tester.pumpAndSettle();
    expect(find.text('История искусства'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('decks-search-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(NcSearchField), findsNothing);

    await tester.tap(find.text(l10n.deckFilterDue));
    await tester.pumpAndSettle();
    expect(find.text('Биология'), findsOneWidget);
    expect(find.text('Статистика'), findsWidgets);
    expect(find.text('История искусства'), findsNothing);
  });

  testWidgets('сетка 1 / 2 / 3 колонки на 390 / 800 / 1440', (
    WidgetTester tester,
  ) async {
    Future<List<Offset>> tiles(Size size) async {
      await pumpDecks(tester, size: size);
      final Finder finder = find.byType(NcCardTile);
      expect(finder, findsNWidgets(3));
      return <Offset>[
        for (var index = 0; index < 3; index++)
          tester.getTopLeft(finder.at(index)),
      ];
    }

    final List<Offset> phone = await tiles(const Size(390, 844));
    expect(phone[1].dy, greaterThan(phone[0].dy));

    final List<Offset> tablet = await tiles(const Size(800, 1000));
    expect(tablet[1].dy, tablet[0].dy);
    expect(tablet[2].dy, greaterThan(tablet[1].dy));

    final List<Offset> desktop = await tiles(const Size(1440, 900));
    expect(desktop[1].dy, desktop[0].dy);
    expect(desktop[2].dy, desktop[0].dy);
    expect(desktop[1].dx, greaterThan(desktop[0].dx));
    expect(desktop[2].dx, greaterThan(desktop[1].dx));
  });

  testWidgets('бюджет стекла ≤ 2: в покое без стекла, при прокрутке 1', (
    WidgetTester tester,
  ) async {
    await pumpDecks(tester);
    expectGlassBudget(tester, maxGroups: 2);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.drag(find.byType(NcCardTile).first, const Offset(0, -240));
    await tester.pumpAndSettle();
    expectGlassBudget(tester, maxGroups: 2);
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const DecksScreen(),
      overrides: ncStage3Overrides(),
    );
    expect(find.byType(NcCardTile), findsNWidgets(3));
  });

  testWidgets('пустое состояние: заголовок, текст и две кнопки', (
    WidgetTester tester,
  ) async {
    await pumpDecks(tester, summaries: <DeckSummary>[]);

    expect(find.text(l10n.decksEmptyTitle), findsOneWidget);
    expect(find.text(l10n.decksEmptyMessage), findsOneWidget);
    expect(find.text(l10n.decksCreateButton), findsOneWidget);
    expect(find.text(l10n.decksCreateGenerate), findsOneWidget);
  });

  testWidgets('пустой поиск: «Ничего не найдено» без 3D-иконки', (
    WidgetTester tester,
  ) async {
    await pumpDecks(tester);

    await tester.tap(find.byKey(const ValueKey<String>('decks-search-toggle')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(NcSearchField), 'нет такой');
    await tester.pumpAndSettle();

    expect(find.text(l10n.decksNoResults), findsOneWidget);
    expect(find.byType(NcIcon3D), findsNothing);
  });
}
