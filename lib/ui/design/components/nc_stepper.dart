import 'package:material_ui/material_ui.dart';

/// `−  N  +` для лимитов (REDESIGN-SPEC §8): круглые `tonal`-кнопки, значение
/// `monoL`, долгое нажатие — автоповтор. Ключи `settings-$id-minus/plus/value`
/// сохраняются ([minusKey], [valueKey], [plusKey]).
class NcStepper extends StatelessWidget {
  /// Создаёт степпер.
  const NcStepper({
    super.key,
    required this.value,
    this.onDecrement,
    this.onIncrement,
    this.minusKey,
    this.valueKey,
    this.plusKey,
    this.semanticLabel,
    this.minValue,
    this.maxValue,
  });

  /// Текущее значение.
  final int value;

  /// Уменьшить; `null` — кнопка «−» неактивна.
  final VoidCallback? onDecrement;

  /// Увеличить; `null` — кнопка «+» неактивна.
  final VoidCallback? onIncrement;

  /// Ключ кнопки «−».
  final Key? minusKey;

  /// Ключ значения.
  final Key? valueKey;

  /// Ключ кнопки «+».
  final Key? plusKey;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Нижняя граница (для автоповтора).
  final int? minValue;

  /// Верхняя граница (для автоповтора).
  final int? maxValue;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
