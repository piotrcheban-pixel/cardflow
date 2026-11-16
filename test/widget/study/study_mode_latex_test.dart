import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/distractor_generator.dart';
import 'package:cardflow/domain/study/true_false_question.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Глобальный рендер LaTeX и cloze в новых режимах (7.17).
///
/// Владелец видел сырые `$…$` и `{{c1::…}}` в «Тесте», «Вводе ответа»,
/// «Верно/Неверно» и «Подборе пар». Тесты подают карточки с формулой
/// `$E=mc^2$` и проверяют, что в дереве есть виджет [Math] от
/// `flutter_math_fork`, а сырых строк нет.
void main() {
  final DateTime now = DateTime.utc(2026, 11, 16, 12);
  const String deckId = 'deck-1';

  Card card(
    String id,
    String front,
    String back, {
    CardType type = CardType.basic,
  }) {
    return makeCard(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      cardType: type,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Колода с формулой во фронте и обычными ответами (Тест/Ввод).
  List<Card> formulaFrontDeck() => <Card>[
    card('ff-0', r'Формула $E=mc^2$', 'Энергия'),
    card('ff-1', r'Формула $F=ma$', 'Сила'),
    card('ff-2', r'Формула $P=UI$', 'Мощность'),
    card('ff-3', r'Формула $Q=cm\Delta t$', 'Теплота'),
    card('ff-4', r'Формула $I=U/R$', 'Ток'),
  ];

  /// Колода, где формула и в вопросе, и в ответе.
  List<Card> formulaAnswersDeck() => <Card>[
    card('fa-0', r'Чему равно $x_0$?', r'$x_0 = a$'),
    card('fa-1', r'Чему равно $x_1$?', r'$x_1 = b$'),
    card('fa-2', r'Чему равно $x_2$?', r'$x_2 = c$'),
    card('fa-3', r'Чему равно $x_3$?', r'$x_3 = d$'),
    card('fa-4', r'Чему равно $x_4$?', r'$x_4 = e$'),
  ];

  Future<void> pumpMode(
    WidgetTester tester,
    String location,
    List<Card> deck,
  ) async {
    final FakeReviewRepository reviews = FakeReviewRepository();
    reviews.previousCard ??= deck.first;
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: FakeCardRepository(cards: deck),
          reviewRepository: reviews,
          matchBestStore: FakeMatchBestStore(),
        ),
        routes: decksRoutes(),
        initialLocation: location,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// Сырой `$…$` в любом видимом тексте (включая `Text.rich`).
  Finder rawDollar() => find.textContaining(r'$', findRichText: true);

  /// Сырая cloze-разметка в любом видимом тексте.
  Finder rawCloze() => find.textContaining('{{', findRichText: true);

  int mathCount(WidgetTester tester) => find.byType(Math).evaluate().length;

  /// Карточка, показанная сейчас в вопросе (общий рендер новых режимов).
  Card currentCard(WidgetTester tester) {
    return tester.widget<CardContentView>(find.byType(CardContentView)).card;
  }

  group('Тест', () {
    testWidgets(r'вопрос с формулой — Math, сырого $E=mc^2$ нет', (
      tester,
    ) async {
      await pumpMode(tester, '/decks/deck-1/test', formulaFrontDeck());
      expect(find.byType(CardContentView), findsOneWidget);
      expect(mathCount(tester), greaterThanOrEqualTo(1));
      expect(rawDollar(), findsNothing, reason: 'сырой LaTeX в дереве');
    });

    testWidgets('вопрос показывает все формулы сразу, без пошагового шага', (
      tester,
    ) async {
      await pumpMode(tester, '/decks/deck-1/test', <Card>[
        for (var index = 0; index < 4; index++)
          card('two-$index', r'Сложи $a+b$ и $c+d$', 'Сумма $index'),
      ]);
      expect(mathCount(tester), 2, reason: 'обе формулы вопроса видны');
      expect(
        find.byKey(const ValueKey<String>('latex-next-step')),
        findsNothing,
        reason: 'пошаговое раскрытие — механика «Классики»',
      );
      expect(rawDollar(), findsNothing);
    });

    testWidgets('четыре варианта ответа рендерят формулы через Math', (
      tester,
    ) async {
      await pumpMode(tester, '/decks/deck-1/test', formulaAnswersDeck());
      for (var index = 0; index < 4; index++) {
        final Finder option = find.byKey(
          ValueKey<String>('study-option-$index'),
        );
        expect(option, findsOneWidget, reason: 'вариант $index есть');
        expect(
          find.descendant(of: option, matching: find.byType(Math)),
          findsOneWidget,
          reason: 'в варианте $index формула отрисована Math',
        );
      }
      expect(rawDollar(), findsNothing, reason: 'сырой LaTeX в вариантах');
    });

    testWidgets('итоги: формула во фронте и в ответе — Math', (tester) async {
      final List<Card> deck = formulaAnswersDeck();
      await pumpMode(tester, '/decks/deck-1/test', deck);
      for (var attempt = 0; attempt < deck.length; attempt++) {
        final Card shown = currentCard(tester);
        final DistractorSet set = const DistractorGenerator().buildQuestion(
          shown,
          deck,
        )!;
        final int wrong = set.correctIndex == 0 ? 1 : 0;
        await tester.tap(find.byKey(ValueKey<String>('study-option-$wrong')));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        if (find
            .byKey(const ValueKey<String>('test-next'))
            .evaluate()
            .isEmpty) {
          break;
        }
        await tester.tap(find.byKey(const ValueKey<String>('test-next')));
        await tester.pump();
      }
      expect(
        find.text(l10nOf(tester).studyWrongListTitle),
        findsOneWidget,
        reason: 'итоги со списком ошибок',
      );
      expect(mathCount(tester), greaterThan(0));
      expect(rawDollar(), findsNothing, reason: 'сырой LaTeX в итогах');
    });
  });

  group('Ввод ответа', () {
    testWidgets('вопрос с формулой — Math, сырого текста нет', (tester) async {
      await pumpMode(tester, '/decks/deck-1/typing', formulaFrontDeck());
      expect(mathCount(tester), greaterThanOrEqualTo(1));
      expect(rawDollar(), findsNothing);
    });

    testWidgets('«Правильный ответ» рендерится единым виджетом CardText', (
      tester,
    ) async {
      await pumpMode(tester, '/decks/deck-1/typing', formulaFrontDeck());
      await tester.tap(
        find.byKey(const ValueKey<String>('typing-show-answer')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.byKey(const ValueKey<String>('typing-expected')),
        findsOneWidget,
      );
    });
  });

  group('Верно/Неверно', () {
    testWidgets('утверждение с формулой — Math, без сырого текста', (
      tester,
    ) async {
      await pumpMode(tester, '/decks/deck-1/true-false', formulaAnswersDeck());
      final Finder statement = find.byKey(
        const ValueKey<String>('tf-statement'),
      );
      expect(statement, findsOneWidget);
      expect(
        find.descendant(of: statement, matching: find.byType(Math)),
        findsOneWidget,
        reason: 'формула в утверждении отрисована',
      );
      expect(rawDollar(), findsNothing);
    });

    testWidgets('пояснение с формулой — Math', (tester) async {
      final List<Card> deck = formulaAnswersDeck();
      await pumpMode(tester, '/decks/deck-1/true-false', deck);
      final Map<String, TrueFalseQuestion> questions =
          <String, TrueFalseQuestion>{
            for (final TrueFalseQuestion question in buildTrueFalseQuestions(
              cards: deck,
              seed: deckId.hashCode,
            ))
              question.card.id: question,
          };
      final TrueFalseQuestion current = questions[currentCard(tester).id]!;
      // Отвечаем НЕВЕРНО, чтобы увидеть плашку с правильным ответом.
      await tester.tap(
        find.byKey(ValueKey<String>(current.isTrue ? 'tf-false' : 'tf-true')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.descendant(
          of: find.byKey(const ValueKey<String>('tf-explanation')),
          matching: find.byType(Math),
          matchRoot: true,
        ),
        findsOneWidget,
        reason: 'правильный ответ в плашке — формула',
      );
      expect(rawDollar(), findsNothing);
    });

    testWidgets('cloze-карточка не показывает сырое {{c1::…}}', (tester) async {
      final List<Card> deck = <Card>[
        card(
          'cloze',
          'Столица {{c1::Франции}} — {{c2::Париж}}',
          'Столица Франции',
          type: CardType.cloze,
        ),
        card('p-1', 'Вопрос 1', 'Митохондрия'),
        card('p-2', 'Вопрос 2', 'Рибосома'),
        card('p-3', 'Вопрос 3', 'Лизосома'),
        card('p-4', 'Вопрос 4', 'Хлоропласт'),
      ];
      await pumpMode(tester, '/decks/deck-1/true-false', deck);
      final int total = buildTrueFalseQuestions(
        cards: deck,
        seed: deckId.hashCode,
      ).length;
      expect(total, greaterThan(0));
      for (var attempt = 0; attempt < total; attempt++) {
        expect(rawCloze(), findsNothing, reason: 'сырая cloze-разметка');
        await tester.tap(
          find
                  .byKey(const ValueKey<String>('tf-true'))
                  .hitTestable()
                  .evaluate()
                  .isEmpty
              ? find.byKey(const ValueKey<String>('tf-false'))
              : find.byKey(const ValueKey<String>('tf-true')),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        final Finder next = find.byKey(const ValueKey<String>('tf-next'));
        if (next.evaluate().isEmpty) break;
        await tester.tap(next);
        await tester.pump();
      }
    });
  });

  group('Подбор пар', () {
    testWidgets('плитки с формулами рендерятся через Math', (tester) async {
      await pumpMode(tester, '/decks/deck-1/match', <Card>[
        for (var index = 0; index < 6; index++)
          card(
            'm-$index',
            <String>[
              r'Чему равно $x_0$?',
              r'Чему равно $x_1$?',
              r'Чему равно $x_2$?',
              r'Чему равно $x_3$?',
              r'Чему равно $x_4$?',
              r'Чему равно $x_5$?',
            ][index],
            <String>[
              r'$x_0 = a$',
              r'$x_1 = b$',
              r'$x_2 = c$',
              r'$x_3 = d$',
              r'$x_4 = e$',
              r'$x_5 = f$',
            ][index],
          ),
      ]);
      for (var index = 0; index < 12; index++) {
        expect(
          find.descendant(
            of: find.byKey(ValueKey<String>('match-tile-$index')),
            matching: find.byType(Math),
          ),
          findsOneWidget,
          reason: 'плитка $index с формулой',
        );
      }
      expect(rawDollar(), findsNothing, reason: 'сырой LaTeX на плитках');
    });
  });
}
