import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/feed_progress_bar.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Режим «Лента» — свободный просмотр (ADR-044).
///
/// Ключевые инварианты: одна карточка на страницу, вертикальный свайп/колесо/
/// клавиши сразу переключают карточку, ответ раскрывается тапом, оценок и
/// записи в журнал повторений нет.
void main() {
  late FakeReviewRepository reviews;

  List<Override> overridesFor(List<Card> deckCards) {
    final FakeCardRepository cards = FakeCardRepository(cards: deckCards);
    reviews = FakeReviewRepository();
    return decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Электротехника',
            totalCards: deckCards.length,
            newCards: deckCards.length,
          ),
        ],
      ),
      cardRepository: cards,
      reviewRepository: reviews,
    );
  }

  Future<void> pumpFeed(
    WidgetTester tester, {
    required List<Card> cards,
  }) async {
    tester.view.physicalSize = const Size(1280, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      appWithRouter(
        overrides: overridesFor(cards),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/feed',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    await tester.pumpAndSettle();
  }

  List<Card> cards(int count) => <Card>[
    for (int index = 0; index < count; index++)
      makeCard(
        id: 'card-${index + 1}',
        deckId: 'deck-1',
        front: 'Вопрос ${index + 1}',
        back: 'Ответ ${index + 1}',
        createdAt: DateTime.utc(2026, 11, 14, 10, index),
      ),
  ];

  final Finder pageView = find.byKey(const ValueKey<String>('feed-page-view'));

  Future<void> flingUp(WidgetTester tester) async {
    await tester.fling(pageView, const Offset(0, -500), 1400);
    await tester.pumpAndSettle();
  }

  Future<void> flingDown(WidgetTester tester) async {
    await tester.fling(pageView, const Offset(0, 500), 1400);
    await tester.pumpAndSettle();
  }

  Future<void> wheel(WidgetTester tester, double dy) async {
    final TestPointer pointer = TestPointer(1, PointerDeviceKind.mouse);
    final Offset center = tester.getCenter(pageView);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(Offset(0, dy)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpAndSettle();
  }

  testWidgets('каркас: одна карточка, прогресс, бейдж просмотра; без оценок', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(2));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(FeedSessionScreen), findsOneWidget);
    expect(find.byType(PageView), findsOneWidget);
    expect(find.byType(FeedProgressBar), findsOneWidget);
    expect(find.byType(FeedCardView), findsWidgets);
    expect(find.text('Вопрос 1'), findsOneWidget);
    expect(find.text('Ответ 1'), findsNothing);
    expect(find.text(l10n.feedBrowseBadge), findsOneWidget);
    expect(find.text(l10n.reviewCardCounter(1, 2)), findsOneWidget);
    // В ленте нет ни одной кнопки оценки, интервалов и техн. бейджа FSRS.
    for (final String rating in <String>['again', 'hard', 'good', 'easy']) {
      expect(
        find.byKey(ValueKey<String>('review-rating-$rating')),
        findsNothing,
      );
    }
    expect(find.text(l10n.reviewIntervalMinutes(1)), findsNothing);
    expect(find.text(l10n.reviewFsrsBadge), findsNothing);
    expect(find.byIcon(Icons.pause), findsNothing);
    expect(find.byIcon(Icons.timer_outlined), findsNothing);
    expect(reviews.ratings, isEmpty);
  });

  testWidgets('свайп вверх — сразу следующая карточка, без докрутки', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(3));
    final AppLocalizations l10n = l10nOf(tester);

    await flingUp(tester);

    expect(find.text('Вопрос 2'), findsOneWidget);
    expect(find.text('Вопрос 1'), findsNothing);
    expect(find.text(l10n.reviewCardCounter(2, 3)), findsOneWidget);
    expect(reviews.ratings, isEmpty, reason: 'листание не оценивает');
  });

  testWidgets('свайп вниз возвращает предыдущую карточку', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(3));
    await flingUp(tester);
    await flingDown(tester);
    expect(find.text('Вопрос 1'), findsOneWidget);
  });

  testWidgets('быстрые повторные свайпы не оставляют пустой экран', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(4));
    await tester.fling(pageView, const Offset(0, -500), 1600);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.fling(pageView, const Offset(0, -500), 1600);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pumpAndSettle();

    // Карточка на экране есть всегда, счётчик не «проваливается» в пустоту.
    expect(find.byType(FeedCardView), findsWidgets);
    expect(
      find.descendant(
        of: find.byType(FeedSessionScreen),
        matching: find.textContaining('Вопрос'),
      ),
      findsWidgets,
    );
    expect(reviews.ratings, isEmpty);
  });

  testWidgets('тап раскрывает и скрывает ответ; раскрытие переживает переход', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(2));

    await tester.tap(find.text('Вопрос 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ответ 1'), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('feed-nav-hint')), findsOneWidget);

    await flingUp(tester);
    await flingDown(tester);
    expect(
      find.text('Ответ 1'),
      findsOneWidget,
      reason: 'ответ остался раскрыт',
    );

    await tester.tap(find.text('Ответ 1'));
    await tester.pumpAndSettle();
    expect(find.text('Ответ 1'), findsNothing);
  });

  testWidgets('клавиатура: вниз/вверх/Home/End/пробел', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(3));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 3'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 2'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.home);
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 1'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Ответ 1'), findsOneWidget);
  });

  testWidgets('колесо мыши переключает карточки без повторной прокрутки', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(3));

    await wheel(tester, 120);
    expect(find.text('Вопрос 2'), findsOneWidget);

    await wheel(tester, -120);
    expect(find.text('Вопрос 1'), findsOneWidget);
  });

  testWidgets(
    'края: на первой карточке «вверх» недоступна, на последней «вниз»',
    (WidgetTester tester) async {
      await pumpFeed(tester, cards: cards(2));

      expect(
        tester
            .widget<IconButton>(
              find.byKey(const ValueKey<String>('feed-previous')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey<String>('feed-next')))
            .onPressed,
        isNotNull,
      );

      await flingUp(tester);
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey<String>('feed-next')))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets('одна карточка: лента не ломается и не показывает пустоту', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(1));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text('Вопрос 1'), findsOneWidget);
    expect(find.text(l10n.reviewCardCounter(1, 1)), findsOneWidget);
    await flingUp(tester);
    expect(find.text('Вопрос 1'), findsOneWidget);
  });

  testWidgets('пустая колода: понятное пустое состояние без оценок', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: const <Card>[]);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.feedEmptyTitle), findsOneWidget);
    expect(find.text(l10n.feedEmptyMessage), findsOneWidget);
    expect(find.byType(FeedCardView), findsNothing);
  });

  testWidgets('длинная колода: прогресс ограничен 24 сегментами', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(40));
    final AppLocalizations l10n = l10nOf(tester);

    expect(
      find.byKey(const ValueKey<String>('feed-progress-segment-23')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('feed-progress-segment-24')),
      findsNothing,
    );
    expect(find.text(l10n.reviewCardCounter(1, 40)), findsOneWidget);
  });

  testWidgets('карточка без ответа: раскрытие не ломает ленту', (
    WidgetTester tester,
  ) async {
    final List<Card> deck = <Card>[
      makeCard(
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Только вопрос',
        back: '',
        createdAt: DateTime.utc(2026, 11, 14, 10),
      ),
    ];
    await pumpFeed(tester, cards: deck);

    await tester.tap(find.text('Только вопрос'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('feed-nav-hint')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('рейка навигации: клик вниз/вверх листает карточки', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(3));

    await tester.tap(find.byKey(const ValueKey<String>('feed-next')));
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 2'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('feed-previous')));
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 1'), findsOneWidget);
  });

  testWidgets('изменение размера окна не ломает ленту', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, cards: cards(3));

    tester.view.physicalSize = const Size(760, 600);
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 1'), findsOneWidget);
    expect(tester.takeException(), isNull);

    tester.view.physicalSize = const Size(1280, 900);
    await tester.pumpAndSettle();
    expect(find.text('Вопрос 1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
