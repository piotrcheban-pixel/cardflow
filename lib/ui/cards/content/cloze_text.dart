import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/cloze_markup.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/content/inline_latex_text.dart';

/// Интерактивное раскрытие cloze-групп по одному номеру.
///
/// Формулы внутри и вокруг пропусков рендерятся LaTeX-ом (fix-gen, Д4):
/// `{{c1::$2n - 3$}}` показывает формулу, а не сырой `$…$`.
class ClozeText extends StatefulWidget {
  const ClozeText({required this.source, required this.revealed, super.key});

  final String source;
  final bool revealed;

  @override
  State<ClozeText> createState() => _ClozeTextState();
}

class _ClozeTextState extends State<ClozeText> {
  final Set<int> _revealedGroups = <int>{};

  @override
  void didUpdateWidget(ClozeText oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.source != widget.source ||
        (oldWidget.revealed && !widget.revealed)) {
      _revealedGroups.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ClozeMarkup markup = ClozeMarkup.parse(widget.source);
    if (!markup.hasGaps) return Text(widget.source);
    final AppLocalizations l10n = AppLocalizations.of(context);
    final spans = <InlineSpan>[];
    for (final ClozeSegment segment in markup.segments) {
      if (!segment.isGap) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: InlineLatexText(source: segment.text ?? ''),
          ),
        );
        continue;
      }
      final int number = segment.number!;
      final bool show = widget.revealed || _revealedGroups.contains(number);
      final Widget child = show
          ? InlineLatexText(
              source: segment.answer ?? '',
              style: TextStyle(color: Theme.of(context).colorScheme.primary),
            )
          : Text(
              l10n.clozeHiddenAnswer,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
              ),
            );
      spans.add(
        WidgetSpan(
          alignment: PlaceholderAlignment.baseline,
          baseline: TextBaseline.alphabetic,
          child: InkWell(
            key: ValueKey<String>(
              show ? 'cloze-answer-$number' : 'cloze-gap-$number',
            ),
            onTap: widget.revealed
                ? null
                : () => setState(() => _revealedGroups.add(number)),
            child: child,
          ),
        ),
      );
    }
    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.center);
  }
}
