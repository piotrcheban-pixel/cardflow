import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_type.dart';
import 'package:cardflow/domain/study/distractor_generator.dart';

/// Дистракторы из колоды (7.15).
void main() {
  const generator = DistractorGenerator();

  List<Card> deck({
    List<String> answers = const <String>[
      'Митохондрия',
      'Рибосома',
      'Хлоропласт',
      'Лизосома',
      'Гольджи',
    ],
  }) {
    return <Card>[
      for (var index = 0; index < answers.length; index++)
        Card(
          id: 'card-$index',
          deckId: 'deck-1',
          front: 'Вопрос $index?',
          back: answers[index],
          cardType: CardType.basic,
          state: CardState.newCard,
          createdAt: DateTime.utc(2026, 11, 16),
          updatedAt: DateTime.utc(2026, 11, 16),
        ),
    ];
  }

  test('три дистрактора из колоды, правильный ровно один', () {
    final cards = deck();
    final set = generator.buildQuestion(cards.first, cards)!;
    expect(set.options, hasLength(4));
    expect(set.options[set.correctIndex], 'Митохондрия');
    final Set<String> unique = set.options.toSet();
    expect(unique, hasLength(4), reason: 'без повторов');
    expect(
      set.options.where((String option) => option == 'Митохондрия'),
      hasLength(1),
    );
  });

  test('позиция правильного воспроизводима по seed', () {
    final cards = deck();
    final first = generator.buildQuestion(cards.first, cards, seed: 42)!;
    final second = generator.buildQuestion(cards.first, cards, seed: 42)!;
    expect(first.correctIndex, second.correctIndex);
    expect(first.options, second.options);
  });

  test(
    'правильный ответ не попадает в дистракторы даже при другом регистре',
    () {
      final cards = deck(
        answers: const <String>['ферма', 'мост', 'Ферма', 'балка', 'рама'],
      );
      final set = generator.buildQuestion(cards.first, cards)!;
      expect(
        set.options.where((String option) => option.toLowerCase() == 'ферма'),
        hasLength(1),
      );
    },
  );

  test('недостаточно карточек → null (карточка пропускается)', () {
    final cards = deck(answers: const <String>['ферма', 'мост']);
    expect(generator.buildQuestion(cards.first, cards), isNull);
  });

  test('ИИ-дистракторы используются, если колода мала', () {
    final cards = deck(answers: const <String>['ферма', 'мост']);
    final set = generator.buildQuestion(
      cards.first,
      cards,
      aiDistractors: const <String>['арка', 'рама', 'балка'],
    )!;
    expect(set.options, hasLength(4));
    expect(set.correctIndex, isNot(-1));
  });

  test('ИИ-дистракторы фильтруются: дубликат правильного и пустые', () {
    final cards = deck(answers: const <String>['ферма', 'мост']);
    final set = generator.buildQuestion(
      cards.first,
      cards,
      aiDistractors: const <String>['ФЕРМА', '  ', 'арка'],
    );
    expect(set, isNull, reason: 'остался только один дистрактор');
  });

  test('числа: та же единица и правдоподобная размерность', () {
    final cards = deck(
      answers: const <String>[
        '10 м/с',
        '20 м/с',
        '2 м/с',
        '5 м/с',
        '5000 кг',
        '30 км/ч',
      ],
    );
    final set = generator.buildQuestion(cards.first, cards)!;
    final Set<String> options = set.options.toSet();
    expect(options, hasLength(4));
    expect(set.options[set.correctIndex], '10 м/с');
    for (final String option in options) {
      expect(option, endsWith('м/с'), reason: 'другие единицы не подходят');
    }
  });

  test('формулы и длинные ответы — вопрос не строится', () {
    final formula = Card(
      id: 'f',
      deckId: 'd',
      front: 'Формула?',
      back: r'$a^2 + b^2 = c^2$',
      cardType: CardType.basic,
      state: CardState.newCard,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );
    expect(generator.buildQuestion(formula, <Card>[formula]), isNull);
  });

  test('тип ответа дистракторов совпадает с типом карточки', () {
    final cards = deck(
      answers: const <String>['3,5', '4,5', '5,5', '6,5', '7,5'],
    );
    final set = generator.buildQuestion(cards.first, cards)!;
    expect(
      set.options.every(
        (String answer) =>
            AnswerTypes.classifyAnswer('?', answer) == AnswerType.number,
      ),
      isTrue,
    );
  });
}
