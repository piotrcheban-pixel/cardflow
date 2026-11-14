/// Локальная оценка объёма текста в токенах (SPEC A8.5 шаг 4, ADR-015).
///
/// Это эвристика для UI и нарезки, а не биллинг: фактический расход приходит
/// из ответа провайдера (`TokenUsage`). Домен не зависит от Flutter.
library;

/// Оценщик токенов для русского и смешанного текста.
///
/// Эвристика: в среднем один токен приходится примерно на
/// [charsPerToken] символа (для кириллицы токенизаторы чаще дают 2–3 символа
/// на токен). Оценка намеренно консервативная: лучше нарезать мельче, чем
/// получить обрезанный ответ.
class TokenEstimator {
  /// Создаёт оценщик.
  const TokenEstimator({this.charsPerToken = 2.5});

  /// Сколько символов в среднем приходится на один токен.
  final double charsPerToken;

  /// Оценивает количество токенов в [text]; пустой текст — 0.
  int estimate(String text) {
    if (text.isEmpty) return 0;
    return (text.runes.length / charsPerToken).ceil();
  }

  /// Суммарная оценка нескольких фрагментов.
  int estimateAll(Iterable<String> texts) {
    var total = 0;
    for (final text in texts) {
      total += estimate(text);
    }
    return total;
  }
}
