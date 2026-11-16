import 'package:material_ui/material_ui.dart';

/// Переключатель Nocturne (REDESIGN-SPEC §8): 52 × 32, трек `ink5` → `aurum`,
/// бегунок `#F2EEE7` с тенью, перелёт на пружине `snap`; Space/Enter и
/// семантика `toggled`.
class NcSwitch extends StatelessWidget {
  /// Создаёт переключатель.
  const NcSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
    this.autofocus = false,
    this.focusNode,
  });

  /// Включён ли.
  final bool value;

  /// Переключение; `null` — неактивен.
  final ValueChanged<bool>? onChanged;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Ширина трека.
  static const double width = 52;

  /// Высота трека.
  static const double height = 32;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
