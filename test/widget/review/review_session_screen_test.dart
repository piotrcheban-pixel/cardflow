import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Красная фаза итерации 2: экран классической сессии (SPEC A6.4, A7.2) —
/// прогресс, flip-карточка, 4 кнопки с прогнозом, клавиши, undo, «Почему?»,
/// выход и завершение.
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

  Future<void> pumpSession(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrides,
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/study',
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Card> twoCards({String? sourceExcerpt}) => <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Первый вопрос',
      back: 'Первый ответ',
      createdAt: DateTime.utc(2026, 11, 13, 10),
      sourceExcerpt: sourceExcerpt,
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-1',
      front: 'Второй вопрос',
      back: 'Второй ответ',
      createdAt: DateTime.utc(2026, 11, 13, 10, 1),
    ),
  ];

  testWidgets('каркас: прогресс, первая карточка и 4 кнопки с прогнозом', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(ReviewSessionScreen), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Первый ответ'), findsNothing, reason: 'ответ скрыт');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text(l10n.ratingAgain), findsOneWidget);
    expect(find.text(l10n.ratingHard), findsOneWidget);
    expect(find.text(l10n.ratingGood), findsOneWidget);
    expect(find.text(l10n.ratingEasy), findsOneWidget);
    expect(find.text(l10n.reviewIntervalMinutes(1)), findsOneWidget);
    expect(find.text(l10n.reviewIntervalMinutes(6)), findsOneWidget);
    expect(find.text(l10n.reviewIntervalMinutes(10)), findsOneWidget);
    expect(find.text(l10n.reviewIntervalDays(16)), findsOneWidget);
  });

  testWidgets('тап по карточке раскрывает ответ', (WidgetTester tester) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));

    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();

    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text('Первый вопрос'), findsNothing);
  });

  testWidgets('пробел раскрывает ответ, клавиши 1–4 дают оценки', (
    WidgetTester tester,
  ) async {
    final deckCards = <Card>[
      makeCard(id: 'k1', deckId: 'deck-1', front: 'К1'),
      makeCard(
        id: 'k2',
        deckId: 'deck-1',
        front: 'К2',
        createdAt: DateTime.utc(2026, 11, 13, 10, 1),
      ),
      makeCard(
        id: 'k3',
        deckId: 'deck-1',
        front: 'К3',
        createdAt: DateTime.utc(2026, 11, 13, 10, 2),
      ),
      makeCard(
        id: 'k4',
        deckId: 'deck-1',
        front: 'К4',
        createdAt: DateTime.utc(2026, 11, 13, 10, 3),
      ),
    ];
    await pumpSession(tester, overrides: overridesFor(deckCards));

    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.text('Ответ'), findsOneWidget);

    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      reviews.previousCard = deckCards.first;
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(reviews.ratings, <Rating>[
      Rating.again,
      Rating.hard,
      Rating.good,
      Rating.easy,
    ]);
  });

  testWidgets('кнопка «Знаю» пишет оценку и переходит к следующей', (
    WidgetTester tester,
  ) async {
    final deckCards = twoCards();
    await pumpSession(tester, overrides: overridesFor(deckCards));
    reviews.previousCard = deckCards.first;
    final AppLocalizations l10n = l10nOf(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();

    expect(reviews.ratings, <Rating>[Rating.good]);
    expect(reviews.cardIds, <String>['card-1']);
    expect(reviews.modes.single, 'classic');
    expect(find.text('Второй вопрос'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(l10n.reviewTitle, isNotEmpty);
  });

  testWidgets('undo откатывает последнюю оценку и возвращает карточку', (
    WidgetTester tester,
  ) async {
    final deckCards = twoCards();
    await pumpSession(tester, overrides: overridesFor(deckCards));
    reviews.previousCard = deckCards.first;
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();
    expect(find.text('Второй вопрос'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('review-undo')));
    await tester.pumpAndSettle();

    expect(reviews.undone, hasLength(1));
    expect(find.text('Первый ответ'), findsOneWidget);
  });

  testWidgets('ошибка записи оценки — сообщение из ARB, карточка на месте', (
    WidgetTester tester,
  ) async {
    final deckCards = twoCards();
    await pumpSession(tester, overrides: overridesFor(deckCards));
    reviews
      ..previousCard = deckCards.first
      ..recordError = StateError('БД недоступна');
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewSaveError), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.textContaining('БД недоступна'), findsNothing);
  });

  testWidgets('завершение сессии: итог и кнопка «Готово»', (
    WidgetTester tester,
  ) async {
    final deckCards = twoCards();
    await pumpSession(tester, overrides: overridesFor(deckCards));
    final AppLocalizations l10n = l10nOf(tester);

    reviews.previousCard = deckCards.first;
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();
    reviews.previousCard = deckCards.last;
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewCompletedTitle), findsOneWidget);
    expect(find.text(l10n.reviewCompletedMessage(2)), findsOneWidget);
    expect(find.text(l10n.reviewDone), findsOneWidget);
  });

  testWidgets('пустая очередь — пустое состояние с кнопкой «Назад»', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(const <Card>[]));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewEmptyTitle), findsOneWidget);
    expect(find.text(l10n.reviewEmptyMessage), findsOneWidget);
    expect(find.text(l10n.reviewBack), findsOneWidget);
  });

  testWidgets('ошибка загрузки карточек — строка из ARB и «Повторить»', (
    WidgetTester tester,
  ) async {
    final overrides = overridesFor(twoCards());
    cards.cardsByDeckError = StateError('boom');
    await pumpSession(tester, overrides: overrides);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewLoadError), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    cards.cardsByDeckError = null;
    await tester.tap(find.widgetWithText(TextButton, l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  testWidgets('«Почему?» неактивна без source_excerpt', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));

    final IconButton why = tester.widget<IconButton>(
      find.byKey(const ValueKey<String>('review-why')),
    );
    expect(why.onPressed, isNull);
  });

  testWidgets('«Почему?» открывает цитату исходника', (
    WidgetTester tester,
  ) async {
    await pumpSession(
      tester,
      overrides: overridesFor(
        twoCards(sourceExcerpt: 'Париж — столица Франции.'),
      ),
    );
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-why')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewWhySheetTitle), findsOneWidget);
    expect(find.text('Париж — столица Франции.'), findsOneWidget);
  });

  testWidgets('запуск с экрана колоды: режим «Классический» → сессия → выход', (
    WidgetTester tester,
  ) async {
    final deckCards = twoCards();
    await tester.pumpWidget(
      appWithRouter(
        overrides: overridesFor(deckCards),
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

    await tester.tap(find.text(l10n.reviewModeClassic));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewSessionScreen), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('review-close')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.reviewExitDialogTitle), findsOneWidget);
    expect(find.text(l10n.reviewExitDialogMessage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('review-exit-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(DeckScreen), findsOneWidget);
    expect(find.byType(ReviewSessionScreen), findsNothing);
  });

  testWidgets('выход: «Продолжить» оставляет в сессии', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-close')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('review-exit-cancel')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewExitDialogTitle), findsNothing);
    expect(find.byType(ReviewSessionScreen), findsOneWidget);
  });

  group('haptics/дизайн/выход (fix-итерация ревью)', () {
    testWidgets(
      'haptics A4.4/A7.2: reveal, 4 оценки и завершение — через канал',
      (WidgetTester tester) async {
        final harness = tester.binding;
        final List<Object?> haptics = <Object?>[];
        harness.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              haptics.add(call.arguments);
            }
            return null;
          },
        );
        addTearDown(
          () => harness.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          ),
        );
        final deckCards = <Card>[
          makeCard(id: 'c1', deckId: 'deck-1', front: '1'),
          makeCard(
            id: 'c2',
            deckId: 'deck-1',
            front: '2',
            createdAt: DateTime.utc(2026, 11, 13, 10, 1),
          ),
          makeCard(
            id: 'c3',
            deckId: 'deck-1',
            front: '3',
            createdAt: DateTime.utc(2026, 11, 13, 10, 2),
          ),
          makeCard(
            id: 'c4',
            deckId: 'deck-1',
            front: '4',
            createdAt: DateTime.utc(2026, 11, 13, 10, 3),
          ),
        ];
        await pumpSession(tester, overrides: overridesFor(deckCards));
        reviews.previousCard = deckCards[0];

        await tester.tap(find.byKey(const ValueKey<String>('review-card')));
        await tester.pumpAndSettle();
        for (final String name in <String>['again', 'hard', 'good', 'easy']) {
          await tester.tap(find.byKey(ValueKey<String>('review-rating-$name')));
          await tester.pumpAndSettle();
        }

        expect(haptics, <Object?>[
          'HapticFeedbackType.selectionClick',
          'HapticFeedbackType.heavyImpact',
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.lightImpact',
          'HapticFeedbackType.selectionClick',
          'HapticFeedbackType.mediumImpact',
        ]);
      },
    );

    testWidgets('цвета кнопок A7.2 и значение прогресса', (
      WidgetTester tester,
    ) async {
      final deckCards = twoCards();
      await pumpSession(tester, overrides: overridesFor(deckCards));
      final BuildContext context = tester.element(
        find.byType(ReviewSessionScreen),
      );
      final ColorScheme scheme = Theme.of(context).colorScheme;

      Color? background(String name) => tester
          .widget<FilledButton>(
            find.byKey(ValueKey<String>('review-rating-$name')),
          )
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{});
      expect(background('again'), scheme.errorContainer);
      expect(background('hard'), scheme.secondaryContainer);
      expect(background('good'), scheme.primary);
      expect(background('easy'), scheme.tertiaryContainer);

      LinearProgressIndicator progress() =>
          tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
      expect(progress().value, 0);
      reviews.previousCard = deckCards.first;
      await tester.tap(
        find.byKey(const ValueKey<String>('review-rating-good')),
      );
      await tester.pumpAndSettle();
      expect(progress().value, 0.5);
    });

    testWidgets('системный back открывает диалог выхода (M2)', (
      WidgetTester tester,
    ) async {
      final deckCards = twoCards();
      await tester.pumpWidget(
        appWithRouter(
          overrides: overridesFor(deckCards),
          routes: decksRoutes(),
          initialLocation: '/decks/deck-1',
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewModeClassic));
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSessionScreen), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      expect(find.text(l10n.reviewExitDialogTitle), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-cancel')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSessionScreen), findsOneWidget);
    });

    testWidgets('«Почему?» неактивна при пустой цитате (L6)', (
      WidgetTester tester,
    ) async {
      await pumpSession(
        tester,
        overrides: overridesFor(twoCards(sourceExcerpt: '   ')),
      );
      final IconButton why = tester.widget<IconButton>(
        find.byKey(const ValueKey<String>('review-why')),
      );
      expect(why.onPressed, isNull);
    });
  });

  group('план конструктора (SPEC A6.7, ADR-018)', () {
    List<Card> planCards() => <Card>[
      makeCard(
        id: 'p1',
        deckId: 'deck-1',
        front: 'Плановый вопрос',
        state: CardState.review,
        due: DateTime.utc(2026, 12, 1),
      ),
      makeCard(
        id: 'p2',
        deckId: 'deck-1',
        front: 'Второй плановый',
        createdAt: DateTime.utc(2026, 11, 14, 10, 1),
      ),
    ];

    Future<void> pumpPlan(
      WidgetTester tester, {
      required SessionPlan plan,
    }) async {
      await tester.pumpWidget(
        appWithHome(
          overrides: overridesFor(plan.cards),
          home: ReviewSessionScreen(plan: plan),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('порядок плана сохраняется, будущие due не отбрасываются', (
      WidgetTester tester,
    ) async {
      final List<Card> planned = planCards();
      await pumpPlan(tester, plan: SessionPlan(cards: planned));
      // План не ходит в репозиторий карточек: экран работает только с планом.
      cards.cardsByDeckError = StateError('репозиторий не должен вызываться');

      expect(find.byType(ReviewSessionScreen), findsOneWidget);
      expect(find.text('Плановый вопрос'), findsOneWidget);
      expect(find.text('Второй плановый'), findsNothing);
    });

    testWidgets('оценка плановой сессии пишется с mode=classic', (
      WidgetTester tester,
    ) async {
      final List<Card> planned = planCards();
      await pumpPlan(tester, plan: SessionPlan(cards: planned));
      reviews.previousCard = planned.first;

      await tester.tap(
        find.byKey(const ValueKey<String>('review-rating-good')),
      );
      await tester.pumpAndSettle();

      expect(reviews.cardIds, <String>['p1']);
      expect(reviews.modes.single, 'classic');
      expect(find.text('Второй плановый'), findsOneWidget);
    });

    testWidgets('лимит минут: по истечении — итог «Время сессии истекло»', (
      WidgetTester tester,
    ) async {
      final List<Card> planned = planCards();
      await pumpPlan(
        tester,
        plan: SessionPlan(
          cards: planned,
          timeBudget: const Duration(minutes: 1),
        ),
      );
      final AppLocalizations l10n = l10nOf(tester);
      expect(find.text(l10n.ratingGood), findsOneWidget);

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(find.text(l10n.reviewTimeUpTitle), findsOneWidget);
      expect(find.text(l10n.reviewTimeUpMessage(0)), findsOneWidget);
      expect(find.text(l10n.ratingGood), findsNothing);
      expect(reviews.ratings, isEmpty);
    });

    testWidgets('после лимита времени оценка не принимается', (
      WidgetTester tester,
    ) async {
      final List<Card> planned = planCards();
      await pumpPlan(
        tester,
        plan: SessionPlan(
          cards: planned,
          timeBudget: const Duration(minutes: 1),
        ),
      );
      reviews.previousCard = planned.first;
      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      await tester.tap(
        find.byKey(const ValueKey<String>('review-rating-good')),
        warnIfMissed: false,
      );
      await tester.pumpAndSettle();

      expect(reviews.ratings, isEmpty);
    });

    testWidgets('без плана — «Сессия не найдена»', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        appWithHome(
          overrides: overridesFor(const <Card>[]),
          home: const ReviewSessionScreen(),
        ),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      expect(find.text(l10n.reviewPlanMissingTitle), findsOneWidget);
      expect(find.text(l10n.reviewPlanMissingMessage), findsOneWidget);
      expect(find.text(l10n.reviewBack), findsOneWidget);
    });
  });
}
