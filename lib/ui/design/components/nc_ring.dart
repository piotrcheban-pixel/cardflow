import 'package:material_ui/material_ui.dart';

/// Кольцевой индикатор (REDESIGN-SPEC §8): толщина 10, градиент по дуге, на
/// конце точка с glow. Для точности и удержания; в центре — любой виджет
/// (например, `NcAnimatedNumber`).
class NcRing extends StatelessWidget {
  /// Создаёт кольцо.
  const NcRing({
    super.key,
    required this.value,
    required this.size,
    required this.child,
    this.strokeWidth = 10,
    this.from,
    this.to,
    this.semanticLabel,
    this.animated = true,
    this.trackColor,
  });

  /// Прогресс 0..1.
  final double value;

  /// Внешний диаметр.
  final double size;

  /// Центральное содержимое.
  final Widget child;

  /// Толщина дуги.
  final double strokeWidth;

  /// Начало градиента (по умолчанию `aurumDeep`).
  final Color? from;

  /// Конец градиента (по умолчанию `aurumBright`).
  final Color? to;

  /// Текст семантики.
  final String? semanticLabel;

  /// Анимировать ли значение пружиной.
  final bool animated;

  /// Цвет трека.
  final Color? trackColor;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
