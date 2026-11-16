import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';
import 'nc_menu.dart';

/// Элемент выпадающего списка (REDESIGN-SPEC §8).
@immutable
class NcDropdownItem<T> {
  /// Создаёт элемент.
  const NcDropdownItem({
    required this.value,
    required this.label,
    this.icon,
    this.enabled = true,
    this.key,
  });

  /// Значение.
  final T value;

  /// Текст пункта (ARB).
  final String label;

  /// Иконка.
  final IconData? icon;

  /// Доступен ли пункт.
  final bool enabled;

  /// Ключ пункта (контракт §9, например `provider-model-<preset>`).
  final Key? key;
}

/// Поле-кнопка + меню `NcMenu` (REDESIGN-SPEC §8). Открывается тапом,
/// Enter/Space на клавиатуре; выбранное значение возвращается через
/// [onChanged].
class NcDropdown<T> extends StatefulWidget {
  /// Создаёт выпадающий список.
  const NcDropdown({
    super.key,
    required this.value,
    required this.items,
    this.onChanged,
    this.label,
    this.hint,
    this.enabled = true,
    this.semanticLabel,
    this.fieldKey,
    this.focusNode,
    this.menuLabel,
  });

  /// Текущее значение (`null` — показать [hint]).
  final T? value;

  /// Элементы списка.
  final List<NcDropdownItem<T>> items;

  /// Выбор значения.
  final ValueChanged<T>? onChanged;

  /// Метка над полем.
  final String? label;

  /// Плейсхолдер пустого значения.
  final String? hint;

  /// Включён ли.
  final bool enabled;

  /// Текст семантики (по умолчанию — выбранная подпись).
  final String? semanticLabel;

  /// Ключ поля-кнопки (контракт §9).
  final Key? fieldKey;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Подпись меню для семантики.
  final String? menuLabel;

  @override
  State<NcDropdown<T>> createState() => _NcDropdownState<T>();
}

class _NcDropdownState<T> extends State<NcDropdown<T>> {
  final GlobalKey _fieldAnchorKey = GlobalKey();

  Future<void> _open() async {
    if (!widget.enabled || widget.onChanged == null) return;
    final T? selected = await showNcMenu<T>(
      context: context,
      anchorKey: _fieldAnchorKey,
      minWidth: 220,
      items: <NcMenuItem<T>>[
        for (final NcDropdownItem<T> item in widget.items)
          NcMenuItem<T>(
            key: item.key,
            label: item.label,
            icon: item.icon,
            value: item.value,
            enabled: item.enabled,
          ),
      ],
    );
    if (selected != null) widget.onChanged!(selected);
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    NcDropdownItem<T>? selected;
    for (final NcDropdownItem<T> item in widget.items) {
      if (item.value == widget.value) {
        selected = item;
        break;
      }
    }
    final bool active = widget.enabled && widget.onChanged != null;
    final BorderRadius radius = BorderRadius.circular(NcRadii.s);
    final Widget field = Container(
      key: _fieldAnchorKey,
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: ShapeDecoration(
        color: theme.colors.ink2,
        shape: RoundedSuperellipseBorder(
          borderRadius: radius,
          side: BorderSide(color: theme.colors.hairline),
        ),
      ),
      child: Row(
        children: <Widget>[
          if (selected?.icon != null) ...<Widget>[
            Icon(
              selected!.icon,
              size: 18,
              color: active
                  ? theme.colors.textPrimary
                  : theme.colors.textDisabled,
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              selected?.label ?? widget.hint ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.typography.bodyL.copyWith(
                color: !active
                    ? theme.colors.textDisabled
                    : selected == null
                    ? theme.colors.textTertiary
                    : theme.colors.textPrimary,
              ),
            ),
          ),
          Icon(
            Icons.expand_more_rounded,
            size: 20,
            color: active
                ? theme.colors.textSecondary
                : theme.colors.textDisabled,
          ),
        ],
      ),
    );

    Widget content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        if (widget.label != null) ...<Widget>[
          Text(
            widget.label!,
            style: theme.typography.labelM.copyWith(
              color: theme.colors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
        ],
        NcTappable(
          key: widget.fieldKey,
          onTap: active ? _open : null,
          enabled: active,
          focusNode: widget.focusNode,
          semanticLabel: widget.semanticLabel ?? selected?.label ?? widget.hint,
          semanticValue: selected?.label,
          focusRadius: NcRadii.s,
          scaleOnPress: false,
          child: field,
        ),
      ],
    );
    return content;
  }
}
