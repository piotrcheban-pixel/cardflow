import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/design/design.dart';

import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/redesign_screen_fixtures.dart';

/// Экран колоды в оформлении Nocturne (REDESIGN-SPEC §9.3).
///
/// Red-тесты шага 3.3: ключи, стат-пилюли, сетка режимов 2×4/4×2, парящий
/// тулбар, бюджет стекла, textScale 2,0, Hero-переход из списка колод.
void main() {
  final AppLocalizations l10n = ncL10n;

  Future<void> pumpDeck(
    WidgetTester tester, {
    Size size = const Size(390, 844),
    List<Card>? cards,
  }) => pumpNcScreen(
    tester,
    home: const DeckScreen(deckId: 'deck-bio'),
    overrides: ncStage3Overrides(cards: cards),
    config: NcScreenConfig(size: size),
  );

  GoRouter deckRouter({String initial = '/decks/deck-bio'}) => GoRouter(
    initialLocation: initial,
    routes: <RouteBase>[
      GoRoute(
        path: '/decks/:id',
        builder: (BuildContext context, GoRouterState state) =>
            DeckScreen(deckId: state.pathParameters['id']!),
      ),
      for (final String mode in <String>[
        'study',
        'practice',
        'test',
        'typing',
        'match',
        'true-false',
      ])
        GoRoute(
          path: '/decks/:id/$mode',
          builder: (BuildContext context, GoRouterState state) =>
              Scaffold(body: Text('DEST-$mode')),
        ),
      GoRoute(
        path: '/constructor',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('DEST-constructor')),
      ),
      GoRoute(
        path: '/decks/:id/generate',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('DEST-generate')),
      ),
      GoRoute(
        path: '/decks/:id/cards/new',
        builder: (BuildContext context, GoRouterState state) =>
            const Scaffold(body: Text('DEST-card-new')),
      ),
    ],
  );

  testWidgets('ключи §9.3, стат-пилюли и секция карточек', (
    WidgetTester tester,
  ) async {
    await pumpDeck(tester);

    expect(
      find.byKey(const ValueKey<String>('deck-start-session')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('deck-overflow-menu')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('deck-add-card')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('deck-generate-action')),
      findsOneWidget,
    );
    expect(find.text(l10n.deckDueCount(6)), findsWidgets);
    expect(find.text(l10n.deckNewCount(4)), findsOneWidget);
    expect(find.text(l10n.deckInProgressCount(5)), findsOneWidget);
    expect(find.text(l10n.deckCardsSection(6)), findsOneWidget);
    expect(find.byType(NcListRow), findsNWidgets(6));

    // Hero-теги аватара и названия для перехода из списка колод.
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Hero && widget.tag == 'deck-avatar-deck-bio',
      ),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Hero && widget.tag == 'deck-title-deck-bio',
      ),
      findsOneWidget,
    );
  });

  testWidgets('лист режимов: заголовок и восемь ключей', (
    WidgetTester tester,
  ) async {
    await pumpDeck(tester);
    await tester.tap(find.byKey(const ValueKey<String>('deck-start-session')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewModeSheetTitle), findsOneWidget);
    for (final String mode in <String>[
      'classic',
      'feed',
      'test',
      'typing',
      'match',
      'true-false',
      'practice',
      'constructor',
    ]) {
      expect(
        find.byKey(ValueKey<String>('review-mode-$mode')),
        findsOneWidget,
        reason: 'Ключ review-mode-$mode должен остаться на плитке',
      );
    }
    expect(find.text(l10n.reviewModeClassic), findsWidgets);
    expect(find.text(l10n.reviewModePractice), findsWidgets);
  });

  testWidgets('сетка режимов: 2 колонки на 390, 4 на 1440', (
    WidgetTester tester,
  ) async {
    Future<void> open(Size size) async {
      await pumpDeck(tester, size: size);
      await tester.tap(
        find.byKey(const ValueKey<String>('deck-start-session')),
      );
      await tester.pumpAndSettle();
    }

    await open(const Size(390, 844));
    Offset tile(String mode) =>
        tester.getTopLeft(find.byKey(ValueKey<String>('review-mode-$mode')));
    expect(tile('classic').dy, tile('feed').dy);
    expect(tile('test').dy, greaterThan(tile('classic').dy));

    Navigator.of(tester.element(find.byType(DeckScreen))).pop();
    await tester.pumpAndSettle();
    await open(const Size(1440, 900));
    expect(tile('typing').dy, tile('classic').dy);
    expect(tile('match').dy, greaterThan(tile('typing').dy));
  });

  testWidgets('режим открывает тот же маршрут (classic/practice/constructor)', (
    WidgetTester tester,
  ) async {
    final GoRouter router = deckRouter();
    addTearDown(router.dispose);
    await pumpNcScreen(tester, router: router, overrides: ncStage3Overrides());

    await tester.tap(find.byKey(const ValueKey<String>('deck-start-session')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('review-mode-classic')));
    await tester.pumpAndSettle();
    expect(find.text('DEST-study'), findsOneWidget);
  });

  testWidgets('тулбар: «Добавить» и «Сгенерировать» вызывают прежние пути', (
    WidgetTester tester,
  ) async {
    final GoRouter router = deckRouter();
    addTearDown(router.dispose);
    await pumpNcScreen(tester, router: router, overrides: ncStage3Overrides());

    await tester.tap(
      find.byKey(const ValueKey<String>('deck-generate-action')),
    );
    await tester.pumpAndSettle();
    expect(find.text('DEST-generate'), findsOneWidget);

    router.pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('deck-add-card')));
    await tester.pumpAndSettle();
    expect(find.text('DEST-card-new'), findsOneWidget);
  });

  testWidgets('бюджет стекла ≤ 2 и стекло есть (покой и прокрутка)', (
    WidgetTester tester,
  ) async {
    await pumpDeck(tester);
    expectGlassBudget(tester, maxGroups: 2);
    expect(find.byType(BackdropFilter), findsWidgets);

    await tester.drag(find.byType(NcListRow).first, const Offset(0, -300));
    await tester.pumpAndSettle();
    expectGlassBudget(tester, maxGroups: 2);
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const DeckScreen(deckId: 'deck-bio'),
      overrides: ncStage3Overrides(),
    );
    expect(find.byType(NcListRow), findsWidgets);
  });

  testWidgets('пустая колода: NcEmptyState с двумя действиями', (
    WidgetTester tester,
  ) async {
    await pumpDeck(tester, cards: <Card>[]);

    expect(find.text(l10n.deckCardsEmpty), findsOneWidget);
    expect(find.text(l10n.deckCardsEmptyHint), findsOneWidget);
    expect(find.text(l10n.deckAddCardTooltip), findsOneWidget);
    expect(find.text(l10n.decksCreateGenerate), findsOneWidget);
  });

  testWidgets('Hero-переход из списка колод в экран колоды', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/',
      routes: decksRoutes(),
    );
    addTearDown(router.dispose);
    await pumpNcScreen(tester, router: router, overrides: ncStage3Overrides());

    await tester.tap(find.text('Биология'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.byType(DeckScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(
      find.byWidgetPredicate(
        (Widget widget) =>
            widget is Hero && widget.tag == 'deck-avatar-deck-bio',
      ),
      findsWidgets,
    );
  });
}
