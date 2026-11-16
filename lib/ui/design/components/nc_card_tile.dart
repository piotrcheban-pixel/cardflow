import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import '../tokens/nc_spacing.dart';
import 'nc_surface.dart';

/// Плитка с ведущим элементом, заголовком, подзаголовком, хвостом и бейджем
/// (REDESIGN-SPEC §8). Заменяет `M3ECard` в списках; основа — `NcSurface`
/// `ink2` `r.l` `depth1`, hover-подъём на ПК.
class NcCardTile extends StatelessWidget {
  /// Создаёт плитку.
  const NcCardTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.badge,
    this.onTap,
    this.onLongPress,
    this.onSecondaryTap,
    this.semanticLabel,
    this.height,
    this.border = true,
  });

  /// Заголовок.
  final Widget title;

  /// Подзаголовок.
  final Widget? subtitle;

  /// Ведущий элемент (3D-аватар, глиф).
  final Widget? leading;

  /// Хвостовой элемент.
  final Widget? trailing;

  /// Бейдж (например, `NcBadge.count`).
  final Widget? badge;

  /// Тап.
  final VoidCallback? onTap;

  /// Долгое нажатие (контекстное меню).
  final VoidCallback? onLongPress;

  /// Правый клик (ПК).
  final VoidCallback? onSecondaryTap;

  /// Текст семантики.
  final String? semanticLabel;

  /// Высота (по умолчанию по содержимому).
  final double? height;

  /// Рисовать рамку.
  final bool border;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Widget content = Row(
      children: <Widget>[
        if (leading != null) ...<Widget>[
          leading!,
          const SizedBox(width: NcSpace.s12),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              DefaultTextStyle.merge(
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.typography.titleM.copyWith(
                  color: theme.colors.textPrimary,
                ),
                child: title,
              ),
              if (subtitle != null) ...<Widget>[
                const SizedBox(height: NcSpace.s2),
                DefaultTextStyle.merge(
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.typography.bodyS.copyWith(
                    color: theme.colors.textSecondary,
                  ),
                  child: subtitle!,
                ),
              ],
            ],
          ),
        ),
        if (badge != null) ...<Widget>[
          const SizedBox(width: NcSpace.s8),
          badge!,
        ],
        if (trailing != null) ...<Widget>[
          const SizedBox(width: NcSpace.s8),
          trailing!,
        ],
      ],
    );

    final Widget surface = NcSurface(
      radius: NcRadii.l,
      level: 1,
      border: border,
      padding: const EdgeInsets.symmetric(
        horizontal: NcSpace.tilePaddingH,
        vertical: NcSpace.tilePaddingV,
      ),
      height: height,
      child: content,
    );
    final bool interactive =
        onTap != null || onLongPress != null || onSecondaryTap != null;
    if (!interactive) {
      return semanticLabel == null
          ? surface
          : Semantics(label: semanticLabel, child: surface);
    }
    return NcTappable(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      semanticLabel: semanticLabel,
      focusRadius: NcRadii.l,
      child: surface,
    );
  }
}
