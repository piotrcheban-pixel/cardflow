/// Вид фрагмента текста с LaTeX.
enum LatexSegmentKind { text, inlineFormula, displayFormula }

/// Один фрагмент стороны карточки.
class LatexSegment {
  const LatexSegment(this.kind, this.value);

  final LatexSegmentKind kind;
  final String value;

  bool get isFormula => kind != LatexSegmentKind.text;
}

/// Разбор `$…$`/`$$…$$` (и допустимых `\(…\)`/`\[…\]`) без зависимости от Flutter.
///
/// Правила (SPEC A7.10, fix-gen Д4):
/// - экранированный `\$` — не разделитель формулы, в тексте остаётся `$`;
/// - `\(…\)` и `\[…\]` нормализуются к `$…$` и `$$…$$`;
/// - незакрытый разделитель — [hasUnclosedDelimiter], текст показывается как есть.
class LatexMarkup {
  const LatexMarkup({
    required this.segments,
    this.hasUnclosedDelimiter = false,
  });

  final List<LatexSegment> segments;
  final bool hasUnclosedDelimiter;

  bool get hasFormulas => segments.any((segment) => segment.isFormula);

  static LatexMarkup parse(String source) {
    final segments = <LatexSegment>[];
    final text = StringBuffer();
    var index = 0;

    void flushText() {
      if (text.isEmpty) return;
      _addText(segments, text.toString());
      text.clear();
    }

    while (index < source.length) {
      if (source.startsWith(r'\$', index)) {
        text.write(r'$');
        index += 2;
        continue;
      }
      final bool displayDollar = source.startsWith(r'$$', index);
      final bool displayBracket = source.startsWith(r'\[', index);
      final bool inlineParen = source.startsWith(r'\(', index);
      final bool inlineDollar = !displayDollar && source[index] == r'$';
      if (!displayDollar && !displayBracket && !inlineParen && !inlineDollar) {
        text.write(source[index]);
        index++;
        continue;
      }
      final bool display = displayDollar || displayBracket;
      final String close = displayDollar
          ? r'$$'
          : displayBracket
          ? r'\]'
          : inlineParen
          ? r'\)'
          : r'$';
      final int delimiterLength = displayDollar || inlineParen || displayBracket
          ? 2
          : 1;
      final int start = index + delimiterLength;
      final int end = source.indexOf(close, start);
      if (end < 0) {
        return LatexMarkup(
          segments: <LatexSegment>[LatexSegment(LatexSegmentKind.text, source)],
          hasUnclosedDelimiter: true,
        );
      }
      final String expression = source.substring(start, end).trim();
      if (expression.isEmpty) {
        index = end + close.length;
        continue;
      }
      flushText();
      segments.add(
        LatexSegment(
          display
              ? LatexSegmentKind.displayFormula
              : LatexSegmentKind.inlineFormula,
          expression,
        ),
      );
      index = end + close.length;
    }
    flushText();
    if (segments.isEmpty) {
      _addText(segments, source);
    }
    return LatexMarkup(segments: List<LatexSegment>.unmodifiable(segments));
  }

  static void _addText(List<LatexSegment> segments, String value) {
    if (value.isEmpty) return;
    if (segments.isNotEmpty && segments.last.kind == LatexSegmentKind.text) {
      final previous = segments.removeLast();
      segments.add(LatexSegment(LatexSegmentKind.text, previous.value + value));
      return;
    }
    segments.add(LatexSegment(LatexSegmentKind.text, value));
  }
}

/// Текст без LaTeX-разметки: разделители убираются, выражения остаются.
///
/// Нужен для семантики (скринридер не должен читать `$…$`) и для поиска по
/// вариантам ответа. Незакрытый разделитель возвращает исходную строку.
String plainTextOfLatex(String source) =>
    LatexMarkup.parse(source).segments.map((LatexSegment s) => s.value).join();
