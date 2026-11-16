import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_type.dart';

/// Тип ответа и пригодность для ввода (7.15).
void main() {
  test('короткий текст — short_text и пригоден для ввода', () {
    final card = _card(
      front: 'Какой органоид синтезирует АТФ?',
      back: 'Митохондрия',
    );
    expect(AnswerTypes.classify(card), AnswerType.shortText);
    expect(AnswerTypes.isTypable(card), isTrue);
  });

  test('число с запятой — number', () {
    expect(
      AnswerTypes.classify(_card(front: 'Чему равно?', back: '3,5')),
      AnswerType.number,
    );
    expect(
      AnswerTypes.classify(_card(front: 'Сколько?', back: '-12')),
      AnswerType.number,
    );
  });

  test('LaTeX — formula, не пригоден для ввода', () {
    final card = _card(
      front: 'Формула момента?',
      back: r'$M_z = x F_y - y F_x$',
    );
    expect(AnswerTypes.classify(card), AnswerType.formula);
    expect(AnswerTypes.isTypable(card), isFalse);
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: r'\alpha + \beta')),
      AnswerType.formula,
    );
  });

  // 7.17, ADR-034: `\(…\)`/`\[…\]` — те же разделители, что у `LatexMarkup`;
  // раньше такой ответ считался обычным текстом и попадал в «Ввод ответа».
  test(r'\(…\) и \[…\] — тоже formula', () {
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: r'\(x^2 + y^2\)')),
      AnswerType.formula,
    );
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: r'\[a + b\]')),
      AnswerType.formula,
    );
  });

  test('формула годится для выбора в «Тесте», но не для ввода', () {
    final card = _card(front: 'Формула?', back: r'$E=mc^2$');
    expect(AnswerTypes.isChoice(card), isTrue);
    expect(AnswerTypes.isTypable(card), isFalse);
  });

  test('длинная формула (> 120 символов) не показывается вариантом', () {
    final String longFormula = '\$${'a' * 119}\$';
    expect(longFormula.length, greaterThan(kMaxChoiceAnswerLength));
    final card = _card(front: 'Вопрос', back: longFormula);
    expect(AnswerTypes.classify(card), AnswerType.formula);
    expect(AnswerTypes.isChoice(card), isFalse);
  });

  test('cloze и длинный текст не годятся для выбора', () {
    expect(
      AnswerTypes.isChoice(
        _card(
          front: 'Столица — {{c1::Париж}}',
          back: '',
          cardType: CardType.cloze,
        ),
      ),
      isFalse,
    );
    expect(
      AnswerTypes.isChoice(_card(front: 'Вопрос', back: 'а' * 61)),
      isFalse,
    );
  });

  test('длинный/многострочный ответ — long_text', () {
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: 'а' * 61)),
      AnswerType.longText,
    );
    expect(
      AnswerTypes.classify(
        _card(front: 'Вопрос', back: 'одно два три четыре пять шесть семь'),
      ),
      AnswerType.longText,
    );
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: 'Строка\nвторая')),
      AnswerType.longText,
    );
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: '   ')),
      AnswerType.longText,
    );
  });

  test('границы: 60 символов и 6 слов ещё пригодны', () {
    expect(
      AnswerTypes.classify(_card(front: 'Вопрос', back: 'а' * 60)),
      AnswerType.shortText,
    );
    expect(
      AnswerTypes.classify(
        _card(front: 'Вопрос', back: 'один два три четыре пять шесть'),
      ),
      AnswerType.shortText,
    );
  });

  test('cloze не пригоден: ответ — пропуск во front', () {
    final card = _card(
      front: 'Столица Франции — {{c1::Париж}}',
      back: '',
      cardType: CardType.cloze,
    );
    expect(AnswerTypes.classify(card), AnswerType.longText);
    expect(AnswerTypes.isTypable(card), isFalse);
  });
}

Card _card({
  required String front,
  required String back,
  CardType cardType = CardType.basic,
}) {
  return Card(
    id: 'card-${front.hashCode}',
    deckId: 'deck-1',
    front: front,
    back: back,
    cardType: cardType,
    state: CardState.newCard,
    createdAt: DateTime.utc(2026, 11, 16),
    updatedAt: DateTime.utc(2026, 11, 16),
  );
}
