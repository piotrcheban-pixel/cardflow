import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/cloze_markup.dart';
import 'package:cardflow/ui/cards/content/inline_latex_text.dart';

/// Интерактивное раскрытие cloze-групп по одному номеру.
///
/// Формулы внутри и вокруг пропусков рендерятся LaTeX-ом (fix-gen, Д4):
/// `{{c1::$2n - 3$}}` показывает формулу, а не сырой `$…$`.
class ClozeText extends StatefulWidget {
  const ClozeText({
    required this.source,
    required this.revealed,
    this.maxLines,
    this.overflow,
    this.textAlign,
    super.key,
  });

  final String source;
  final bool revealed;

  /// Ограничение строк (список карточек колоды не должен расти в высоту).
  final int? maxLines;

  /// Как обрезать длинный cloze-текст в списке.
  final TextOverflow? overflow;

  /// Выравнивание текста; `null` — центр (карточка сессии).
  final TextAlign? textAlign;

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
    final ThemeData theme = Theme.of(context);
    // Сегменты копируются в изменяемый список: у пропуска «забирается»
    // ведущая пунктуация следующего текста, поэтому «____,» рисуется одним
    // неразрывным фрагментом.
    final List<ClozeSegment> segments = markup.segments.toList();
    final spans = <InlineSpan>[];
    for (int index = 0; index < segments.length; index++) {
      final ClozeSegment segment = segments[index];
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
      String trailing = '';
      if (index + 1 < segments.length && !segments[index + 1].isGap) {
        final String nextText = segments[index + 1].text ?? '';
        final RegExpMatch? match = _leadingPunctuation.firstMatch(nextText);
        if (match != null) {
          trailing = match.group(1)!;
          segments[index + 1] = ClozeSegment.text(
            nextText.substring(trailing.length),
          );
        }
      }
      final Widget child = show
          ? InlineLatexText(
              source: '${segment.answer ?? ''}$trailing',
              style: TextStyle(color: theme.colorScheme.primary),
            )
          : Text(
              // Фиксированная ширина пропуска (7 неразрывных пробелов с
              // подчёркиванием) — «—…» заменено на понятную линию.
              '${'\u00A0' * 7}$trailing',
              style: TextStyle(
                color: theme.colorScheme.onSurfaceVariant,
                decoration: TextDecoration.underline,
                decorationColor: theme.colorScheme.onSurfaceVariant,
                decorationThickness: 1.5,
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
    return Text.rich(
      TextSpan(children: spans),
      textAlign: widget.textAlign ?? TextAlign.center,
      maxLines: widget.maxLines,
      overflow: widget.overflow ?? TextOverflow.clip,
    );
  }

  /// Ведущая пунктуация фрагмента после пропуска (вместе с пробелом перед ней).
  static final RegExp _leadingPunctuation = RegExp(r'^(\s*[,.;:!?…)»]+)');
}
