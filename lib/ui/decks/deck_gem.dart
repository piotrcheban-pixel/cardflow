/// Имя 3D-аватара колоды по стабильному хешу идентификатора (§5.4).
///
/// FNV-1a, а не `String.hashCode`: значение обязано совпадать между запусками,
/// иначе golden-снимки и переходы Hero будут различаться от прогона к прогону.
String deckGemName(String deckId) {
  var hash = 0x811C9DC5;
  for (final int unit in deckId.codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return 'deck_gem_${hash % 8 + 1}';
}
