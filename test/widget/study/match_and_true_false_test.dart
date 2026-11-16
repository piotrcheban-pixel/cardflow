import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/study/match_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Режимы «Подбор пар» и «Верно/Неверно» (7.16).
void main() {
  final DateTime now = DateTime.utc(2026, 11, 16, 12);
  final List<String> answers = <String>[
    'Митохондрия',
    'Рибосома',
    'Хлоропласт',
    'Лизосома',
    'Гольджи',
    'Ядро',
  ];

  List<Card> cards({int count = 6}) {
    return <Card>[
      for (var index = 0; index < count; index++)
        makeCard(
          id: 'card-$index',
          deckId: 'deck-1',
          front: 'Вопрос $index',
          back: answers[index],
          createdAt: now,
          updatedAt: now,
        ),
    ];
  }

  Future<({FakeReviewRepository reviews, FakeMatchBestStore best})> pumpScreen(
    WidgetTester tester, {
    required String location,
    required List<Card> deck,
    FakeMatchBestStore? best,
    FakeReviewRepository? reviews,
  }) async {
    final FakeMatchBestStore bestStore =
        best ?? FakeMatchBestStore(bestByDeck: <String, int>{'deck-1': 5000});
    final FakeReviewRepository reviewRepository =
        reviews ?? FakeReviewRepository();
    reviewRepository.previousCard ??= deck.first;
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: FakeCardRepository(cards: deck),
          reviewRepository: reviewRepository,
          matchBestStore: bestStore,
        ),
        routes: decksRoutes(),
        initialLocation: location,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    return (reviews: reviewRepository, best: bestStore);
  }

  List<String> tileTexts(WidgetTester tester) {
    final List<String> texts = <String>[];
    for (var index = 0; index < 12; index++) {
      final Finder key = find.byKey(ValueKey<String>('match-tile-$index'));
      final Finder text = find.descendant(of: key, matching: find.byType(Text));
      texts.add(
        text.evaluate().isEmpty
            ? ''
            : tester.widget<Text>(text.first).data ?? '',
      );
    }
    return texts;
  }

  int tileIndexByText(WidgetTester tester, String value) {
    for (var index = 0; index < 12; index++) {
      final Finder key = find.byKey(ValueKey<String>('match-tile-$index'));
      final Finder text = find.descendant(of: key, matching: find.byType(Text));
      if (text.evaluate().isEmpty) continue;
      if (tester.widget<Text>(text.first).data == value) return index;
    }
    return -1;
  }

  group('Подбор пар', () {
    testWidgets('сетка 12 плиток, таймер и лучшее время', (tester) async {
      await pumpScreen(tester, location: '/decks/deck-1/match', deck: cards());
      expect(find.byType(MatchScreen), findsOneWidget);
      final List<String> texts = tileTexts(tester);
      expect(texts.where((String text) => text.isNotEmpty), hasLength(12));
      final l10n = l10nOf(tester);
      expect(find.text(l10n.matchBest('5,0')), findsOneWidget);
      expect(find.text(l10n.matchTimer('0,0')), findsOneWidget);
    });

    testWidgets('несовпавшая пара не исчезает', (tester) async {
      await pumpScreen(tester, location: '/decks/deck-1/match', deck: cards());
      final List<String> texts = tileTexts(tester);
      // Берём две плитки разных карточек (первый текст и последний).
      final int first = 0;
      final int second = 11;
      expect(texts[first], isNot(texts[second]));
      await tester.tap(find.byKey(ValueKey<String>('match-tile-$first')));
      await tester.pump();
      await tester.tap(find.byKey(ValueKey<String>('match-tile-$second')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(
        tileTexts(tester).where((String text) => text.isNotEmpty),
        hasLength(12),
      );
    });

    testWidgets('все пары найдены: итог, лучшее время и «Ещё раз»', (
      tester,
    ) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/match',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      for (final Card card in cards()) {
        final int front = tileIndexByText(tester, card.front);
        final int back = tileIndexByText(tester, card.back);
        expect(front, isNot(-1));
        expect(back, isNot(-1));
        await tester.tap(find.byKey(ValueKey<String>('match-tile-$front')));
        await tester.pump();
        await tester.tap(find.byKey(ValueKey<String>('match-tile-$back')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
      }
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('match-completed')),
        findsOneWidget,
      );
      expect(find.text(l10n.matchCompletedTitle), findsOneWidget);
      expect(state.reviews.ratings, isEmpty, reason: 'Пары не пишут FSRS');
      expect(state.best.saves, hasLength(1));
      expect(state.best.saves.single.deckId, 'deck-1');
      expect(
        find.byKey(const ValueKey<String>('match-best-result')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey<String>('match-restart')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(
        tileTexts(tester).where((String text) => text.isNotEmpty),
        hasLength(12),
      );
    });

    testWidgets('меньше 6 карточек — пустое состояние', (tester) async {
      await pumpScreen(
        tester,
        location: '/decks/deck-1/match',
        deck: cards(count: 5),
      );
      expect(find.text(l10nOf(tester).matchEmptyTitle), findsOneWidget);
    });
  });

  group('Верно/Неверно', () {
    testWidgets('верный ответ → Good, затем «Далее»', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/true-false',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      final String statement = plainTextUnder(
        tester,
        find.byKey(const ValueKey<String>('tf-statement')),
      );
      final bool isTrue = statement == l10n.trueFalseStatement(answers.first);
      await tester.tap(
        find.byKey(ValueKey<String>(isTrue ? 'tf-true' : 'tf-false')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.ratings, <Rating>[Rating.good]);
      expect(state.reviews.modes, <String>['true_false']);
      expect(find.text(l10n.trueFalseCorrect), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('tf-next')));
      await tester.pump();
      expect(find.text('Вопрос 0'), findsNothing);
      expect(find.text('Вопрос 1'), findsOneWidget);
    });

    testWidgets('неверный ответ → Again и правильный ответ', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/true-false',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      final String statement = plainTextUnder(
        tester,
        find.byKey(const ValueKey<String>('tf-statement')),
      );
      final bool isTrue = statement == l10n.trueFalseStatement(answers.first);
      await tester.tap(
        find.byKey(ValueKey<String>(isTrue ? 'tf-false' : 'tf-true')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(state.reviews.ratings, <Rating>[Rating.again]);
      expect(find.text(l10n.trueFalseWrong), findsOneWidget);
      expect(
        find.text(l10n.trueFalseExplanation(answers.first)),
        findsOneWidget,
      );
    });

    testWidgets('свайп вправо = «верно»', (tester) async {
      final state = await pumpScreen(
        tester,
        location: '/decks/deck-1/true-false',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      final String statement = plainTextUnder(
        tester,
        find.byKey(const ValueKey<String>('tf-statement')),
      );
      final bool isTrue = statement == l10n.trueFalseStatement(answers.first);
      await tester.drag(
        find.byKey(const ValueKey<String>('tf-statement')),
        const Offset(140, 0),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(state.reviews.ratings, <Rating>[
        isTrue ? Rating.good : Rating.again,
      ]);
    });

    testWidgets('итоги: точность и повтор ошибок', (tester) async {
      await pumpScreen(
        tester,
        location: '/decks/deck-1/true-false',
        deck: cards(),
      );
      final l10n = l10nOf(tester);
      for (var attempt = 0; attempt < 6; attempt++) {
        final String statement = plainTextUnder(
          tester,
          find.byKey(const ValueKey<String>('tf-statement')),
        );
        final bool isTrue =
            statement == l10n.trueFalseStatement(answers[attempt]);
        // Отвечаем неверно, чтобы проверить итог и список ошибок.
        await tester.tap(
          find.byKey(ValueKey<String>(isTrue ? 'tf-false' : 'tf-true')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await tester.tap(find.byKey(const ValueKey<String>('tf-next')));
        await tester.pump();
      }
      expect(find.text(l10n.testResultsTitle), findsOneWidget);
      expect(find.text(l10n.testAccuracy(0)), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('study-repeat-mistakes')),
        findsOneWidget,
      );
    });

    testWidgets('нет другого ответа — пустое состояние', (tester) async {
      await pumpScreen(
        tester,
        location: '/decks/deck-1/true-false',
        deck: cards(count: 1),
      );
      expect(find.text(l10nOf(tester).trueFalseEmptyTitle), findsOneWidget);
    });
  });
}
