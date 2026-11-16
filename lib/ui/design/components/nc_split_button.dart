import 'package:material_ui/material_ui.dart';

import 'internal/nc_button_appearance.dart';
import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import 'nc_button.dart';
import 'nc_menu.dart';

/// Составная кнопка: основное действие слева + стрелка меню справа (§8).
///
/// Заменяет `M3ESplitButton`; между сегментами зазор 2 px, меню — `NcMenu` на
/// `glass.thick`. Ключи пунктов сохраняются ([NcMenuItem.key]).
class NcSplitButton extends StatefulWidget {
  /// Создаёт составную кнопку.
  const NcSplitButton({
    super.key,
    required this.label,
    this.onPressed,
    required this.items,
    this.menuSemanticLabel,
    this.icon,
    this.variant = NcButtonVariant.primary,
    this.size = NcButtonSize.m,
    this.expand = false,
  });

  /// Текст основного действия.
  final String label;

  /// Действие основного сегмента.
  final VoidCallback? onPressed;

  /// Пункты меню.
  final List<NcMenuItem<void>> items;

  /// Подпись меню для семантики (ARB).
  final String? menuSemanticLabel;

  /// Иконка основного действия.
  final IconData? icon;

  /// Вариант оформления.
  final NcButtonVariant variant;

  /// Размер.
  final NcButtonSize size;

  /// Растянуть на всю ширину.
  final bool expand;

  @override
  State<NcSplitButton> createState() => _NcSplitButtonState();
}

class _NcSplitButtonState extends State<NcSplitButton> {
  final GlobalKey _arrowKey = GlobalKey();
  bool _menuOpen = false;

  Future<void> _openMenu() async {
    if (_menuOpen || widget.items.isEmpty) return;
    _menuOpen = true;
    try {
      await showNcMenu<void>(
        context: context,
        anchorKey: _arrowKey,
        items: widget.items,
      );
    } finally {
      if (mounted) setState(() => _menuOpen = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool enabled = widget.onPressed != null;
    final NcButtonAppearance appearance = NcButtonAppearance.resolve(
      theme,
      widget.variant,
      enabled: enabled,
      prominent: false,
      hovered: false,
    );
    final double height = NcButtonAppearance.height(widget.size);
    final double iconSize = NcButtonAppearance.iconSize(widget.size);
    Widget main = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: NcButtonAppearance.horizontalPadding(widget.size),
      ),
      child: SizedBox(
        height: height,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (widget.icon != null) ...<Widget>[
              Icon(
                widget.icon,
                size: iconSize,
                color: appearance.iconColor ?? appearance.foreground,
              ),
              const SizedBox(width: 8),
            ],
            Text(
              widget.label,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style:
                  (widget.size == NcButtonSize.s
                          ? theme.typography.labelM
                          : theme.typography.labelL)
                      .copyWith(color: appearance.foreground),
            ),
          ],
        ),
      ),
    );
    main = appearance.decorate(main, radius: NcRadii.pill);
    main = NcTappable(
      enabled: enabled,
      onTap: widget.onPressed,
      semanticLabel: widget.label,
      focusRadius: NcRadii.pill,
      child: main,
    );

    Widget arrowContent = SizedBox(
      key: _arrowKey,
      width: height,
      height: height,
      child: Icon(
        Icons.expand_more_rounded,
        size: iconSize + 2,
        color: appearance.foreground,
      ),
    );
    arrowContent = appearance.decorate(arrowContent, radius: NcRadii.pill);
    Widget arrow = NcTappable(
      onTap: _openMenu,
      enabled: widget.items.isNotEmpty,
      semanticLabel: widget.menuSemanticLabel,
      focusRadius: NcRadii.pill,
      child: arrowContent,
    );
    if (widget.menuSemanticLabel != null) {
      arrow = Tooltip(message: widget.menuSemanticLabel!, child: arrow);
    }
    final Widget segments = Row(
      mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[main, const SizedBox(width: 2), arrow],
    );
    if (!widget.expand) return segments;
    return SizedBox(width: double.infinity, child: segments);
  }
}
