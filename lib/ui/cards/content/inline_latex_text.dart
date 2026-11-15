import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/latex_markup.dart';

/// Однострочный LaTeX-рендер без пошагового раскрытия (для cloze и подсказок).
///
/// Отличие от [LatexText]: все формулы показываются сразу, блочные формулы
/// рендерятся как inline — текст остаётся в одну строку (fix-gen, Д4).
class InlineLatexText extends StatelessWidget {
  const InlineLatexText({required this.source, this.style, super.key});

  final String source;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final LatexMarkup markup = LatexMarkup.parse(source);
    if (!markup.hasFormulas) return Text(source, style: style);
    final List<InlineSpan> spans = <InlineSpan>[];
    for (final LatexSegment segment in markup.segments) {
      if (!segment.isFormula) {
        spans.add(TextSpan(text: segment.value, style: style));
        continue;
      }
      final Widget math = Math.tex(
        segment.value,
        mathStyle: MathStyle.text,
        textStyle: style ?? Theme.of(context).textTheme.bodyMedium,
        onErrorFallback: (Object error) => Text(segment.value, style: style),
      );
      spans.add(
        WidgetSpan(alignment: PlaceholderAlignment.middle, child: math),
      );
    }
    return Text.rich(TextSpan(children: spans, style: style));
  }
}
