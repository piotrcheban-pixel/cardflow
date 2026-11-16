/// Нормализация ответов для сравнения (итерация 7.15).
///
/// Правила (SPEC/задание 7.15): Unicode NFC, нижний регистр, `ё` → `е`,
/// сжатые пробелы, без пунктуации по краям. Несколько допустимых ответов в
/// `back` разделяются `/` или `;`.
library;

import 'package:unorm_dart/unorm_dart.dart' as unorm;

/// Символы пунктуации, которые срезаются по краям ответа.
const String _edgePunctuation = '.,;:!?…«»„“”"\'`()[]{}—–-';

/// Приводит ответ к сравнимому виду.
String normalizeAnswer(String value) {
  final String nfc = unorm.nfc(value);
  var text = nfc.toLowerCase().replaceAll('ё', 'е').replaceAll('\u00A0', ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  // Срезаем пунктуацию по краям (по одному символу за проход).
  while (text.isNotEmpty && _edgePunctuation.contains(text[0])) {
    text = text.substring(1).trimLeft();
  }
  while (text.isNotEmpty && _edgePunctuation.contains(text[text.length - 1])) {
    text = text.substring(0, text.length - 1).trimRight();
  }
  return text;
}

/// Разбирает `back` на список допустимых ответов (`/`, `;`).
///
/// Дробь вида `3/4` не делится: иначе число превратится в два ответа.
List<String> acceptedAnswers(String back) {
  final String trimmed = back.trim();
  if (trimmed.isEmpty) return const <String>[];
  if (RegExp(r'^\d+\s*/\s*\d+$').hasMatch(trimmed)) {
    return <String>[trimmed];
  }
  final List<String> parts = trimmed
      .split(RegExp(r'\s*[;/]\s*'))
      .map((String part) => part.trim())
      .where((String part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? <String>[trimmed] : parts;
}

/// Разбирает число из ответа (`3,5` = `3.5`); `null` — не число.
double? parseAnswerNumber(String value) {
  final String text = value.trim().replaceAll(',', '.');
  if (!RegExp(r'^[-+]?\d+(?:\.\d+)?$').hasMatch(text)) return null;
  return double.tryParse(text);
}
