/// Нормализация текста для сравнения (этап Ingestion, ADR-050).
///
/// Сравнение материала (дедупликация карточек, сверка цитат) не должно зависеть
/// от типографских различий: «ё»/«е», «кавычки-ёлочки»/прямые кавычки,
/// длинное тире/дефис, повторные пробелы. Поэтому у блока есть
/// `Block.normalizedText`, а якоря (`start`/`end`) считаются **по исходному**
/// тексту: нормализация меняет длину строки и для offsets не годится.
///
/// Функции чистые и идемпотентные: `normalize(normalize(x)) == normalize(x)`.
library;

/// Пробельные символы, включая нулевой ширины: любой пробел → один `' '`.
final RegExp _spaceRun = RegExp(r'[\s\u200B\u200C\u200D\u2060\uFEFF]+');

/// Кавычки-двойники: «ёлочки», „лапки“, “английские”, ‟, ″, 〝〞〟.
final RegExp _doubleQuote = RegExp('[«»„“”‟″〝〞〟]');

/// Кавычки-одиночки и примы: ‘одинарные’, ‚лапки‘, ‛, ′, обратный апостроф, ´.
final RegExp _singleQuote = RegExp('[‘’‚‛′`´]');

/// Тире и дефисы (все виды) и мягкий перенос, который удаляется.
final RegExp _dash = RegExp('[‐‑‒–—―−⁃\u00AD]');

/// Мягкий перенос (U+00AD): невидим, при сравнении должен исчезнуть.
const String _softHyphen = '\u00AD';

/// Нормализатор текста для сравнения.
class ContentNormalizer {
  /// Создаёт нормализатор (без состояния).
  const ContentNormalizer();

  /// Полная нормализация: пробелы → ё → кавычки → дефисы.
  ///
  /// Порядок шагов важен только для читаемости: каждое преобразование
  /// действует на свой набор символов, взаимных пересечений нет.
  String normalize(String text) =>
      normalizeDashes(normalizeQuotes(normalizeYo(normalizeWhitespace(text))));

  /// Пробелы: любой пробельный символ (включая NBSP, типографские пробелы и
  /// символы нулевой ширины) → `' '`; повторы схлопываются; края обрезаются.
  String normalizeWhitespace(String text) =>
      text.replaceAll(_spaceRun, ' ').trim();

  /// `ё`/`Ё` → `е`/`Е` (поиск не должен зависеть от буквы «ё»).
  String normalizeYo(String text) =>
      text.replaceAll('ё', 'е').replaceAll('Ё', 'Е');

  /// Кавычки: «ёлочки», „лапки“, “английские” → `"`; ‘одинарные’, ‚лапки‘,
  /// ‛, ′, ` и ´ → `'`. Прямые кавычки не меняются.
  String normalizeQuotes(String text) =>
      text.replaceAll(_doubleQuote, '"').replaceAll(_singleQuote, "'");

  /// Тире и дефисы (‐ ‑ ‒ – — ― − ⁃) → `-`; мягкий перенос (U+00AD) удаляется.
  String normalizeDashes(String text) => text.replaceAllMapped(
    _dash,
    (Match match) => match[0] == _softHyphen ? '' : '-',
  );
}
