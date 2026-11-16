/// Тип ответа карточки и пригодность для ввода (итерация 7.15).
///
/// `AnswerType.classify(card)` возвращает `short_text`, `number`, `formula` или
/// `long_text`. В режим «Ввод ответа» и в «Тест» (дистракторы из колоды) идут
/// только `short_text` и `number`: ответ не длиннее ~60 символов и 6 слов, без
/// LaTeX и переносов строк. Остальные карточки в этих режимах пропускаются.
library;

import 'package:cardflow/domain/cards/card.dart';

/// Тип ответа карточки.
enum AnswerType {
  /// Короткий текстовый ответ (одно-два слова).
  shortText('short_text'),

  /// Число (в том числе с десятичной запятой).
  number('number'),

  /// Формула/LaTeX — вводом не проверяется.
  formula('formula'),

  /// Длинный текст или многострочный ответ.
  longText('long_text');

  const AnswerType(this.wireName);

  /// Стабильное значение для диагностики/тестов.
  final String wireName;

  /// Подходит ли тип для ввода ответа вручную.
  bool get isTypable => this == shortText || this == number;
}

/// Максимальная длина ответа для ввода.
const int kMaxTypedAnswerLength = 60;

/// Максимальное число слов ответа для ввода.
const int kMaxTypedAnswerWords = 6;

/// Классификация и правила пригодности ответа.
abstract final class AnswerTypes {
  static final RegExp _numberPattern = RegExp(r'^[-+]?\d+(?:[.,]\d+)?$');
  static final RegExp _latexCommand = RegExp(r'\\[a-zA-Z]+|\$');
  static final RegExp _whitespace = RegExp(r'\s+');

  /// Тип ответа карточки [card].
  static AnswerType classify(Card card) =>
      classifyAnswer(card.front, card.back, cardType: card.cardType);

  /// Тип ответа по сторонам карточки.
  static AnswerType classifyAnswer(
    String front,
    String back, {
    CardType cardType = CardType.basic,
  }) {
    final String answer = back.trim();
    // Cloze: ответ — пропуск в front, а не back; для ввода не пригоден.
    if (cardType == CardType.cloze) return AnswerType.longText;
    if (answer.isEmpty) return AnswerType.longText;
    if (answer.contains(r'$') || _latexCommand.hasMatch(answer)) {
      return AnswerType.formula;
    }
    if (_numberPattern.hasMatch(answer)) return AnswerType.number;
    if (answer.contains('\n')) return AnswerType.longText;
    if (answer.length > kMaxTypedAnswerLength) return AnswerType.longText;
    final List<String> words = answer
        .split(_whitespace)
        .where((String word) => word.isNotEmpty)
        .toList(growable: false);
    if (words.length > kMaxTypedAnswerWords) return AnswerType.longText;
    return AnswerType.shortText;
  }

  /// Можно ли вводить ответ этой карточки вручную (Тест/Ввод).
  static bool isTypable(Card card) => classify(card).isTypable;
}
