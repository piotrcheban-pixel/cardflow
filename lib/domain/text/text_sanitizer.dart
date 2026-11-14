/// Санитизация локально извлечённого текста (SPEC A8.3, итерация 7.8).
///
/// Единственный санитайзер для парсеров и API-слоя: убирает управляющие
/// символы (NUL, вертикальная табуляция и т.п.), которые API провайдеров
/// отвергают как «invalid characters in content»; нормализует переводы строк,
/// схлопывает пустые строки и обрезает пробелы. Один и тот же вход даёт один
/// и тот же выход, поэтому `content_hash` карточек не меняется.
library;

/// Управляющие символы, которые удаляются (кроме `\t` и `\n`).
final RegExp _controlCharacters = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
);

/// Хвостовые пробелы и табы в строке.
final RegExp _trailingWhitespace = RegExp(r'[ \t]+$');

/// Три и более перевода строки подряд (две и более пустых строки).
final RegExp _excessBlankLines = RegExp(r'\n{3,}');

/// Санитайзер извлечённого текста.
class TextSanitizer {
  /// Создаёт санитайзер.
  const TextSanitizer();

  /// Приводит текст к канонической форме.
  ///
  /// `\r\n`/`\r` → `\n`; управляющие символы (кроме `\t`, `\n`) удаляются;
  /// неразрывный пробел → обычный; хвостовые пробелы строк убираются; три и
  /// более перевода строки подряд сжимаются до двух; края обрезаются.
  String sanitize(String input) {
    var text = input.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    text = text.replaceAll(_controlCharacters, '');
    text = text.replaceAll('\u00A0', ' ');
    text = text
        .split('\n')
        .map((String line) => line.replaceAll(_trailingWhitespace, ''))
        .join('\n');
    text = text.replaceAll(_excessBlankLines, '\n\n');
    return text.trim();
  }

  /// true, если после санитизации текста не остаётся.
  bool isEmpty(String input) => sanitize(input).isEmpty;
}
