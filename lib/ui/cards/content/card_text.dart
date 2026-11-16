import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/cards/cloze_markup.dart';
import 'package:cardflow/ui/cards/content/cloze_text.dart';
import 'package:cardflow/ui/cards/content/inline_latex_text.dart';

/// Единый рендер текста карточки вне блочной вёрстки карточки (7.17).
///
/// Используется там, где раньше стоял обычный `Text`: варианты ответа в
/// «Тесте», плитки «Подбора пар», утверждение и пояснение «Верно/Неверно»,
/// строка правильного ответа и diff во «Вводе ответа», список ошибок на
/// итогах. Формулы `$…$`/`\(…\)` рендерятся [Math] из `flutter_math_fork`,
/// cloze-разметка `{{cN::…}}` — через [ClozeText], а не сырой строкой.
///
/// В отличие от `CardContentView` здесь нет картинки и блочной вёрстки: это
/// одна строка (иногда с ограничением строк), которую размещает родитель.
class CardText extends StatelessWidget {
  const CardText({
    required this.source,
    this.style,
    this.textAlign,
    this.maxLines,
    this.overflow,
    this.revealed = true,
    super.key,
  });

  /// Текст карточки (вопрос, ответ или вариант).
  final String source;

  final TextStyle? style;
  final TextAlign? textAlign;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Раскрывать ли cloze-пропуски (по умолчанию — да: это ответ/вариант).
  final bool revealed;

  @override
  Widget build(BuildContext context) {
    if (source.isEmpty) return const SizedBox.shrink();
    if (ClozeMarkup.parse(source).hasGaps) {
      return DefaultTextStyle.merge(
        style: style,
        textAlign: textAlign ?? TextAlign.start,
        child: ClozeText(source: source, revealed: revealed),
      );
    }
    return InlineLatexText(
      source: source,
      style: style,
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}
