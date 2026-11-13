/// Единая нормализация извлечённого из документа текста (SPEC A8.3).
///
/// Один нормализатор на все парсеры: одинаковый вход даёт одинаковый выход,
/// поэтому повторный парсинг файла не меняет `content_hash` карточек.
library;

/// Управляющие символы, которые удаляются (кроме `\t` и `\n`).
final RegExp _controlCharacters = RegExp(
  r'[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F]',
);

/// Хвостовые пробелы и табы в строке.
final RegExp _trailingWhitespace = RegExp(r'[ \t]+$');

/// Три и более перевода строки подряд (две и более пустых строки).
final RegExp _excessBlankLines = RegExp(r'\n{3,}');

/// Приводит текст документа к канонической форме.
///
/// Правила: `\r\n` и `\r` → `\n`; NUL и управляющие символы (кроме `\t`, `\n`)
/// удаляются; неразрывные пробелы → обычные; хвостовые пробелы строк убираются;
/// три и более пустых строк подряд сжимаются до двух; общие пробелы по краям
/// текста обрезаются.
String normalizeDocumentText(String input) {
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
