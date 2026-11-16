/// Сравнение введённого ответа с правильным (итерация 7.15).
///
/// Нормализация — `answer_normalization.dart`; несколько допустимых ответов в
/// `back` через `/`/`;`; для чисел — точное сравнение значения (`3,5` = `3.5`).
/// Опечатка распознаётся расстоянием Левенштейна: ≤ 1 для ответов до 6 символов
/// и ≤ 2 для длинных. Для UI возвращается посимвольный diff (лишнее/недостающее).
library;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/answer_normalization.dart';
import 'package:cardflow/domain/study/answer_type.dart';

/// Итог сравнения ответа.
enum AnswerMatchResult {
  /// Точное совпадение (с точностью до нормализации).
  exact,

  /// Опечатка в пределах допустимого расстояния.
  almost,

  /// Неверный ответ.
  wrong;

  /// Ответ засчитывается (точно или почти).
  bool get isCorrect => this != wrong;
}

/// Вид фрагмента diff.
enum AnswerDiffKind {
  /// Символ совпал.
  equal,

  /// Символ есть в правильном ответе, но не во введённом.
  missing,

  /// Лишний символ во введённом ответе.
  extra,
}

/// Один фрагмент посимвольного diff.
class AnswerDiffOp {
  /// Создаёт фрагмент.
  const AnswerDiffOp(this.kind, this.text);

  /// Вид фрагмента.
  final AnswerDiffKind kind;

  /// Текст фрагмента.
  final String text;

  @override
  String toString() => '${kind.name}("$text")';
}

/// Результат сравнения.
class AnswerMatch {
  /// Создаёт результат.
  const AnswerMatch({
    required this.result,
    required this.expected,
    required this.normalizedInput,
    this.diff = const <AnswerDiffOp>[],
  });

  /// Итог.
  final AnswerMatchResult result;

  /// Правильный ответ, к которому сравнивали.
  final String expected;

  /// Нормализованный ввод.
  final String normalizedInput;

  /// Посимвольный diff (только для коротких текстовых ответов).
  final List<AnswerDiffOp> diff;

  /// Ответ засчитан.
  bool get isCorrect => result.isCorrect;

  @override
  String toString() => 'AnswerMatch(${result.name}, expected: $expected)';
}

/// Сравнивает введённый ответ с карточкой.
AnswerMatch matchCardAnswer(Card card, String input) {
  return matchAnswer(
    back: card.back,
    input: input,
    type: AnswerTypes.classify(card),
  );
}

/// Сравнивает [input] с ответом [back] типа [type].
AnswerMatch matchAnswer({
  required String back,
  required String input,
  AnswerType type = AnswerType.shortText,
}) {
  final List<String> accepted = acceptedAnswers(back);
  final String normalizedInput = normalizeAnswer(input);
  if (accepted.isEmpty) {
    return AnswerMatch(
      result: AnswerMatchResult.wrong,
      expected: back,
      normalizedInput: normalizedInput,
    );
  }

  if (type == AnswerType.number) {
    final double? inputNumber = parseAnswerNumber(normalizedInput);
    for (final String answer in accepted) {
      final double? expectedNumber = parseAnswerNumber(answer);
      if (inputNumber != null &&
          expectedNumber != null &&
          inputNumber == expectedNumber) {
        return AnswerMatch(
          result: AnswerMatchResult.exact,
          expected: answer,
          normalizedInput: normalizedInput,
          diff: buildAnswerDiff(answer, normalizedInput),
        );
      }
    }
    final String best = accepted.first;
    return AnswerMatch(
      result: AnswerMatchResult.wrong,
      expected: best,
      normalizedInput: normalizedInput,
      diff: buildAnswerDiff(best, normalizedInput),
    );
  }

  String? bestExpected;
  var bestDistance = 1 << 30;
  for (final String answer in accepted) {
    final String normalizedExpected = normalizeAnswer(answer);
    if (normalizedExpected == normalizedInput) {
      return AnswerMatch(
        result: AnswerMatchResult.exact,
        expected: answer,
        normalizedInput: normalizedInput,
        diff: buildAnswerDiff(normalizedExpected, normalizedInput),
      );
    }
    final int distance = levenshteinDistance(
      normalizedExpected,
      normalizedInput,
    );
    if (distance < bestDistance) {
      bestDistance = distance;
      bestExpected = answer;
    }
  }

  final String expected = bestExpected!;
  final String normalizedExpected = normalizeAnswer(expected);
  final int threshold = normalizedExpected.runes.length <= 6 ? 1 : 2;
  final bool almost = type == AnswerType.shortText && bestDistance <= threshold;
  return AnswerMatch(
    result: almost ? AnswerMatchResult.almost : AnswerMatchResult.wrong,
    expected: expected,
    normalizedInput: normalizedInput,
    diff: type == AnswerType.shortText
        ? buildAnswerDiff(normalizedExpected, normalizedInput)
        : const <AnswerDiffOp>[],
  );
}

