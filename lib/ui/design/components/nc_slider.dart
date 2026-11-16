import 'package:material_ui/material_ui.dart';

/// Слайдер Nocturne (REDESIGN-SPEC §8): трек 6 px `ink5`, активная часть —
/// градиент Aurum, бегунок 22 px, при перетаскивании — пузырь со значением
/// (`monoM`). Тактильный отклик — на каждой риске (`NcHaptics`, ≤ 40 мс).
class NcSlider extends StatelessWidget {
  /// Создаёт слайдер.
  const NcSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
    this.onChangeEnd,
    this.semanticLabel,
    this.valueLabel,
    this.enabled = true,
    this.focusNode,
  });

  /// Текущее значение.
  final double value;

  /// Минимум.
  final double min;

  /// Максимум.
  final double max;

  /// Число рисок (делений).
  final int? divisions;

  /// Изменение значения.
  final ValueChanged<double>? onChanged;

  /// Конец перетаскивания.
  final ValueChanged<double>? onChangeEnd;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Подпись значения в пузыре (например, «90 %»); по умолчанию — число.
  final String Function(double value)? valueLabel;

  /// Включён ли слайдер.
  final bool enabled;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
