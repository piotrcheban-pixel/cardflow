import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/latex_markup.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Нативный LaTeX-рендер с последовательным раскрытием формул.
class LatexText extends StatefulWidget {
  const LatexText({required this.source, required this.revealed, super.key});

  final String source;
  final bool revealed;

  @override
  State<LatexText> createState() => _LatexTextState();
}

class _LatexTextState extends State<LatexText> {
  int _visibleFormulas = 1;

  @override
  void didUpdateWidget(LatexText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        (oldWidget.revealed && !widget.revealed)) {
      _visibleFormulas = 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    final markup = LatexMarkup.parse(widget.source);
    if (markup.hasUnclosedDelimiter) return _fallback(context);
    if (!markup.hasFormulas) {
      // Экранированный `\$` возвращается в текст без слэша (fix-gen, Д4).
      return Text(
        markup.segments.map((LatexSegment segment) => segment.value).join(),
      );
    }
    for (final segment in markup.segments.where((item) => item.isFormula)) {
      if (!_isParsable(segment.value)) return _fallback(context);
    }

    final formulaCount = markup.segments.where((item) => item.isFormula).length;
    final visibleCount = widget.revealed
        ? formulaCount
        : _visibleFormulas.clamp(1, formulaCount);
    final children = <Widget>[];
    var formulaIndex = 0;
    final inline = <InlineSpan>[];

    void flushInline() {
      if (inline.isEmpty) return;
      children.add(Text.rich(TextSpan(children: List<InlineSpan>.of(inline))));
      inline.clear();
    }

    for (final segment in markup.segments) {
      if (!segment.isFormula) {
        inline.add(TextSpan(text: segment.value));
        continue;
      }
      formulaIndex++;
      if (formulaIndex > visibleCount) {
        inline.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Text(
              AppLocalizations.of(context).clozeHiddenAnswer,
              key: ValueKey<String>('latex-hidden-$formulaIndex'),
            ),
          ),
        );
        continue;
      }
      final math = Math.tex(
        segment.value,
        mathStyle: segment.kind == LatexSegmentKind.displayFormula
            ? MathStyle.display
            : MathStyle.text,
        textStyle: Theme.of(context).textTheme.bodyLarge,
        onErrorFallback: (error) =>
            Text(widget.source, style: Theme.of(context).textTheme.bodyLarge),
      );
      if (segment.kind == LatexSegmentKind.displayFormula) {
        flushInline();
        children.add(
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: math,
          ),
        );
      } else {
        inline.add(
          WidgetSpan(alignment: PlaceholderAlignment.middle, child: math),
        );
      }
    }
    flushInline();

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        ...children,
        if (!widget.revealed && visibleCount < formulaCount)
          TextButton(
            key: const ValueKey<String>('latex-next-step'),
            onPressed: () => setState(() => _visibleFormulas++),
            child: Text(AppLocalizations.of(context).latexNextStep),
          ),
      ],
    );
  }

  bool _isParsable(String expression) {
    try {
      return Math.tex(expression).parseError == null;
    } on Object {
      return false;
    }
  }

  Widget _fallback(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      Text(widget.source, textAlign: TextAlign.center),
      const SizedBox(height: 8),
      Text(
        AppLocalizations.of(context).generationIssueLatexBroken,
        style: TextStyle(color: Theme.of(context).colorScheme.error),
        textAlign: TextAlign.center,
      ),
    ],
  );
}