/// Расстояние Левенштейна (по символам Unicode, не по байтам).
int levenshteinDistance(String left, String right) {
  final List<int> a = left.runes.toList(growable: false);
  final List<int> b = right.runes.toList(growable: false);
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (int i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final int cost = a[i - 1] == b[j - 1] ? 0 : 1;
      current[j] = _min3(
        current[j - 1] + 1,
        previous[j] + 1,
        previous[j - 1] + cost,
      );
    }
    final List<int> swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Посимвольный diff правильного ответа и ввода.
///
/// `missing` — символ правильного ответа, которого нет во вводе (подсветить),
/// `extra` — лишний введённый символ (зачеркнуть).
List<AnswerDiffOp> buildAnswerDiff(String expected, String input) {
  final List<int> a = expected.runes.toList(growable: false);
  final List<int> b = input.runes.toList(growable: false);
  final List<List<int>> lcs = List<List<int>>.generate(
    a.length + 1,
    (int _) => List<int>.filled(b.length + 1, 0),
  );
  for (var i = 1; i <= a.length; i++) {
    for (var j = 1; j <= b.length; j++) {
      lcs[i][j] = a[i - 1] == b[j - 1]
          ? lcs[i - 1][j - 1] + 1
          : (lcs[i - 1][j] >= lcs[i][j - 1] ? lcs[i - 1][j] : lcs[i][j - 1]);
    }
  }

  final List<AnswerDiffOp> reversed = <AnswerDiffOp>[];
  var i = a.length;
  var j = b.length;
  while (i > 0 || j > 0) {
    if (i > 0 && j > 0 && a[i - 1] == b[j - 1]) {
      reversed.add(
        AnswerDiffOp(AnswerDiffKind.equal, String.fromCharCode(a[i - 1])),
      );
      i--;
      j--;
    } else if (j > 0 && (i == 0 || lcs[i][j - 1] >= lcs[i - 1][j])) {
      reversed.add(
        AnswerDiffOp(AnswerDiffKind.extra, String.fromCharCode(b[j - 1])),
      );
      j--;
    } else {
      reversed.add(
        AnswerDiffOp(AnswerDiffKind.missing, String.fromCharCode(a[i - 1])),
      );
      i--;
    }
  }
  final List<AnswerDiffOp> ordered = reversed.reversed.toList(growable: false);
  return _mergeDiff(ordered);
}

List<AnswerDiffOp> _mergeDiff(List<AnswerDiffOp> ops) {
  if (ops.isEmpty) return ops;
  final List<AnswerDiffOp> merged = <AnswerDiffOp>[];
  for (final AnswerDiffOp op in ops) {
    if (merged.isNotEmpty && merged.last.kind == op.kind) {
      merged[merged.length - 1] = AnswerDiffOp(
        op.kind,
        merged.last.text + op.text,
      );
    } else {
      merged.add(op);
    }
  }
  return List<AnswerDiffOp>.unmodifiable(merged);
}

int _min3(int a, int b, int c) {
  final int min = a < b ? a : b;
  return min < c ? min : c;
}
