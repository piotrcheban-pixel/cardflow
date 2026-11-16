/// Вопрос режима «Верно/Неверно» (итерация 7.16).
///
/// Показывается front карточки и утверждение: либо правильный ответ, либо
/// дистрактор (50/50, воспроизводимо по seed). Игрок отвечает «верно» или
/// «неверно»; FSRS пишется только для due-карточек (ADR-032).
library;

import 'dart:math' as math;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_type.dart';

/// Один вопрос «Верно/Неверно».
class TrueFalseQuestion {
  /// Создаёт вопрос.
  const TrueFalseQuestion({
    required this.card,
    required this.shownAnswer,
    required this.isTrue,
  });

  /// Карточка (показывается front).
  final Card card;

  /// Показанное утверждение (правильный ответ или дистрактор).
  final String shownAnswer;

  /// Утверждение верное.
  final bool isTrue;
}

/// Строит вопрос для карточки; `null` — нет альтернативного ответа.
TrueFalseQuestion? buildTrueFalseQuestion({
  required Card card,
  required List<Card> deck,
  int seed = 0,
}) {
  final String answer = card.back.trim();
  if (answer.isEmpty) return null;
  final String alternative = _alternativeAnswer(card, deck, seed: seed);
  if (alternative.isEmpty) return null;
  final math.Random random = math.Random(seed ^ card.id.hashCode);
  final bool isTrue = random.nextBool();
  return TrueFalseQuestion(
    card: card,
    shownAnswer: isTrue ? answer : alternative,
    isTrue: isTrue,
  );
}

/// Может ли для карточки быть построен вопрос (есть другой ответ в колоде).
bool hasTrueFalseAlternative(Card card, List<Card> deck) {
  if (card.back.trim().isEmpty) return false;
  return _alternativeAnswer(card, deck, seed: 0).isNotEmpty;
}

String _alternativeAnswer(Card card, List<Card> deck, {required int seed}) {
  final String correct = card.back.trim();
  final List<String> candidates = <String>[];
  for (final Card other in deck) {
    if (other.id == card.id) continue;
    final String answer = other.back.trim();
    if (answer.isEmpty) continue;
    if (answer == correct) continue;
    if (!AnswerTypes.isTypable(other)) {
      // Для «Верно/Неверно» длинные ответы тоже допустимы, но дистрактор
      // должен быть правдоподобным: берём только короткие/числа.
      continue;
    }
    candidates.add(answer);
  }
  if (candidates.isEmpty) return '';
  candidates.sort();
  return candidates[math.Random(seed ^ card.id.hashCode)
      .nextInt(candidates.length)];
}

/// Строит вопросы для колоды (карточки с доступным дистрактором).
List<TrueFalseQuestion> buildTrueFalseQuestions({
  required List<Card> cards,
  int seed = 0,
}) {
  final List<TrueFalseQuestion> questions = <TrueFalseQuestion>[];
  for (final Card card in cards) {
    final TrueFalseQuestion? question = buildTrueFalseQuestion(
      card: card,
      deck: cards,
      seed: seed,
    );
    if (question != null) questions.add(question);
  }
  return questions;
}
