import 'dart:ui' as ui;

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/latex_markup.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';

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
    final NcTheme theme = NcTheme.of(context);
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
            child: ClipRSuperellipse(
              key: ValueKey<String>('latex-hidden-$formulaIndex'),
              borderRadius: BorderRadius.circular(NcRadii.s),
              child: ColoredBox(
                color: theme.colors.ink4,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 2,
                  ),
                  child: ImageFiltered(
                    imageFilter: ui.ImageFilter.blur(sigmaX: 2, sigmaY: 2),
                    child: Text(AppLocalizations.of(context).clozeHiddenAnswer),
                  ),
                ),
              ),
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
        textStyle: theme.typography.bodyL.copyWith(
          color: theme.colors.textPrimary,
        ),
        onErrorFallback: (error) => Text(
          widget.source,
          style: theme.typography.bodyL.copyWith(
            color: theme.colors.textPrimary,
          ),
        ),
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
          NcButton(
            key: const ValueKey<String>('latex-next-step'),
            label: AppLocalizations.of(context).latexNextStep,
            variant: NcButtonVariant.ghost,
            size: NcButtonSize.s,
            onPressed: () => setState(() => _visibleFormulas++),
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

  Widget _fallback(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        NcBadge(
          label: AppLocalizations.of(context).generationIssueLatexBroken,
          tone: NcBadgeTone.amber,
        ),
        const SizedBox(height: 8),
        Text(
          widget.source,
          textAlign: TextAlign.center,
          style: theme.typography.bodyL.copyWith(
            color: theme.colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
