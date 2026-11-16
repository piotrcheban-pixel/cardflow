import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/true_false_question.dart';

/// Вопросы «Верно/Неверно» (7.16).
void main() {
  Card card(String id, String front, String back) => Card(
    id: id,
    deckId: 'deck-1',
    front: front,
    back: back,
    cardType: CardType.basic,
    state: CardState.newCard,
    createdAt: DateTime.utc(2026, 11, 16),
    updatedAt: DateTime.utc(2026, 11, 16),
  );

  final List<Card> deck = <Card>[
    card('a', 'Органоид?', 'Митохондрия'),
    card('b', 'Органоид 2?', 'Рибосома'),
    card('c', 'Органоид 3?', 'Лизосома'),
  ];

  test('утверждение — правильный ответ или дистрактор из колоды', () {
    for (var seed = 0; seed < 8; seed++) {
      final question = buildTrueFalseQuestion(
        card: deck.first,
        deck: deck,
        seed: seed,
      )!;
      expect(<String>[
        'Митохондрия',
        'Рибосома',
        'Лизосома',
      ], contains(question.shownAnswer));
      if (question.isTrue) {
        expect(question.shownAnswer, 'Митохондрия');
      } else {
        expect(question.shownAnswer, isNot('Митохондрия'));
      }
    }
  });

  test('50/50 воспроизводимо по seed', () {
    for (var seed = 0; seed < 4; seed++) {
      final first = buildTrueFalseQuestion(
        card: deck.first,
        deck: deck,
        seed: seed,
      )!;
      final second = buildTrueFalseQuestion(
        card: deck.first,
        deck: deck,
        seed: seed,
      )!;
      expect(first.isTrue, second.isTrue);
      expect(first.shownAnswer, second.shownAnswer);
    }
  });

  test('нет другого ответа — вопрос не строится', () {
    final single = <Card>[card('only', 'Вопрос?', 'Ответ')];
    expect(buildTrueFalseQuestion(card: single.first, deck: single), isNull);
    expect(hasTrueFalseAlternative(single.first, single), isFalse);
  });

  // 7.17, ADR-034: формула — допустимый дистрактор, иначе формат утверждения
  // выдаёт, верно оно или нет (формула/обычный ответ).
  test('формульный ответ годится в дистракторы', () {
    final formulaDeck = <Card>[
      card('a', 'Вопрос 1', r'$x_1 = b$'),
      card('b', 'Вопрос 2', r'$x_0 = a$'),
    ];
    expect(hasTrueFalseAlternative(formulaDeck[1], formulaDeck), isTrue);
    for (var seed = 0; seed < 4; seed++) {
      final TrueFalseQuestion question = buildTrueFalseQuestion(
        card: formulaDeck[1],
        deck: formulaDeck,
        seed: seed,
      )!;
      expect(
        question.shownAnswer,
        contains(r'$'),
        reason: 'утверждение в том же формате, что и ответы колоды',
      );
    }
  });

  test('вопросы для колоды: только карточки с альтернативой', () {
    final mixed = <Card>[
      deck.first,
      deck[1],
      card('empty', 'Вопрос без ответа?', ''),
      card('long', 'Вопрос?', r'$x^2$'),
    ];
    final questions = buildTrueFalseQuestions(cards: mixed);
    // 'a' и 'b' — вопросы с короткими ответами; 'long' тоже получает вопрос
    // (утверждение может быть формулой, дистрактор — короткий ответ), 'empty'
    // исключён: нет правильного ответа.
    expect(questions, hasLength(3));
    expect(questions.map((question) => question.card.id), <String>[
      'a',
      'b',
      'long',
    ]);
  });
}
