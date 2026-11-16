import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_spacing.dart';

/// Строка 56–72 px внутри секции (REDESIGN-SPEC §8): `leading` 28 px,
/// заголовок/подзаголовок, `trailing` (шеврон/значение/переключатель).
/// Разделитель — `hairline` с отступом от leading.
class NcListRow extends StatelessWidget {
  /// Создаёт строку.
  const NcListRow({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.showDivider = true,
    this.semanticLabel,
    this.minHeight = 56,
    this.titleMaxLines = 1,
    this.subtitleMaxLines = 1,
  });

  /// Заголовок (ARB или `CardText`).
  final Widget title;

  /// Подзаголовок.
  final Widget? subtitle;

  /// Ведущий элемент (глиф 28, аватар).
  final Widget? leading;

  /// Хвостовой элемент (шеврон, значение, переключатель).
  final Widget? trailing;

  /// Тап по строке.
  final VoidCallback? onTap;

  /// Долгое нажатие.
  final VoidCallback? onLongPress;

  /// Правый клик (контекстное меню на ПК).
  final VoidCallback? onSecondaryTap;

  /// Рисовать разделитель снизу.
  final bool showDivider;

  /// Текст семантики.
  final String? semanticLabel;

  /// Минимальная высота.
  final double minHeight;

  /// Максимум строк заголовка.
  final int titleMaxLines;

  /// Максимум строк подзаголовка.
  final int subtitleMaxLines;

  /// Отступ разделителя при наличии leading.
  static const double _leadingWidth = 28;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Widget content = Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: NcSpace.s16,
        vertical: NcSpace.s8,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: minHeight - NcSpace.s16),
        child: Row(
          children: <Widget>[
            if (leading != null) ...<Widget>[
              SizedBox(
                width: _leadingWidth,
                child: Center(child: leading),
              ),
              const SizedBox(width: NcSpace.s12),
            ],
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  DefaultTextStyle.merge(
                    maxLines: titleMaxLines,
                    overflow: TextOverflow.ellipsis,
                    style: theme.typography.titleS.copyWith(
                      color: theme.colors.textPrimary,
                    ),
                    child: title,
                  ),
                  if (subtitle != null)
                    DefaultTextStyle.merge(
                      maxLines: subtitleMaxLines,
                      overflow: TextOverflow.ellipsis,
                      style: theme.typography.bodyS.copyWith(
                        color: theme.colors.textSecondary,
                      ),
                      child: subtitle!,
                    ),
                ],
              ),
            ),
            if (trailing != null) ...<Widget>[
              const SizedBox(width: NcSpace.s12),
              trailing!,
            ],
          ],
        ),
      ),
    );

    final bool interactive =
        onTap != null || onLongPress != null || onSecondaryTap != null;
    final Widget row = interactive
        ? NcTappable(
            onTap: onTap,
            onLongPress: onLongPress,
            onSecondaryTap: onSecondaryTap,
            semanticLabel: semanticLabel,
            focusRadius: 0,
            child: content,
          )
        : content;
    if (!showDivider) return row;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        row,
        Divider(
          height: 1,
          thickness: 1,
          color: theme.colors.hairline,
          indent: leading == null
              ? NcSpace.s16
              : NcSpace.s16 + _leadingWidth + NcSpace.s12,
        ),
      ],
    );
  }
}
