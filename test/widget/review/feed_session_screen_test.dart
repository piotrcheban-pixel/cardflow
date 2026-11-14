import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/feed_progress_bar.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Красная фаза итерации 4: экран «Лента» (SPEC A7.3, ADR-016) — PageView,
/// жесты/пороги, Stories-прогресс, авто-продвижение, пауза, haptics, undo.
void main() {
  late FakeReviewRepository reviews;
  late FakeCardRepository cards;

  List<Override> overridesFor(
    List<Card> deckCards, {
    FakeDeckRepository? decks,
  }) {
    cards = FakeCardRepository(cards: deckCards);
    reviews = FakeReviewRepository();
    return decksOverrides(
      deckRepository:
          decks ??
          FakeDeckRepository(
            summaries: <DeckSummary>[
              makeSummary(
                id: 'deck-1',
                name: 'Испанский',
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
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrides,
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/feed',
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pump(const Duration(milliseconds: 20));
  }

  List<Card> twoCards({String? sourceExcerpt}) => <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Первый вопрос',
      back: 'Первый ответ',
      createdAt: DateTime.utc(2026, 11, 14, 10),
      sourceExcerpt: sourceExcerpt,
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-1',
      front: 'Второй вопрос',
      back: 'Второй ответ',
      createdAt: DateTime.utc(2026, 11, 14, 10, 1),
    ),
  ];

  List<Card> manyCards(int count) => <Card>[
    for (int index = 0; index < count; index++)
      makeCard(
        id: 'card-${index + 1}',
        deckId: 'deck-1',
        front: 'Вопрос ${index + 1}',
        back: 'Ответ ${index + 1}',
        createdAt: DateTime.utc(2026, 11, 14, 10, index),
      ),
  ];

  final ValueKey<String> firstCardKey = const ValueKey<String>(
    'feed-card-card-1',
  );

  Future<void> pumpAfterGesture(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 450));
  }

  testWidgets('каркас: Stories, карточка, колода, счётчик, пауза', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(FeedSessionScreen), findsOneWidget);
    expect(find.byType(FeedProgressBar), findsOneWidget);
    expect(find.byType(FeedCardView), findsWidgets);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Первый ответ'), findsNothing, reason: 'ответ скрыт');
    expect(find.text('Испанский'), findsOneWidget);
    expect(find.text(l10n.feedCounter(1, 2)), findsOneWidget);
    expect(find.text(l10n.feedPause), findsOneWidget);
    expect(find.text(l10n.feedSeconds(5)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('feed-progress-segment-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('feed-progress-segment-1')),
      findsOneWidget,
    );
  });

  testWidgets('тап раскрывает и скрывает ответ', (WidgetTester tester) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text('Первый вопрос'), findsNothing);

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Первый ответ'), findsNothing);
  });

  testWidgets('вертикальный свайп листает без оценки', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.fling(
      find.byKey(const ValueKey<String>('feed-page-view')),
      const Offset(0, -500),
      1200,
    );
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text('Второй вопрос'), findsOneWidget);
    expect(find.text('Первый вопрос'), findsNothing);
    expect(find.text(l10n.feedCounter(2, 2)), findsOneWidget);
    expect(reviews.ratings, isEmpty, reason: 'листание не засчитывается');
  });

  testWidgets('свайп вправо — «Знаю», mode=feed', (WidgetTester tester) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));
    reviews.previousCard = deckCards.first;

    await tester.fling(find.byKey(firstCardKey), const Offset(140, 0), 1200);
    await pumpAfterGesture(tester);

    expect(reviews.ratings, <Rating>[Rating.good]);
    expect(reviews.cardIds, <String>['card-1']);
    expect(reviews.modes, <String>['feed']);
    expect(find.text('Второй вопрос'), findsOneWidget);
  });

  testWidgets('свайп влево — «Не знаю»', (WidgetTester tester) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));
    reviews.previousCard = deckCards.first;

    await tester.fling(find.byKey(firstCardKey), const Offset(-140, 0), 1200);
    await pumpAfterGesture(tester);

    expect(reviews.ratings, <Rating>[Rating.again]);
    expect(reviews.modes, <String>['feed']);
  });

  testWidgets('долгий свайп вправо — «Легко», влево — «Сложно»', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = manyCards(3);
    await pumpFeed(tester, overrides: overridesFor(deckCards));

    reviews.previousCard = deckCards[0];
    await tester.timedDrag(
      find.byKey(firstCardKey),
      const Offset(600, 0),
      const Duration(milliseconds: 600),
    );
    await pumpAfterGesture(tester);
    expect(reviews.ratings, <Rating>[Rating.easy]);

    reviews.previousCard = deckCards[1];
    await tester.timedDrag(
      find.byKey(const ValueKey<String>('feed-card-card-2')),
      const Offset(-600, 0),
      const Duration(milliseconds: 600),
    );
    await pumpAfterGesture(tester);
    expect(reviews.ratings, <Rating>[Rating.easy, Rating.hard]);
  });

  testWidgets('короткий медленный свайп возвращает карточку пружиной', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));

    await tester.timedDrag(
      find.byKey(firstCardKey),
      const Offset(120, 0),
      const Duration(seconds: 1),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(reviews.ratings, isEmpty);
    expect(find.text('Первый вопрос'), findsOneWidget);
    final Transform transform = tester.widget<Transform>(
      find.descendant(
        of: find.byKey(firstCardKey),
        matching: find.byKey(const ValueKey<String>('feed-swipe-transform')),
      ),
    );
    expect(transform.transform.getTranslation().x, closeTo(0, 0.5));
  });

  testWidgets('Stories: оценённый сегмент заполнен, текущий пульсирует', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));

    Opacity pulse() => tester.widget<Opacity>(
      find.byKey(const ValueKey<String>('feed-progress-pulse')),
    );
    final double firstOpacity = pulse().opacity;
    await tester.pump(const Duration(milliseconds: 300));
    final double secondOpacity = pulse().opacity;
    expect(
      (firstOpacity - secondOpacity).abs(),
      greaterThan(0.01),
      reason: 'текущий сегмент должен пульсировать',
    );

    reviews.previousCard = deckCards.first;
    await tester.fling(find.byKey(firstCardKey), const Offset(140, 0), 1200);
    await pumpAfterGesture(tester);

    final Container segment = tester.widget<Container>(
      find.byKey(const ValueKey<String>('feed-progress-segment-0')),
    );
    final Color color = (segment.decoration! as BoxDecoration).color!;
    final ColorScheme scheme = Theme.of(
      tester.element(find.byType(FeedProgressBar)),
    ).colorScheme;
    expect(color, scheme.primary, reason: 'оценённый сегмент заполнен');
  });

  testWidgets('авто-продвижение 3 с перелистывает без оценки', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('feed-auto-advance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.feedSeconds(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Второй вопрос'), findsOneWidget);
    expect(reviews.ratings, isEmpty, reason: 'авто-продвижение не оценивает');
    expect(find.text(l10n.feedCounter(2, 2)), findsOneWidget);
  });

  testWidgets('авто-продвижение не идёт без раскрытия', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('feed-auto-advance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.feedSeconds(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 4));

    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text(l10n.feedCounter(1, 2)), findsOneWidget);
  });

  testWidgets('«Пауза» останавливает таймер, «Продолжить» возобновляет', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('feed-auto-advance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.feedSeconds(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey<String>('feed-pause')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l10n.feedResume), findsOneWidget);

    await tester.pump(const Duration(seconds: 4));
    expect(
      find.text('Первый ответ'),
      findsOneWidget,
      reason: 'пауза держит раскрытую карточку на месте',
    );

    await tester.tap(find.byKey(const ValueKey<String>('feed-pause')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text(l10n.feedPause), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Второй вопрос'), findsOneWidget);
  });

  testWidgets('оценки дают haptics A7.2, завершение — mediumImpact', (
    WidgetTester tester,
  ) async {
    final List<Object?> haptics = <Object?>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (MethodCall call) async {
        if (call.method == 'HapticFeedback.vibrate') {
          haptics.add(call.arguments);
        }
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        null,
      ),
    );

    final List<Card> deckCards = manyCards(4);
    await pumpFeed(tester, overrides: overridesFor(deckCards));

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    reviews.previousCard = deckCards[0];
    await tester.fling(find.byKey(firstCardKey), const Offset(140, 0), 1200);
    await pumpAfterGesture(tester);

    reviews.previousCard = deckCards[1];
    await tester.timedDrag(
      find.byKey(const ValueKey<String>('feed-card-card-2')),
      const Offset(600, 0),
      const Duration(milliseconds: 600),
    );
    await pumpAfterGesture(tester);

    reviews.previousCard = deckCards[2];
    await tester.fling(
      find.byKey(const ValueKey<String>('feed-card-card-3')),
      const Offset(-140, 0),
      1200,
    );
    await pumpAfterGesture(tester);

    reviews.previousCard = deckCards[3];
    await tester.timedDrag(
      find.byKey(const ValueKey<String>('feed-card-card-4')),
      const Offset(-600, 0),
      const Duration(milliseconds: 600),
    );
    await pumpAfterGesture(tester);

    expect(haptics, <Object?>[
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
    ]);
  });

  testWidgets('undo возвращает оценённую карточку раскрытой', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));
    reviews.previousCard = deckCards.first;

    await tester.fling(find.byKey(firstCardKey), const Offset(140, 0), 1200);
    await pumpAfterGesture(tester);
    expect(find.text('Второй вопрос'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('review-undo')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(seconds: 1));

    expect(reviews.undone, hasLength(1));
    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text('Второй вопрос'), findsNothing);
  });

  testWidgets('ошибка записи: сообщение ARB, карточка остаётся', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));
    reviews
      ..previousCard = deckCards.first
      ..recordError = StateError('БД недоступна');
    final AppLocalizations l10n = l10nOf(tester);

    await tester.fling(find.byKey(firstCardKey), const Offset(140, 0), 1200);
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.text(l10n.reviewSaveError), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.textContaining('БД недоступна'), findsNothing);
    expect(reviews.ratings, isEmpty);
  });

  testWidgets('форма карточки: 28 в покое → 16 при свайпе (A4.3)', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));

    BorderRadius radius() {
      final Material material = tester.widget<Material>(
        find
            .descendant(
              of: find.byKey(firstCardKey),
              matching: find.byType(Material),
            )
            .first,
      );
      return (material.shape! as RoundedRectangleBorder).borderRadius.resolve(
        TextDirection.ltr,
      );
    }

    expect(radius().topLeft.x, 28);
    final TestGesture gesture = await tester.startGesture(
      tester.getCenter(find.byKey(firstCardKey)),
    );
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    await gesture.moveBy(const Offset(100, 0));
    await tester.pump();
    expect(radius().topLeft.x, lessThan(28));
    expect(radius().topLeft.x, greaterThanOrEqualTo(16));

    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(radius().topLeft.x, closeTo(28, 1));
  });

  testWidgets('клавиши: Space раскрывает, 3 — «Знаю»', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Первый ответ'), findsOneWidget);

    reviews.previousCard = deckCards.first;
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await pumpAfterGesture(tester);
    expect(reviews.ratings, <Rating>[Rating.good]);
  });

  testWidgets('Stories: семантическая подпись прогресса на русском', (
    WidgetTester tester,
  ) async {
    final SemanticsHandle handle = tester.ensureSemantics();
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    expect(
      tester.getSemantics(find.byType(FeedProgressBar)).label,
      l10n.feedProgressSemantics(0, 2),
    );
    handle.dispose();
  });

  testWidgets('завершение: все оценены — итоговый экран', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    await pumpFeed(tester, overrides: overridesFor(deckCards));
    final AppLocalizations l10n = l10nOf(tester);

    reviews.previousCard = deckCards.first;
    await tester.fling(find.byKey(firstCardKey), const Offset(140, 0), 1200);
    await pumpAfterGesture(tester);

    reviews.previousCard = deckCards.last;
    await tester.fling(
      find.byKey(const ValueKey<String>('feed-card-card-2')),
      const Offset(140, 0),
      1200,
    );
    await pumpAfterGesture(tester);

    expect(find.text(l10n.reviewCompletedTitle), findsOneWidget);
    expect(find.text(l10n.reviewCompletedMessage(2)), findsOneWidget);
    expect(find.text(l10n.reviewDone), findsOneWidget);
  });

  testWidgets('пустая очередь — пустое состояние', (WidgetTester tester) async {
    await pumpFeed(tester, overrides: overridesFor(const <Card>[]));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewEmptyTitle), findsOneWidget);
    expect(find.text(l10n.reviewBack), findsOneWidget);
  });

  testWidgets('ошибка загрузки — ARB и «Повторить»', (
    WidgetTester tester,
  ) async {
    final List<Override> overrides = overridesFor(twoCards());
    cards.cardsByDeckError = StateError('boom');
    await pumpFeed(tester, overrides: overrides);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewLoadError), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    cards.cardsByDeckError = null;
    await tester.tap(find.widgetWithText(TextButton, l10n.retry));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  testWidgets('«Почему?»: цитата и неактивность без неё', (
    WidgetTester tester,
  ) async {
    await pumpFeed(
      tester,
      overrides: overridesFor(
        twoCards(sourceExcerpt: 'Париж — столица Франции.'),
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-why')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.reviewWhySheetTitle), findsOneWidget);
    expect(find.text('Париж — столица Франции.'), findsOneWidget);
  });

  testWidgets('фон приложения останавливает авто-продвижение', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('feed-auto-advance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.feedSeconds(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Первый ответ'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Второй вопрос'), findsOneWidget);
  });

  testWidgets('«Почему?» останавливает авто-продвижение', (
    WidgetTester tester,
  ) async {
    await pumpFeed(
      tester,
      overrides: overridesFor(
        twoCards(sourceExcerpt: 'Париж — столица Франции.'),
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('feed-auto-advance')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.text(l10n.feedSeconds(3)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(firstCardKey));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tap(find.byKey(const ValueKey<String>('review-why')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text(l10n.feedCounter(1, 2)), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Первый ответ'), findsOneWidget);
  });

  testWidgets('«Почему?» неактивна без source_excerpt', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));

    final IconButton why = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('review-why')),
    );
    expect(why.onPressed, isNull);
  });

  testWidgets('выход: диалог, «Продолжить» остаётся в ленте', (
    WidgetTester tester,
  ) async {
    await pumpFeed(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-close')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text(l10n.reviewExitDialogTitle), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('review-exit-cancel')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(FeedSessionScreen), findsOneWidget);
  });
}
