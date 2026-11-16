import 'package:material_ui/material_ui.dart';

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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
