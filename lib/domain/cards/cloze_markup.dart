/// Текстовый фрагмент или пропуск cloze.
class ClozeSegment {
  const ClozeSegment.text(this.text) : number = null, answer = null;

  const ClozeSegment.gap({required this.number, required this.answer})
    : text = null;

  final String? text;
  final int? number;
  final String? answer;

  bool get isGap => number != null;
}

/// Разобранная разметка `{{cN::ответ}}`.
class ClozeMarkup {
  const ClozeMarkup({required this.segments});

  final List<ClozeSegment> segments;

  bool get hasGaps => segments.any((segment) => segment.isGap);

  static final RegExp _pattern = RegExp(r'\{\{c([1-9]\d*)::([\s\S]+?)\}\}');

  static ClozeMarkup parse(String source) {
    final matches = _pattern.allMatches(source).toList(growable: false);
    if (matches.isEmpty) return _plain(source);
    final segments = <ClozeSegment>[];
    var cursor = 0;
    for (final match in matches) {
      final answer = match.group(2);
      if (answer == null || answer.trim().isEmpty) return _plain(source);
      final before = source.substring(cursor, match.start);
      if (_containsMarkup(before)) return _plain(source);
      if (before.isNotEmpty) segments.add(ClozeSegment.text(before));
      segments.add(
        ClozeSegment.gap(number: int.parse(match.group(1)!), answer: answer),
      );
      cursor = match.end;
    }
    final after = source.substring(cursor);
    if (_containsMarkup(after)) return _plain(source);
    if (after.isNotEmpty) segments.add(ClozeSegment.text(after));
    return ClozeMarkup(segments: List<ClozeSegment>.unmodifiable(segments));
  }

  static bool _containsMarkup(String value) =>
      value.contains('{{') || value.contains('}}');

  static ClozeMarkup _plain(String source) =>
      ClozeMarkup(segments: <ClozeSegment>[ClozeSegment.text(source)]);
}
