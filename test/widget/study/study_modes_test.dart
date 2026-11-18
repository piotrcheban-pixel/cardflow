import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/study/multiple_choice_screen.dart';
import 'package:cardflow/ui/study/typing_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Режимы «Тест» и «Ввод ответа» (7.15).
void main() {
  final DateTime now = DateTime.utc(2026, 11, 16, 12);
  final List<String> answers = <String>[
    'Митохондрия',
    'Рибосома',
    'Хлоропласт',
    'Лизосома',
    'Гольджи',
  ];

  List<Card> cards({DateTime? due, CardState state = CardState.newCard}) {
    return <Card>[
      for (var index = 0; index < answers.length; index++)
        makeCard(
          id: 'card-$index',
          deckId: 'deck-1',
          front: 'Вопрос $index?',
          back: answers[index],
          state: state,
          due: due,
          createdAt: now,
          updatedAt: now,
        ),
    ];
  }

  Future<({FakeReviewRepository reviews, FakePracticeRepository practice})>
  pumpScreen(
    WidgetTester tester, {
    required String location,
    required List<Card> deck,
    FakeReviewRepository? reviews,
    FakePracticeRepository? practice,
  }) async {
    final FakeReviewRepository reviewRepository =
        reviews ?? FakeReviewRepository();
    reviewRepository.previousCard ??= deck.first;
    final FakePracticeRepository practiceRepository =
        practice ?? FakePracticeRepository();
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: FakeCardRepository(cards: deck),
          reviewRepository: reviewRepository,
          practiceRepository: practiceRepository,
        ),
        routes: decksRoutes(),
        initialLocation: location,
      ),
    );
    await tester.pumpAndSettle();
    return (reviews: reviewRepository, practice: practiceRepository);
  }

  Color? backgroundOf(WidgetTester tester, int index) {
    final FilledButton button = tester.widget<FilledButton>(
      find.descendant(
        of: find.byKey(ValueKey<String>('study-option-$index')),
        matching: find.byType(FilledButton),
      ),
    );
    return button.style?.backgroundColor?.resolve(<WidgetState>{});
  }

  group('Тест', () {
    testWidgets('вопрос, четыре варианта и верный ответ в них', (tester) async {
      await pumpScreen(tester, location: '/decks/deck-1/test', deck: cards());
      expect(find.byType(MultipleChoiceScreen), findsOneWidget);
      expect(find.text('Вопрос 0?'), findsOneWidget);
      for (var index = 0; index < 4; index++) {
        expect(
          find.byKey(ValueKey<String>('study-option-$index')),
          findsOneWidget,
        );
      }
      expect(find.text('Митохондрия'), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('test-next')), findsNothing);
    });

    testWidgets('верный ответ: зелёная подсветка, Good только для due', (
      tester,
    ) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/test',
        deck: cards(),
      );
      final int correctIndex = _indexOfLabel(tester, 'Митохондрия');

      await tester.tap(find.text('Митохондрия'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.ratings, <Rating>[Rating.good]);
      expect(state.reviews.modes, <String>['test']);
      expect(backgroundOf(tester, correctIndex), const Color(0xFFE8F5E9));
      expect(find.byKey(const ValueKey<String>('test-next')), findsOneWidget);
    });

    testWidgets('неверный ответ: Again, красный выбор и зелёный правильный', (
      tester,
    ) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/test',
        deck: cards(),
      );
      final int correctIndex = _indexOfLabel(tester, 'Митохондрия');
      final int wrongIndex = _indexOfLabel(tester, 'Рибосома');

      await tester.tap(find.text('Рибосома'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.ratings, <Rating>[Rating.again]);
      expect(backgroundOf(tester, wrongIndex), const Color(0xFFFFEBEE));
      expect(backgroundOf(tester, correctIndex), const Color(0xFFE8F5E9));
      expect(find.byKey(const ValueKey<String>('test-next')), findsOneWidget);
    });

    testWidgets('верный ответ авто-переходит через 1,2 с', (tester) async {
      await pumpScreen(tester, location: '/decks/deck-1/test', deck: cards());
      await tester.tap(find.text('Митохондрия'));
      await tester.pump();
      expect(find.text('Вопрос 0?'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 1300));
      await tester.pump();
      expect(find.text('Вопрос 0?'), findsNothing);
      expect(find.text('Вопрос 1?'), findsOneWidget);
    });

    testWidgets('клавиши 1–4 выбирают вариант, Enter ведёт дальше', (
      tester,
    ) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/test',
        deck: cards(),
      );
      // Находим номер правильного варианта и нажимаем его цифрой.
      final int correctIndex = _indexOfLabel(tester, 'Митохондрия');
      await tester.sendKeyEvent(switch (correctIndex) {
        0 => LogicalKeyboardKey.digit1,
        1 => LogicalKeyboardKey.digit2,
        2 => LogicalKeyboardKey.digit3,
        _ => LogicalKeyboardKey.digit4,
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.reviews.ratings, <Rating>[Rating.good]);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(find.text('Вопрос 1?'), findsOneWidget);
    });

    testWidgets('карточка с due в будущем пишется как тренировка', (
      tester,
    ) async {
      // Экран работает с реальными часами (`isDueForStudy` сравнивает due с
      // `DateTime.now().toUtc()`), поэтому фиксированная дата рано или поздно
      // оказывается в прошлом. due считаем от текущего момента.
      final DateTime futureDue = DateTime.now().toUtc().add(
        const Duration(days: 30),
      );
      final deck = cards(state: CardState.review, due: futureDue);
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/test',
        deck: deck,
      );
      await tester.tap(find.text('Митохондрия'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.ratings, isEmpty, reason: 'FSRS не трогаем');
      expect(state.practice.ratings, <Rating>[Rating.good]);
      expect(state.practice.modes, <String>['test']);
    });

    testWidgets('итоги: точность, ошибки и «Повторить ошибки»', (tester) async {
      await pumpScreen(tester, location: '/decks/deck-1/test', deck: cards());
      final l10n = l10nOf(tester);
      for (var attempt = 0; attempt < 5; attempt++) {
        final String correct = answers[attempt];
        final int wrongIndex = _wrongIndex(tester, correct);
        expect(
          wrongIndex,
          isNot(-1),
          reason: 'в вопросе есть неверный вариант',
        );
        await tester.tap(
          find.byKey(ValueKey<String>('study-option-$wrongIndex')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const ValueKey<String>('test-next')));
        await tester.pump();
      }
      expect(find.text(l10n.testResultsTitle), findsOneWidget);
      expect(find.text(l10n.testAccuracy(0)), findsOneWidget);
      expect(find.text(l10n.studyWrongListTitle), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('study-repeat-mistakes')),
      );
      await tester.pump();
      expect(find.byType(MultipleChoiceScreen), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('test-next')), findsNothing);
    });

    testWidgets('нет подходящих карточек — пустое состояние', (tester) async {
      final longCards = <Card>[
        makeCard(
          id: 'long-1',
          deckId: 'deck-1',
          front: 'Вопрос?',
          back: 'Очень длинный ответ, который нельзя ввести вручную, потому что он длиннее шестидесяти символов.',
        ),
      ];
      await pumpScreen(tester, location: '/decks/deck-1/test', deck: longCards);
      expect(find.text(l10nOf(tester).testEmptyTitle), findsOneWidget);
    });
  });

  group('Ввод ответа', () {
    testWidgets('exact: зелёное «Верно» и Good', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('typing-input')),
        'митохондрия',
      );
      await tester.tap(find.byKey(const ValueKey<String>('typing-check')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(l10n.typingCorrect), findsOneWidget);
      expect(state.reviews.ratings, <Rating>[Rating.good]);
      expect(find.byKey(const ValueKey<String>('typing-next')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('typing-diff')), findsNothing);
    });

    testWidgets('almost: жёлтое «Почти!» и Hard', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: cards(),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('typing-input')),
        'Митохондрий',
      );
      await tester.tap(find.byKey(const ValueKey<String>('typing-check')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(l10nOf(tester).typingAlmost), findsOneWidget);
      expect(state.reviews.ratings, <Rating>[Rating.hard]);
      expect(
        find.byKey(const ValueKey<String>('typing-i-was-right')),
        findsOneWidget,
      );
    });

    testWidgets('wrong: красное «Неверно», diff, ответ и «Я был прав»', (
      tester,
    ) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('typing-input')),
        'Блк',
      );
      await tester.tap(find.byKey(const ValueKey<String>('typing-check')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(l10n.typingWrong), findsOneWidget);
      expect(find.text(l10n.typingRightAnswer('Митохондрия')), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('typing-diff')), findsOneWidget);
      expect(state.reviews.ratings, <Rating>[Rating.again]);
      expect(state.reviews.modes, <String>['typing']);
    });

    testWidgets('«Я был прав» меняет Again на Good', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      await tester.enterText(
        find.byKey(const ValueKey<String>('typing-input')),
        'Блк',
      );
      await tester.tap(find.byKey(const ValueKey<String>('typing-check')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      await tester.tap(
        find.byKey(const ValueKey<String>('typing-i-was-right')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.undone, hasLength(1));
      expect(state.reviews.ratings, <Rating>[Rating.again, Rating.good]);
      expect(find.text(l10n.typingCorrect), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('typing-i-was-right')),
        findsNothing,
      );
    });

    testWidgets('«Показать ответ» = сдался: Again и правильный ответ', (
      tester,
    ) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('typing-show-answer')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.ratings, <Rating>[Rating.again]);
      expect(find.text(l10n.typingRightAnswer('Митохондрия')), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('typing-i-was-right')),
        findsNothing,
      );
      expect(find.byKey(const ValueKey<String>('typing-next')), findsOneWidget);
    });

    testWidgets('Enter отправляет ответ', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: cards(),
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('typing-input')),
        'Митохондрия',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.reviews.ratings, <Rating>[Rating.good]);
    });

    testWidgets('карточки без пригодных ответов — пустое состояние', (
      tester,
    ) async {
      final formulaCards = <Card>[
        makeCard(
          id: 'f',
          deckId: 'deck-1',
          front: 'Формула?',
          back: r'$a^2 + b^2 = c^2$',
        ),
      ];
      await pumpScreen(
        tester,
        location: '/decks/deck-1/typing',
        deck: formulaCards,
      );
      expect(find.text(l10nOf(tester).typingEmptyTitle), findsOneWidget);
    });

    testWidgets('экран ввода — TypingScreen', (tester) async {
      await pumpScreen(tester, location: '/decks/deck-1/typing', deck: cards());
      expect(find.byType(TypingScreen), findsOneWidget);
    });
  });
}

int _wrongIndex(WidgetTester tester, String correct) {
  for (var index = 0; index < 4; index++) {
    final Finder key = find.byKey(ValueKey<String>('study-option-$index'));
    final Finder text = find.descendant(of: key, matching: find.byType(Text));
    if (text.evaluate().isEmpty) continue;
    final String? label = tester.widget<Text>(text.first).data;
    if (label != null && label != correct) return index;
  }
  return -1;
}

int _indexOfLabel(WidgetTester tester, String label) {
  for (var index = 0; index < 4; index++) {
    final Finder key = find.byKey(ValueKey<String>('study-option-$index'));
    if (find
        .descendant(of: key, matching: find.text(label))
        .evaluate()
        .isNotEmpty) {
      return index;
    }
  }
  return -1;
}
