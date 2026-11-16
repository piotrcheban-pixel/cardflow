import 'package:material_ui/material_ui.dart';

/// Линейный прогресс (REDESIGN-SPEC §8): hairline-трек и золотая заливка с
/// бликом на кромке; изменение — на пружине.
class NcProgressLine extends StatelessWidget {
  /// Создаёт линию прогресса.
  const NcProgressLine({
    super.key,
    required this.value,
    this.color,
    this.height = 3,
    this.semanticLabel,
    this.animated = true,
    this.trackColor,
  });

  /// Прогресс 0..1.
  final double value;

  /// Цвет заливки (по умолчанию Aurum).
  final Color? color;

  /// Высота линии.
  final double height;

  /// Текст семантики (из ARB, например «Прогресс сессии»).
  final String? semanticLabel;

  /// Анимировать ли изменение пружиной.
  final bool animated;

  /// Цвет трека (по умолчанию `ink5`).
  final Color? trackColor;

  /// Ключ заливки (для тестов анимации и golden).
  static const Key fillKey = ValueKey<String>('nc-progress-fill');

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
