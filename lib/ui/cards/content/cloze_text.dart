import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/cloze_markup.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Интерактивное раскрытие cloze-групп по одному номеру.
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
    final markup = ClozeMarkup.parse(widget.source);
    if (!markup.hasGaps) return Text(widget.source);
    final l10n = AppLocalizations.of(context);
    final spans = <InlineSpan>[];
    for (final segment in markup.segments) {
      if (!segment.isGap) {
        spans.add(TextSpan(text: segment.text));
        continue;
      }
      final number = segment.number!;
      final show = widget.revealed || _revealedGroups.contains(number);
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
            child: Text(
              show ? segment.answer! : l10n.clozeHiddenAnswer,
              style: TextStyle(
                color: show
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.onSurfaceVariant,
                decoration: show ? null : TextDecoration.underline,
              ),
            ),
          ),
        ),
      );
    }
    return Text.rich(TextSpan(children: spans), textAlign: TextAlign.center);
  }
}
