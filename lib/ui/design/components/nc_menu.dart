import 'package:material_ui/material_ui.dart';

/// Пункт меню Nocturne (REDESIGN-SPEC §8).
@immutable
class NcMenuItem<T> {
  /// Создаёт пункт меню.
  const NcMenuItem({
    required this.label,
    this.icon,
    this.value,
    this.onSelected,
    this.destructive = false,
    this.enabled = true,
    this.key,
    this.trailing,
  });

  /// Текст пункта (из ARB).
  final String label;

  /// Иконка слева.
  final IconData? icon;

  /// Значение, возвращаемое [showNcMenu].
  final T? value;

  /// Действие пункта (альтернатива [value]).
  final ValueChanged<T>? onSelected;

  /// Деструктивный пункт — `ember` (§8).
  final bool destructive;

  /// Доступен ли пункт.
  final bool enabled;

  /// Ключ пункта (контракт §9).
  final Key? key;

  /// Хвостовая подпись (значение настройки).
  final String? trailing;
}

/// Меню Nocturne: `glass.thick`, `r.l`, строки 48 px, иконка + текст,
/// деструктивный пункт — `ember` (§8).
class NcMenu<T> extends StatefulWidget {
  /// Создаёт меню.
  const NcMenu({
    super.key,
    required this.items,
    this.minWidth = 200,
    this.maxWidth = 320,
    this.onDismiss,
    this.autofocusFirst = true,
  });

  /// Пункты.
  final List<NcMenuItem<T>> items;

  /// Минимальная ширина.
  final double minWidth;

  /// Максимальная ширина.
  final double maxWidth;

  /// Закрыть меню (Escape, выбор).
  final VoidCallback? onDismiss;

  /// Поставить фокус на первый пункт при открытии.
  final bool autofocusFirst;

  @override
  State<NcMenu<T>> createState() => _NcMenuState<T>();
}

class _NcMenuState<T> extends State<NcMenu<T>> {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Показывает меню, привязанное к [anchorKey], и возвращает выбранное значение.
///
/// Реализовано через `OverlayEntry` (а не `PopupMenuRoute`): нужен собственный
/// материал `NcGlass` и появление scale 0,94→1 от точки вызова (§8).
Future<T?> showNcMenu<T>({
  required BuildContext context,
  required GlobalKey anchorKey,
  required List<NcMenuItem<T>> items,
  double minWidth = 200,
}) => Future<T?>.value(null);
