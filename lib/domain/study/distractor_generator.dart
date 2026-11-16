/// Дистракторы для режима «Тест» и «Верно/Неверно» (итерация 7.15).
///
/// Три неверных ответа берутся из той же колоды и того же типа ответа, близких
/// по длине; числа — правдоподобные значения той же размерности и единиц.
/// Правильный ответ и дубликаты (после нормализации) исключаются. Позиция
/// правильного ответа случайна, но воспроизводима по seed.
///
/// Если в колоде меньше 4 подходящих ответов, генератор принимает дистракторы
/// от ИИ (`aiDistractors`, batch-запрос на колоду) и кэширует их вызывающим
/// слоем. Если и их не хватает — карточка пропускается в Тесте
/// (`buildQuestion == null`).
library;

import 'dart:math' as math;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_normalization.dart';
import 'package:cardflow/domain/study/answer_type.dart';

/// Готовый вопрос Теста: варианты и индекс правильного.
class DistractorSet {
  /// Создаёт набор.
  const DistractorSet({required this.options, required this.correctIndex});

  /// Варианты ответа (правильный + три дистрактора).
  final List<String> options;

  /// Индекс правильного варианта (0..3).
  final int correctIndex;
}

/// Генератор вариантов ответа.
class DistractorGenerator {
  /// Создаёт генератор.
  const DistractorGenerator();

  /// Строит вопрос для [card] из [deck]; `null` — недостаточно дистракторов.
  ///
  /// [seed] фиксирует перемешивание (в тестах), [aiDistractors] — ответ
  /// batch-запроса к ИИ для колод с малым числом подходящих ответов.
  ///
  /// Формульные ответы допускаются (7.17, ADR-034): в «Тесте» ответ выбирают,
  /// а не печатают, поэтому LaTeX-ответ — полноценный вариант. Длинные ответы
  /// (`long_text`) по-прежнему не годятся для кнопок.
  DistractorSet? buildQuestion(
    Card card,
    List<Card> deck, {
    int seed = 0,
    List<String> aiDistractors = const <String>[],
  }) {
    final AnswerType type = AnswerTypes.classify(card);
    if (!AnswerTypes.isChoice(card)) return null;
    final String correct = card.back.trim();
    if (correct.isEmpty) return null;

    final List<String> distractors = _pickDistractors(
      card,
      deck,
      type: type,
      correct: correct,
      aiDistractors: aiDistractors,
    );
    if (distractors.length < 3) return null;

    final List<String> options = <String>[correct, ...distractors.take(3)];
    final math.Random random = math.Random(seed ^ card.id.hashCode);
    options.shuffle(random);
    return DistractorSet(
      options: List<String>.unmodifiable(options),
      correctIndex: options.indexOf(correct),
    );
  }

  /// Кандидаты из колоды и ИИ, отсортированные по близости длины.
  List<String> _pickDistractors(
    Card card,
    List<Card> deck, {
    required AnswerType type,
    required String correct,
    required List<String> aiDistractors,
  }) {
    final String normalizedCorrect = normalizeAnswer(correct);
    final Set<String> seen = <String>{normalizedCorrect};
    final List<String> candidates = <String>[];
    for (final Card other in deck) {
      if (other.id == card.id) continue;
      if (AnswerTypes.classify(other) != type) continue;
      final String answer = other.back.trim();
      if (answer.isEmpty) continue;
      if (answer.length > kMaxChoiceAnswerLength) continue;
      final String normalized = normalizeAnswer(answer);
      if (!seen.add(normalized)) continue;
      if (!_compatible(answer, correct, type)) continue;
      candidates.add(answer);
    }
    for (final String answer in aiDistractors) {
      final String trimmed = answer.trim();
      if (trimmed.isEmpty) continue;
      final String normalized = normalizeAnswer(trimmed);
      if (normalized == normalizedCorrect) continue;
      if (!seen.add(normalized)) continue;
      candidates.add(trimmed);
    }
    candidates.sort(
      (String a, String b) => (a.length - correct.length).abs().compareTo(
        (b.length - correct.length).abs(),
      ),
    );
    return candidates;
  }

  /// Совместим ли кандидат с правильным ответом (длина, единицы, размерность).
  bool _compatible(String candidate, String correct, AnswerType type) {
    if (type == AnswerType.number) {
      final ({double? value, String unit}) left = _numberParts(candidate);
      final ({double? value, String unit}) right = _numberParts(correct);
      if (left.value == null || right.value == null) return false;
      if (left.unit != right.unit) return false;
      if (left.value == right.value) return false;
      final double ratio = right.value == 0
          ? left.value!.abs()
          : (left.value!.abs() / right.value!.abs());
      return ratio >= 0.01 && ratio <= 100;
    }
    final int lengthDelta = (candidate.length - correct.length).abs();
    return lengthDelta <= math.max(4, correct.length ~/ 2 + 2);
  }

  /// Числовая часть и единицы ответа (`10 м/с` → 10, `м/с`).
  ({double? value, String unit}) _numberParts(String value) {
    final String trimmed = value.trim();
    final Match? match = RegExp(r'^([-+]?\d+(?:[.,]\d+)?)\s*(.*)$')
        .firstMatch(trimmed);
    if (match == null) return (value: null, unit: '');
    final double? number = parseAnswerNumber(match.group(1)!);
    final String unit = match
        .group(2)!
        .toLowerCase()
        .replaceAll(RegExp(r'\s+'), '')
        .trim();
    return (value: number, unit: unit);
  }
}
