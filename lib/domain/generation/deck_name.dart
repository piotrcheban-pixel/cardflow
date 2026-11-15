/// Имя колоды по умолчанию из темы пожелания (SPEC A6.8, fix-gen Д1).
///
/// Если файлов нет, колода называется по первым словам пожелания: «Статика:
/// аксиомы и фермы» → «Статика». Длинные пожелания обрезаются. Чистые правила
/// без Flutter.
library;

/// Максимум слов в имени колоды из темы.
const int kDeckNameMaxWords = 6;

/// Максимум символов в имени колоды из темы.
const int kDeckNameMaxLength = 60;

/// Имя колоды из пожелания; пустая строка — темы нет.
String deckNameFromWishes(String? wishes, {int maxWords = kDeckNameMaxWords}) {
  final String text = wishes?.trim() ?? '';
  if (text.isEmpty) return '';
  // Первое предложение/строка: остальное — требования, а не название.
  final String firstLine = text.split(RegExp(r'[\n.!?]')).first.trim();
  final String cleaned = firstLine
      .replaceAll(RegExp(r'\s+', unicode: true), ' ')
      .replaceAll(RegExp(r'^["«]+|["»]+$'), '')
      .trim();
  if (cleaned.isEmpty) return '';
  final List<String> words = cleaned
      .split(' ')
      .where((String w) => w.isNotEmpty)
      .toList();
  var name = words
      .take(maxWords)
      .join(' ')
      .replaceAll(RegExp(r'[,:;–—-]+$'), '')
      .trim();
  if (name.length > kDeckNameMaxLength) {
    name = name.substring(0, kDeckNameMaxLength).trim();
  }
  if (name.isEmpty) return '';
  return name[0].toUpperCase() + name.substring(1);
}
