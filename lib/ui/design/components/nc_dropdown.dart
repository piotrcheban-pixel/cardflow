import 'package:material_ui/material_ui.dart';

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
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
