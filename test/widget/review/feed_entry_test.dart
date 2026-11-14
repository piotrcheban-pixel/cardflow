import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';
import 'package:cardflow/ui/router/app_router.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Красная фаза итерации 4: вход в ленту из листа режимов (SPEC A6.3) и
/// production-маршрут `/decks/:deckId/feed` (A7.3).
void main() {
  List<Override> overridesFor(List<Card> cards) {
    return decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: cards.length,
            newCards: cards.length,
          ),
        ],
      ),
      cardRepository: FakeCardRepository(cards: cards),
      reviewRepository: FakeReviewRepository(),
    );
  }

  List<Card> twoCards() => <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Первый вопрос',
      back: 'Первый ответ',
      createdAt: DateTime.utc(2026, 11, 14, 10),
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-1',
      front: 'Второй вопрос',
      back: 'Второй ответ',
      createdAt: DateTime.utc(2026, 11, 14, 10, 1),
    ),
  ];

  testWidgets('лист режимов содержит «Ленту» и открывает её', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overridesFor(twoCards()),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1',
      ),
    );
    await tester.pumpAndSettle();
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(DeckScreen), findsOneWidget);
    await tester.tap(find.text(l10n.reviewStartSession));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewSessionModeTitle), findsOneWidget);
    expect(find.text(l10n.reviewModeClassic), findsOneWidget);
    expect(find.text(l10n.reviewModeFeed), findsOneWidget);

    await tester.tap(find.text(l10n.reviewModeFeed));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(FeedSessionScreen), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  testWidgets('production-роутер открывает ленту по /decks/:deckId/feed', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(twoCards()),
        child: CardFlowApp(
          router: createAppRouter(
            initialLocation: AppRoutes.feedPath('deck-1'),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(FeedSessionScreen), findsOneWidget);
    expect(find.text('Испанский'), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  test('AppRoutes.feedPath — `/decks/:deckId/feed`', () {
    expect(AppRoutes.feed, 'feed');
    expect(AppRoutes.feedPath('deck-1'), '/decks/deck-1/feed');
  });
}
