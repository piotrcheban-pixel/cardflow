/// Извлечение и проверка LaTeX-формул (SPEC A8.4: «попытаться распарсить
/// формулы `flutter_math_fork`; при ошибке пометить карточку, не отбрасывать»).
library;

import 'package:flutter_math_fork/flutter_math.dart';

/// Извлекает полные формулы `$$…$$` (блок) и `$…$` (строка) из [text].
///
/// Незакрытые разделители в список не попадают — их наличие проверяет
/// [latexIsValid]. Пустые формулы пропускаются.
List<String> extractLatexFormulas(String text) {
  final formulas = <String>[];
  var index = 0;
  while (index < text.length) {
    if (text.startsWith(r'\$', index)) {
      index += 2;
      continue;
    }
    if (text.startsWith(r'$$', index)) {
      final end = text.indexOf(r'$$', index + 2);
      if (end < 0) break;
      final expression = text.substring(index + 2, end).trim();
      if (expression.isNotEmpty) formulas.add(expression);
      index = end + 2;
    } else if (text[index] == r'$') {
      final end = text.indexOf(r'$', index + 1);
      if (end < 0) break;
      final expression = text.substring(index + 1, end).trim();
      if (expression.isNotEmpty) formulas.add(expression);
      index = end + 1;
    } else {
      index++;
    }
  }
  return formulas;
}

/// Валиден ли LaTeX в [text]: все формулы парсятся `flutter_math_fork`,
/// незакрытых разделителей нет.
bool latexIsValid(String text) {
  var index = 0;
  while (index < text.length) {
    if (text.startsWith(r'\$', index)) {
      index += 2;
      continue;
    }
    if (text.startsWith(r'$$', index)) {
      final end = text.indexOf(r'$$', index + 2);
      if (end < 0) return false;
      final expression = text.substring(index + 2, end).trim();
      if (expression.isNotEmpty && !isLatexExpressionParsable(expression)) {
        return false;
      }
      index = end + 2;
    } else if (text[index] == r'$') {
      final end = text.indexOf(r'$', index + 1);
      if (end < 0) return false;
      final expression = text.substring(index + 1, end).trim();
      if (expression.isNotEmpty && !isLatexExpressionParsable(expression)) {
        return false;
      }
      index = end + 1;
    } else {
      index++;
    }
  }
  return true;
}

/// Парсится ли одно LaTeX-выражение (без рендера, через `Math.tex`).
///
/// Публичный способ `flutter_math_fork`: конструктор `Math.tex` разбирает
/// выражение и складывает ошибку в `parseError` (спайк S2, итерация 3b).
bool isLatexExpressionParsable(String expression) {
  try {
    return Math.tex(expression).parseError == null;
  } on Object {
    return false;
  }
}
