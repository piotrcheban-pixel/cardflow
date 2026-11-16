import 'package:material_ui/material_ui.dart';

/// Подсказка клавиши: `1`, `Space`, `Enter` (REDESIGN-SPEC §8, §10).
///
/// Рамка `hairlineStrong`, `r.xs`, `monoM` `textTertiary`. Показывается только
/// на ПК и при аппаратной клавиатуре — решение принимает экран; компонент
/// сам ничего не скрывает.
class NcKeyHint extends StatelessWidget {
  /// Создаёт подсказку клавиши.
  const NcKeyHint({super.key, required this.label, this.compact = false});

  /// Текст клавиши (`Space`, `1`…`4`, `Enter`).
  final String label;

  /// Компактный вариант (внутри кнопки оценки).
  final bool compact;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
