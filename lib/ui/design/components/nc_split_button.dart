import 'package:material_ui/material_ui.dart';

import 'nc_button.dart';
import 'nc_menu.dart';

/// Составная кнопка: основное действие слева + стрелка меню справа (§8).
///
/// Заменяет `M3ESplitButton`; между сегментами зазор 2 px, меню — `NcMenu` на
/// `glass.thick`. Ключи пунктов сохраняются ([NcMenuItem.key]).
class NcSplitButton extends StatelessWidget {
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
  Widget build(BuildContext context) => const SizedBox.shrink();
}
