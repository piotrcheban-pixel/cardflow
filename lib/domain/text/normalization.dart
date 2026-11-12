/// Нормализация пользовательского текста для сравнения (SPEC A5, A8.5).
///
/// Правило дедупликации и поиска: нижний регистр, `ё` → `е`, пунктуация
/// отбрасывается, повторные пробелы сжимаются. Одна функция на весь проект,
/// чтобы `content_hash` и поиск сравнивали текст одинаково.
library;

final RegExp _punctuation = RegExp(r'[^\p{L}\p{N}\s]', unicode: true);
final RegExp _whitespace = RegExp(r'\s+', unicode: true);

/// Приводит текст к нормализованной форме для сравнения.
String normalizeForComparison(String value) {
  final lower = value.toLowerCase().replaceAll('ё', 'е');
  final withoutPunctuation = lower.replaceAll(_punctuation, ' ');
  return withoutPunctuation.replaceAll(_whitespace, ' ').trim();
}
