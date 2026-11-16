import 'package:material_ui/material_ui.dart';

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
class NcIconButton extends StatelessWidget {
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

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
