import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import 'nc_glass.dart';

/// Вариант иконочной кнопки (REDESIGN-SPEC §8).
enum NcIconButtonVariant {
  /// Прозрачная, иконка `textPrimary`.
  ghost,

  /// Заливка `ink4`.
  tonal,

  /// Стекло `glass.thin` (поверх контента, «назад» в шапке).
  glass,
}

/// Круглая иконочная кнопка 44 × 44 (§8). Обязательный [tooltip] из ARB —
/// он же текст семантики и подпись для скринридера.
class NcIconButton extends StatefulWidget {
  /// Создаёт иконочную кнопку.
  const NcIconButton({
    super.key,
    required this.icon,
    required this.tooltip,
    this.onPressed,
    this.variant = NcIconButtonVariant.ghost,
    this.size = 44,
    this.selected = false,
    this.autofocus = false,
    this.focusNode,
    this.iconColor,
  });

  /// Иконка.
  final IconData icon;

  /// Подпись (ARB): семантика и tooltip.
  final String tooltip;

  /// Действие; `null` — неактивная.
  final VoidCallback? onPressed;

  /// Вариант оформления.
  final NcIconButtonVariant variant;

  /// Диаметр кнопки (по умолчанию 44, §8).
  final double size;

  /// Выбрано ли (например, открытый поиск).
  final bool selected;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Цвет иконки (например, `ember` у удаления).
  final Color? iconColor;

  @override
  State<NcIconButton> createState() => _NcIconButtonState();
}

class _NcIconButtonState extends State<NcIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool enabled = widget.onPressed != null;
    final Color background = !enabled
        ? NcColors.transparent
        : widget.selected
        ? theme.colors.aurumSoft
        : switch (widget.variant) {
            NcIconButtonVariant.ghost =>
              _hovered ? theme.colors.ink4 : NcColors.transparent,
            NcIconButtonVariant.tonal =>
              _hovered ? theme.colors.ink5 : theme.colors.ink4,
            NcIconButtonVariant.glass => NcColors.transparent,
          };
    final Color foreground = !enabled
        ? theme.colors.textDisabled
        : widget.selected
        ? theme.colors.aurum
        : widget.iconColor ?? theme.colors.textPrimary;
    final BorderRadius radius = BorderRadius.circular(widget.size / 2);

    Widget button = DecoratedBox(
      decoration: ShapeDecoration(
        color: background,
        shape: RoundedSuperellipseBorder(borderRadius: radius),
      ),
      child: SizedBox.square(
        dimension: widget.size,
        child: Center(
          child: Icon(widget.icon, size: widget.size * 0.45, color: foreground),
        ),
      ),
    );
    if (widget.variant == NcIconButtonVariant.glass) {
      button = NcGlass(
        tier: NcGlassTier.thin,
        radius: widget.size / 2,
        width: widget.size,
        height: widget.size,
        child: button,
      );
    }
    button = MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: NcTappable(
        onTap: enabled ? widget.onPressed : null,
        enabled: enabled,
        semanticLabel: widget.tooltip,
        focusRadius: widget.size / 2,
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        child: button,
      ),
    );
    return Tooltip(message: widget.tooltip, child: button);
  }
}
