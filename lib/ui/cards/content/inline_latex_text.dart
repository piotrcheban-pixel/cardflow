import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/latex_markup.dart';
import 'package:cardflow/ui/cards/content/latex_spans.dart';

/// Однострочный LaTeX-рендер без пошагового раскрытия (для cloze и подсказок).
///
/// Отличие от [LatexText]: все формулы показываются сразу, блочные формулы
/// рендерятся как inline — текст остаётся в одну строку (fix-gen, Д4).
///
/// Текст без формул остаётся обычным `Text` (с `data`), чтобы `find.text` и
/// чтение `Text.data` в тестах продолжали работать: меняется только рендер
/// формул.
class InlineLatexText extends StatelessWidget {
  const InlineLatexText({
    required this.source,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String source;
  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  Widget build(BuildContext context) {
    if (!LatexMarkup.parse(source).hasFormulas) {
      return Text(
        source,
        style: style,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }
    return Text.rich(
      TextSpan(
        children: latexTextSpans(context, source, style: style),
        style: style,
      ),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
