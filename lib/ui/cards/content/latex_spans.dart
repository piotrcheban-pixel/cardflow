import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/latex_markup.dart';

/// Строит inline-спаны для текста с `$…$`, `$$…$$`, `\(…\)`, `\[…\]`.
///
/// Отличие от [LatexText] (пошаговое раскрытие) и от `CardContentView`: все
/// формулы показываются сразу и остаются внутри одного `Text.rich`. Это нужно
/// кнопкам вариантов, плиткам пар, строке правильного ответа и diff-у (7.17) —
/// там макет задаёт родитель, а не блочная вёрстка карточки.
///
/// Формула, которую `flutter_math_fork` не разбирает, остаётся текстом этого
/// фрагмента (без падения и без сырых `$…$` — разделители уже разобраны).
List<InlineSpan> latexTextSpans(
  BuildContext context,
  String source, {
  TextStyle? style,
  TextStyle? formulaStyle,
}) {
  final LatexMarkup markup = LatexMarkup.parse(source);
  if (!markup.hasFormulas) {
    return <InlineSpan>[TextSpan(text: source, style: style)];
  }
  // Цвет/кегль формулы наследуются от кнопки/плашки, а не от bodyMedium:
  // варианты Теста бывают зелёными и красными. `Math` требует непустые
  // `fontSize` и `color`, поэтому подставляем значения темы явно.
  final ThemeData theme = Theme.of(context);
  final TextStyle effective = DefaultTextStyle.of(context).style
      .merge(theme.textTheme.bodyMedium)
      .merge(formulaStyle ?? style);
  final TextStyle mathStyle = effective.copyWith(
    color: effective.color ?? theme.colorScheme.onSurface,
    fontSize: effective.fontSize ?? 16,
  );
  final List<InlineSpan> spans = <InlineSpan>[];
  for (final LatexSegment segment in markup.segments) {
    if (!segment.isFormula) {
      spans.add(TextSpan(text: segment.value, style: style));
      continue;
    }
    spans.add(
      WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: Math.tex(
          segment.value,
          mathStyle: MathStyle.text,
          textStyle: mathStyle,
          onErrorFallback: (Object error) =>
              Text(segment.value, style: style ?? mathStyle),
        ),
      ),
    );
  }
  return spans;
}
