/// Вид фрагмента текста с LaTeX.
enum LatexSegmentKind { text, inlineFormula, displayFormula }

/// Один фрагмент стороны карточки.
class LatexSegment {
  const LatexSegment(this.kind, this.value);

  final LatexSegmentKind kind;
  final String value;

  bool get isFormula => kind != LatexSegmentKind.text;
}

/// Разбор `$…$` и `$$…$$` без зависимости от Flutter.
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
    var cursor = 0;
    var index = 0;
    while (index < source.length) {
      final display = source.startsWith(r'$$', index);
      if (!display && source[index] != r'$') {
        index++;
        continue;
      }
      final delimiter = display ? r'$$' : r'$';
      final start = index + delimiter.length;
      final end = source.indexOf(delimiter, start);
      if (end < 0) {
        return LatexMarkup(
          segments: <LatexSegment>[LatexSegment(LatexSegmentKind.text, source)],
          hasUnclosedDelimiter: true,
        );
      }
      final expression = source.substring(start, end).trim();
      if (expression.isEmpty) {
        index = end + delimiter.length;
        continue;
      }
      if (index > cursor) {
        _addText(segments, source.substring(cursor, index));
      }
      segments.add(
        LatexSegment(
          display
              ? LatexSegmentKind.displayFormula
              : LatexSegmentKind.inlineFormula,
          expression,
        ),
      );
      index = end + delimiter.length;
      cursor = index;
    }
    if (cursor < source.length) _addText(segments, source.substring(cursor));
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
