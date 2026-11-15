/// Санитизация локально извлечённого текста (SPEC A8.3, итерации 7.8/7.10).
///
/// Единственный санитайзер для парсеров и API-слоя: убирает управляющие
/// символы (ASCII и Unicode Cc/Cf — PDFium отдаёт C1-управляющие), одиночные
/// суррогаты (невалидный UTF-16 → невалидный UTF-8 в запросе), которые API
/// провайдеров отвергают как «invalid characters in content»; нормализует
/// переводы строк, схлопывает пустые строки и обрезает пробелы. Один и тот же
/// вход даёт один и тот же выход, поэтому `content_hash` карточек не меняется.
library;

/// Неразрывный пробел.
const int _nbsp = 0x00A0;

/// Перевод строки.
const int _lineFeed = 0x0A;

/// Табуляция.
const int _tab = 0x09;

/// Три и более перевода строки подряд (две и более пустых строки).
final RegExp _excessBlankLines = RegExp(r'\n{3,}');

/// Хвостовые пробелы и табы в строке.
final RegExp _trailingWhitespace = RegExp(r'[ \t]+$');

/// Санитайзер извлечённого текста.
class TextSanitizer {
  /// Создаёт санитайзер.
  const TextSanitizer();

  /// Приводит текст к канонической форме.
  ///
  /// `\r\n`/`\r` → `\n`; разделители строк `U+2028`/`U+2029` → `\n`;
  /// управляющие символы Unicode (Cc/Cf, кроме `\t`, `\n`), одиночные
  /// суррогаты и BOM удаляются; неразрывный пробел → обычный; хвостовые
  /// пробелы строк убираются; три и более перевода строки подряд сжимаются до
  /// двух; края обрезаются.
  String sanitize(String input) {
    var text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll('\u2028', '\n').replaceAll('\u2029', '\n');
    text = stripNonPrintable(text);
    text = text.replaceAll('\u00A0', ' ');
    text = text
        .split('\n')
        .map((String line) => line.replaceAll(_trailingWhitespace, ''))
        .join('\n');
    text = text.replaceAll(_excessBlankLines, '\n\n');
    return text.trim();
  }

  /// Удаляет непечатаемые символы Unicode и одиночные суррогаты.
  ///
  /// Сохраняются `\t`, `\n` и неразрывный пробел (его нормализует [sanitize]);
  /// корректные суррогатные пары (эмодзи, редкие иероглифы) не трогаются.
  String stripNonPrintable(String input) {
    final List<int> units = input.codeUnits;
    final StringBuffer buffer = StringBuffer();
    for (var index = 0; index < units.length; index++) {
      final int unit = units[index];
      if (_isHighSurrogate(unit)) {
        if (index + 1 < units.length && _isLowSurrogate(units[index + 1])) {
          buffer
            ..writeCharCode(unit)
            ..writeCharCode(units[index + 1]);
          index++;
        }
        continue;
      }
      if (_isLowSurrogate(unit)) continue;
      if (_isNonPrintable(unit)) continue;
      buffer.writeCharCode(unit);
    }
    return buffer.toString();
  }

  /// true, если после санитизации текста не остаётся.
  bool isEmpty(String input) => sanitize(input).isEmpty;

  static bool _isHighSurrogate(int unit) => unit >= 0xD800 && unit <= 0xDBFF;

  static bool _isLowSurrogate(int unit) => unit >= 0xDC00 && unit <= 0xDFFF;

  /// Непечатаемый символ (Cc/Cf, кроме `\t`, `\n` и NBSP).
  static bool _isNonPrintable(int unit) {
    if (unit == _tab || unit == _lineFeed || unit == _nbsp) return false;
    if (unit <= 0x1F) return true;
    if (unit == 0x7F) return true;
    // C1-управляющие: PDFium отдаёт их из PDF как есть.
    if (unit >= 0x80 && unit <= 0x9F) return true;
    if (unit == 0x00AD) return true;
    // Zero-width и bidi-марки.
    if (unit >= 0x200B && unit <= 0x200F) return true;
    if (unit >= 0x202A && unit <= 0x202E) return true;
    if (unit >= 0x2060 && unit <= 0x206F) return true;
    // BOM и несимволы.
    if (unit == 0xFEFF) return true;
    if (unit >= 0xFFF9 && unit <= 0xFFFB) return true;
    if (unit == 0xFFFE || unit == 0xFFFF) return true;
    return false;
  }
}
