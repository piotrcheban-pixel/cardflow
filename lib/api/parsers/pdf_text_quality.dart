/// Проверка «нечитаемого» текста из PDF (ADR-024, итерация 7.10).
///
/// PDFium отдаёт из битого ToUnicode-словаря символы замены `U+FFFD` и
/// одиночные суррогаты; такой текст ломает запрос к API провайдера. Проверка
/// нормализует текст через UTF-8 (невалидный UTF-16 → `U+FFFD`) и считает
/// долю замен: много замен — файл считается нечитаемым.
library;

import 'dart:convert';

/// Проверка читаемости текста, извлечённого из PDF.
class PdfTextQuality {
  /// Создаёт проверку.
  const PdfTextQuality({
    this.minReplacementChars = 5,
    this.maxReplacementRatio = 0.05,
  });

  /// Минимальное число замен, ниже которого текст считается читаемым.
  final int minReplacementChars;

  /// Максимальная допустимая доля замен (строго больше — нечитаемо).
  final double maxReplacementRatio;

  /// Символ замены Unicode.
  static const int _replacementChar = 0xFFFD;

  /// Нормализует текст через UTF-8: одиночные суррогаты → `U+FFFD`.
  String utf8Normalized(String text) => utf8.decode(utf8.encode(text));

  /// true, если текст из PDF считается нечитаемым.
  ///
  /// Нечитаемым считается текст, где замен не меньше [minReplacementChars]
  /// и их доля строго больше [maxReplacementRatio].
  bool isUnreadable(String text) {
    final String normalized = utf8Normalized(text);
    if (normalized.isEmpty) return false;
    var replacements = 0;
    for (final int unit in normalized.codeUnits) {
      if (unit == _replacementChar) replacements++;
    }
    if (replacements < minReplacementChars) return false;
    final int length = normalized.runes.length;
    if (length == 0) return false;
    return replacements / length > maxReplacementRatio;
  }
}
