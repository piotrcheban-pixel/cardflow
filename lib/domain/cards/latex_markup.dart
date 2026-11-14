/// Вид фрагмента текста с LaTeX.
enum LatexSegmentKind { text, inlineFormula, displayFormula }

/// Один фрагмент стороны карточки.
class LatexSegment {
  const LatexSegment(this.kind, this.value);

  final LatexSegmentKind kind;
  final String value;
}

/// Разбор `$…$` и `$$…$$` без зависимости от Flutter.
class LatexMarkup {
  const LatexMarkup({required this.segments, this.hasUnclosedDelimiter = false});

  final List<LatexSegment> segments;
  final bool hasUnclosedDelimiter;

  static LatexMarkup parse(String source) => LatexMarkup(
    segments: <LatexSegment>[LatexSegment(LatexSegmentKind.text, source)],
  );
}
