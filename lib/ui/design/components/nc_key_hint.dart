import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';
import '../tokens/nc_radii.dart';

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
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6, vertical: 1),
      decoration: ShapeDecoration(
        shape: RoundedSuperellipseBorder(
          borderRadius: BorderRadius.circular(NcRadii.xs),
          side: BorderSide(color: theme.colors.hairlineStrong),
        ),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.visible,
        style: theme.typography.monoM.copyWith(
          color: theme.colors.textTertiary,
          fontSize: compact ? 10 : null,
          height: 1.2,
        ),
      ),
    );
  }
}
