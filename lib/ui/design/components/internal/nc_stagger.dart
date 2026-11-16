import 'package:material_ui/material_ui.dart';

import '../../../motion.dart';
import '../../motion_scope.dart';

/// Каскадное появление элемента списка (REDESIGN-SPEC §6.2 `stagger`).
///
/// Fade + сдвиг 8 px; шаг 28 мс, не больше 8 элементов. В режиме «Стандартная
/// анимация» и при `MediaQuery.disableAnimations` каскада нет — общий fade
/// 160 мс (§6.4). Анимация одноразовая (появление), поэтому `pumpAndSettle`
/// в тестах работает.
class NcStagger extends StatelessWidget {
  /// Оборачивает [child] каскадом; [index] — позиция в списке.
  const NcStagger({
    super.key,
    required this.child,
    this.index = 0,
    this.enabled = true,
    this.offset = 8,
  });

  /// Ребёнок.
  final Widget child;

  /// Позиция в каскаде.
  final int index;

  /// Разрешён ли каскад (например, скелетоны его не используют).
  final bool enabled;

  /// Сдвиг снизу в логических px до появления.
  final double offset;

  @override
  Widget build(BuildContext context) {
    final NcMotion motion = NcMotion.of(context);
    if (!enabled) return child;
    final Duration delay = motion.staggerEnabled
        ? AppMotion.staggerDelay(index)
        : Duration.zero;
    final Duration total = motion.reduceMotion
        ? AppMotion.fast
        : AppMotion.base + delay;
    final double start = total.inMicroseconds == 0
        ? 0
        : delay.inMicroseconds / total.inMicroseconds;
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        start.clamp(0, 1),
        1,
        curve: motion.reduceMotion ? AppMotion.fastCurve : AppMotion.baseCurve,
      ),
      builder: (BuildContext context, double value, Widget? child) {
        return Opacity(
          opacity: value,
          child: Transform.translate(
            offset: Offset(0, offset * (1 - value)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
