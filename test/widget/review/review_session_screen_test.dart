import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';
import '../../helpers/settings_fakes.dart';

/// Красная фаза итерации 2: экран классической сессии (SPEC A6.4, A7.2) —
/// прогресс, flip-карточка, 4 кнопки с прогнозом, клавиши, undo, «Почему?»,
/// выход и завершение.
void main() {
  late FakeReviewRepository reviews;
  late FakeCardRepository cards;

  List<Override> overridesFor(
    List<Card> deckCards, {
    FakeDeckRepository? decks,
    FakeAppSettingsStore? appSettingsStore,
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
      appSettingsStore: appSettingsStore,
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

  /// Раскрывает ответ текущей карточки — обязательный шаг перед оценкой
  /// (находка F1 аудита: оценка без ответа запрещена).
  Future<void> reveal(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();
  }

  testWidgets('каркас: прогресс, вопрос и крупное действие (G1)', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(ReviewSessionScreen), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Первый ответ'), findsNothing, reason: 'ответ скрыт');
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Аудит v7 (G1): состояние «вопрос» не содержит панели оценок вообще.
    for (final String label in <String>[
      l10n.ratingAgain,
      l10n.ratingHard,
      l10n.ratingGood,
      l10n.ratingEasy,
    ]) {
      expect(find.text(label), findsNothing, reason: 'нет оценок до ответа');
    }
    expect(
      find.byKey(const ValueKey<String>('review-reveal')),
      findsOneWidget,
    );
    // Аудит v4 (V24): до раскрытия прогнозы не показываются.
    expect(find.text(l10n.reviewIntervalMinutes(1)), findsNothing);
    expect(find.text(l10n.reviewIntervalMinutes(6)), findsNothing);
    expect(find.text(l10n.reviewIntervalMinutes(10)), findsNothing);
    expect(find.text(l10n.reviewIntervalDays(16)), findsNothing);

    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.ratingGood), findsOneWidget);
    expect(find.text(l10n.reviewIntervalMinutes(1)), findsOneWidget);
    expect(find.text(l10n.reviewIntervalMinutes(6)), findsOneWidget);
    expect(find.text(l10n.reviewIntervalMinutes(10)), findsOneWidget);
    expect(find.text(l10n.reviewIntervalDays(16)), findsOneWidget);
    // G1: главное действие лицевой стороны исчезает после раскрытия.
    expect(
      find.byKey(const ValueKey<String>('review-reveal')),
      findsNothing,
    );
  });

  testWidgets('дневной лимит новых карточек из настроек ограничивает сессию', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    final List<Override> overrides = overridesFor(
      deckCards,
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(dailyNewLimit: 1),
      ),
    );
    await pumpSession(tester, overrides: overrides);
    final AppLocalizations l10n = l10nOf(tester);
    reviews.previousCard = deckCards.first;

    expect(find.text('Первый вопрос'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.reviewCompletedTitle), findsOneWidget);
    expect(find.text('Второй вопрос'), findsNothing);
    expect(reviews.cardIds, <String>['card-1']);
  });

  testWidgets('тап по карточке раскрывает ответ', (WidgetTester tester) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));

    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();

    // D3: раскрытая карточка показывает и вопрос, и ответ — проверить, на что
    // отвечал, можно без возврата на лицевую сторону.
    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  // Находка F1 (blocker) аудита и гейт v7 G1: оценка до раскрытия ответа
  // запрещена — иначе расписание FSRS строится по ответам, которых пользователь
  // не видел. После аудита v7 кнопки не «заблокированы», а отсутствуют в дереве.
  testWidgets('оценок до раскрытия нет в дереве, после — ровно четыре (G1)', (
    WidgetTester tester,
  ) async {
    final deckCards = twoCards();
    await pumpSession(tester, overrides: overridesFor(deckCards));
    reviews.previousCard = deckCards.first;
    final AppLocalizations l10n = l10nOf(tester);

    for (final String name in <String>['again', 'hard', 'good', 'easy']) {
      expect(
        find.byKey(ValueKey<String>('review-rating-$name')),
        findsNothing,
        reason: 'до раскрытия панели оценок нет в дереве («$name»)',
      );
    }
    // Подсказка «Оценки откроются после показа ответа» удалена (G1/V7-17).
    expect(
      find.byKey(const ValueKey<String>('review-rating-hint')),
      findsNothing,
    );
    expect(find.text(l10n.reviewRevealRequiredHint), findsNothing);
    // Клавиатурные подсказки-дубли удалены (G5/V7-17).
    expect(
      find.byKey(const ValueKey<String>('review-keyboard-hints-front')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('review-keyboard-hints')),
      findsNothing,
    );

    await reveal(tester);
    int active = 0;
    for (final String name in <String>['again', 'hard', 'good', 'easy']) {
      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(ValueKey<String>('review-rating-$name')),
      );
      expect(button.onPressed, isNotNull, reason: 'после раскрытия «$name»');
      active++;
    }
    expect(active, 4, reason: 'ровно четыре оценки');
  });

  testWidgets('клавиши 1–4 до раскрытия не пишут оценку (F1)', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));

    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    expect(reviews.ratings, isEmpty);
    expect(find.text('Первый вопрос'), findsOneWidget);
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
      // Каждая следующая карточка закрыта: сначала раскрываем ответ (F1),
      // затем ставим оценку клавишей.
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      await tester.pumpAndSettle();
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
    await reveal(tester);

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
    await reveal(tester);

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
    await reveal(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();
    reviews.previousCard = deckCards.last;
    await reveal(tester);
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
    expect(
      find.byKey(const ValueKey<String>('review-empty-practice')),
      findsNothing,
      reason: 'в колоде нет карточек — тренировать нечего',
    );
  });

  // Итерация 7.11 (owner-note): пустая сессия при исчерпанном дневном лимите
  // объясняет причину и предлагает тренировку вместо тупика. Итерация 7.12
  // (ADR-028): вместо тупика — ещё и «Продолжить без лимита».
  testWidgets('дневной лимит исчерпан: причина, продолжение и тренировка', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    final List<Override> overrides = decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: deckCards.length,
            newCards: deckCards.length,
          ),
        ],
      ),
      cardRepository: FakeCardRepository(cards: deckCards),
      reviewRepository: FakeReviewRepository(),
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(dailyNewLimit: 20),
      ),
      dailyUsageRepository: FakeDailyUsageRepository(
        usage: const DailyReviewUsage(newCards: 20),
      ),
    );
    await pumpSession(tester, overrides: overrides);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewDailyLimitTitle), findsOneWidget);
    expect(find.text(l10n.reviewDailyLimitMessage), findsOneWidget);
    final Finder practice = find.byKey(
      const ValueKey<String>('review-empty-practice'),
    );
    expect(practice, findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('review-empty-continue')),
      findsOneWidget,
    );

    // «Продолжить без лимита» перестраивает очередь без ограничений.
    await tester.tap(
      find.byKey(const ValueKey<String>('review-empty-continue')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text(l10n.reviewDailyLimitTitle), findsNothing);
  });

  testWidgets('дневной лимит исчерпан: тренировка доступна из пустой сессии', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = twoCards();
    final List<Override> overrides = decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: deckCards.length,
            newCards: deckCards.length,
          ),
        ],
      ),
      cardRepository: FakeCardRepository(cards: deckCards),
      reviewRepository: FakeReviewRepository(),
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(dailyNewLimit: 20),
      ),
      dailyUsageRepository: FakeDailyUsageRepository(
        usage: const DailyReviewUsage(newCards: 20),
      ),
    );
    await pumpSession(tester, overrides: overrides);

    await tester.tap(
      find.byKey(const ValueKey<String>('review-empty-practice')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(PracticeSessionScreen), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  // ADR-028: карточки, созданные сегодня, доступны даже при исчерпанном лимите.
  testWidgets('сегодняшняя новая карточка не блокируется дневным лимитом', (
    WidgetTester tester,
  ) async {
    final List<Card> deckCards = <Card>[
      makeCard(
        id: 'today-1',
        deckId: 'deck-1',
        front: 'Сегодняшний вопрос',
        createdAt: DateTime.now(),
      ),
    ];
    final List<Override> overrides = decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: 1,
            newCards: 1,
          ),
        ],
      ),
      cardRepository: FakeCardRepository(cards: deckCards),
      reviewRepository: FakeReviewRepository(),
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(dailyNewLimit: 20),
      ),
      dailyUsageRepository: FakeDailyUsageRepository(
        usage: const DailyReviewUsage(newCards: 20),
      ),
    );
    await pumpSession(tester, overrides: overrides);

    expect(find.text(l10nOf(tester).reviewDailyLimitTitle), findsNothing);
    expect(find.text('Сегодняшний вопрос'), findsOneWidget);
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
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  testWidgets('«Почему?» скрыта без source_excerpt (аудит v4)', (
    WidgetTester tester,
  ) async {
    await pumpSession(tester, overrides: overridesFor(twoCards()));

    // Аудит v4 (ACTIONS #18): мёртвая disabled-иконка убрана — кнопки просто нет.
    expect(find.byKey(const ValueKey<String>('review-why')), findsNothing);
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
        // F1: каждая следующая карточка закрыта — раскрываем её перед оценкой.
        for (int index = 0; index < 4; index++) {
          if (index > 0) {
            await tester.tap(find.byKey(const ValueKey<String>('review-card')));
            await tester.pumpAndSettle();
          }
          await tester.tap(
            find.byKey(
              ValueKey<String>(
                'review-rating-${<String>['again', 'hard', 'good', 'easy'][index]}',
              ),
            ),
          );
          await tester.pumpAndSettle();
        }

        expect(haptics, <Object?>[
          'HapticFeedbackType.selectionClick', // раскрытие 1-й карточки
          'HapticFeedbackType.heavyImpact', // Не знаю
          'HapticFeedbackType.selectionClick', // раскрытие 2-й
          'HapticFeedbackType.lightImpact', // Сложно
          'HapticFeedbackType.selectionClick', // раскрытие 3-й
          'HapticFeedbackType.lightImpact', // Знаю
          'HapticFeedbackType.selectionClick', // раскрытие 4-й
          'HapticFeedbackType.selectionClick', // Легко
          'HapticFeedbackType.mediumImpact', // завершение сессии
        ]);
      },
    );

    testWidgets('haptics выключены в настройках — платформенных вызовов нет', (
      WidgetTester tester,
    ) async {
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
      await pumpSession(
        tester,
        overrides: overridesFor(
          twoCards(),
          appSettingsStore: FakeAppSettingsStore(
            settings: AppSettings.defaults.copyWith(haptics: false),
          ),
        ),
      );
      final AppLocalizations l10n = l10nOf(tester);
      await tester.tap(find.byKey(const ValueKey<String>('review-card')));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.ratingGood));
      await tester.pumpAndSettle();

      expect(haptics, isEmpty);
    });

    testWidgets('цвета кнопок A7.2 и значение прогресса', (
      WidgetTester tester,
    ) async {
      final deckCards = twoCards();
      await pumpSession(tester, overrides: overridesFor(deckCards));
      final BuildContext context = tester.element(
        find.byType(ReviewSessionScreen),
      );
      final ColorScheme scheme = Theme.of(context).colorScheme;

      LinearProgressIndicator progress() =>
          tester.widget<LinearProgressIndicator>(
            find.byType(LinearProgressIndicator),
          );
      expect(progress().value, 0);
      reviews.previousCard = deckCards.first;
      await reveal(tester);

      // Кнопки существуют только после раскрытия (G1) — цвета проверяются там.
      Color? background(String name) => tester
          .widget<FilledButton>(
            find.byKey(ValueKey<String>('review-rating-$name')),
          )
          .style
          ?.backgroundColor
          ?.resolve(<WidgetState>{});
      // Цвета ролей дизайн-системы v2 (ADR-038): Again — errorContainer,
      // Hard — surfaceContainer, Good — secondaryContainer, Easy — primaryFixed.
      expect(background('again'), scheme.errorContainer);
      expect(background('hard'), scheme.surfaceContainer);
      expect(background('good'), scheme.secondaryContainer);
      expect(background('easy'), scheme.primaryFixed);

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

    testWidgets('«Почему?» скрыта при пустой цитате (L6, аудит v4)', (
      WidgetTester tester,
    ) async {
      await pumpSession(
        tester,
        overrides: overridesFor(twoCards(sourceExcerpt: '   ')),
      );
      expect(find.byKey(const ValueKey<String>('review-why')), findsNothing);
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
      await reveal(tester);

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
      // Маркер активной сессии — главное действие лицевой стороны (оценок до
      // раскрытия в дереве нет, G1).
      expect(
        find.byKey(const ValueKey<String>('review-reveal')),
        findsOneWidget,
      );

      await tester.pump(const Duration(minutes: 1));
      await tester.pump();

      expect(find.text(l10n.reviewTimeUpTitle), findsOneWidget);
      expect(find.text(l10n.reviewTimeUpMessage(0)), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('review-reveal')),
        findsNothing,
      );
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

      // Клавиша оценки после истечения времени: движок не должен получить
      // запись (кнопки уже скрыты итоговым экраном).
      await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
      await tester.pumpAndSettle();

      expect(reviews.ratings, isEmpty);
    });

    testWidgets('без плана — «Сессия не найдена»', (WidgetTester tester) async {
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

