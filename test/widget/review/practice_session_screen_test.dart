import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Экран «Тренировка» (ADR-025, итерация 7.11): любые карточки вне FSRS,
/// оценки в журнал practice, undo, завершение.
void main() {
  late FakePracticeRepository practice;
  late FakeCardRepository cards;

  List<Override> overridesFor(List<Card> deckCards) {
    cards = FakeCardRepository(cards: deckCards);
    practice = FakePracticeRepository();
    return decksOverrides(
      deckRepository: FakeDeckRepository(
        summaries: <DeckSummary>[
          makeSummary(
            id: 'deck-1',
            name: 'Испанский',
            totalCards: deckCards.length,
          ),
        ],
      ),
      cardRepository: cards,
      practiceRepository: practice,
    );
  }

  Future<void> pumpPractice(
    WidgetTester tester, {
    required List<Override> overrides,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: overrides,
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/practice',
      ),
    );
    await tester.pumpAndSettle();
  }

  List<Card> cardsToPractice() => <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Первый вопрос',
      back: 'Первый ответ',
      createdAt: DateTime.utc(2026, 11, 10),
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-1',
      front: 'Второй вопрос',
      back: 'Второй ответ',
      state: CardState.review,
      // due в будущем: тренировка игнорирует FSRS.
      due: DateTime.now().add(const Duration(days: 10)),
      createdAt: DateTime.utc(2026, 11, 11),
    ),
  ];

  /// Раскрывает ответ текущей карточки (F1: без ответа оценка запрещена).
  Future<void> reveal(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('practice-card')));
    await tester.pumpAndSettle();
  }

  testWidgets('карточка с due в будущем доступна; ответ скрыт до тапа', (
    WidgetTester tester,
  ) async {
    await pumpPractice(tester, overrides: overridesFor(cardsToPractice()));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.byType(PracticeSessionScreen), findsOneWidget);
    expect(find.text(l10n.practiceTitle), findsOneWidget);
    expect(find.text(l10n.practiceSubtitle), findsOneWidget);
    expect(find.text('Первый вопрос'), findsOneWidget);
    expect(find.text('Первый ответ'), findsNothing);
    // Аудит v7 (G1): до раскрытия ответа панели оценок нет в дереве вообще —
    // ни активной, ни серой, ни с подсказкой.
    expect(find.text(l10n.ratingAgain), findsNothing);
    expect(find.text(l10n.ratingGood), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('review-rating-good')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey<String>('practice-reveal')),
      findsOneWidget,
      reason: 'единственное действие лицевой стороны',
    );
    expect(
      find.byKey(const ValueKey<String>('review-interval-good')),
      findsNothing,
      reason: 'в тренировке нет прогноза интервалов',
    );

    await tester.tap(find.byKey(const ValueKey<String>('practice-card')));
    await tester.pumpAndSettle();
    expect(find.text('Первый ответ'), findsOneWidget);
    expect(find.text(l10n.ratingGood), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('practice-reveal')),
      findsNothing,
      reason: 'после раскрытия действие «Показать ответ» исчезает',
    );
  });

  testWidgets('оценок до раскрытия нет в дереве, после раскрытия — четыре (G1)', (
    WidgetTester tester,
  ) async {
    await pumpPractice(tester, overrides: overridesFor(cardsToPractice()));

    for (final String name in <String>['again', 'hard', 'good', 'easy']) {
      expect(
        find.byKey(ValueKey<String>('review-rating-$name')),
        findsNothing,
        reason: 'тренировка: панели оценок до ответа нет («$name»)',
      );
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.pumpAndSettle();
    expect(practice.ratings, isEmpty);

    await reveal(tester);
    for (final String name in <String>['again', 'hard', 'good', 'easy']) {
      final FilledButton button = tester.widget<FilledButton>(
        find.byKey(ValueKey<String>('review-rating-$name')),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: 'после раскрытия «$name» активна',
      );
    }
  });

  testWidgets('оценка пишется как practice и ведёт к следующей карточке', (
    WidgetTester tester,
  ) async {
    await pumpPractice(tester, overrides: overridesFor(cardsToPractice()));

    await tester.tap(find.byKey(const ValueKey<String>('practice-card')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();

    expect(practice.cardIds, <String>['card-1']);
    expect(practice.ratings, <Rating>[Rating.good]);
    expect(find.text('Второй вопрос'), findsOneWidget);

    await reveal(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-easy')));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.practiceCompletedTitle), findsOneWidget);
    expect(find.text(l10n.practiceCompletedMessage(2)), findsOneWidget);
    expect(practice.ratings, <Rating>[Rating.good, Rating.easy]);
  });

  testWidgets('undo возвращает карточку и удаляет запись тренировки', (
    WidgetTester tester,
  ) async {
    await pumpPractice(tester, overrides: overridesFor(cardsToPractice()));

    await reveal(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-hard')));
    await tester.pumpAndSettle();
    expect(find.text('Второй вопрос'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('review-undo')));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = l10nOf(tester);
    expect(practice.undoneLogIds, <String>['practice-log-1']);
    expect(
      find.text('Первый ответ'),
      findsOneWidget,
      reason: 'после undo карточка возвращается раскрытой',
    );
    expect(find.text(l10n.reviewUndoneMessage), findsOneWidget);
  });

  testWidgets('ошибка записи: сообщение из ARB, карточка та же', (
    WidgetTester tester,
  ) async {
    final List<Override> overrides = overridesFor(cardsToPractice());
    await pumpPractice(tester, overrides: overrides);
    practice.recordError = StateError('БД недоступна');
    await reveal(tester);

    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pumpAndSettle();

    final AppLocalizations l10n = l10nOf(tester);
    expect(find.text(l10n.reviewSaveError), findsOneWidget);
    expect(find.textContaining('БД недоступна'), findsNothing);
    expect(find.text('Первый вопрос'), findsOneWidget);
  });

  testWidgets('пустая колода — пустое состояние тренировки', (
    WidgetTester tester,
  ) async {
    await pumpPractice(tester, overrides: overridesFor(const <Card>[]));
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.practiceEmptyTitle), findsOneWidget);
    expect(find.text(l10n.practiceEmptyMessage), findsOneWidget);
    expect(find.text(l10n.reviewBack), findsOneWidget);
  });

  testWidgets('ошибка загрузки карточек — сообщение из ARB и повтор', (
    WidgetTester tester,
  ) async {
    final List<Override> overrides = overridesFor(cardsToPractice());
    cards.cardsByDeckError = StateError('boom');
    await pumpPractice(tester, overrides: overrides);
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.reviewLoadError), findsOneWidget);
    expect(find.textContaining('boom'), findsNothing);

    cards.cardsByDeckError = null;
    await tester.tap(find.widgetWithText(OutlinedButton, l10n.retry));
    await tester.pumpAndSettle();
    expect(find.text('Первый вопрос'), findsOneWidget);
  });
}
