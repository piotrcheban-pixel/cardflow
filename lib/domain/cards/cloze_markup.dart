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

  bool get hasGaps => false;

  static ClozeMarkup parse(String source) =>
      ClozeMarkup(segments: <ClozeSegment>[ClozeSegment.text(source)]);
}
