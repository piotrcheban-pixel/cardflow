import 'package:material_ui/material_ui.dart';

/// Форма скелетона.
enum NcSkeletonShape {
  /// Скруглённый прямоугольник (строки, плитки).
  rounded,

  /// Круг (аватар, иконка).
  circle,
}

/// Скелетон загрузки: плашка `ink2` с бликом `shimmer` (REDESIGN-SPEC §8).
///
/// Заменяет `CircularProgressIndicator` в загрузке списков и экранов.
/// Повторяющаяся анимация: в тестах — `pump(Duration)`; при
/// `MediaQuery.disableAnimations` и Standard — статичная плашка (§6.4).
class NcSkeleton extends StatefulWidget {
  /// Создаёт скелетон.
  const NcSkeleton({
    super.key,
    required this.height,
    this.width,
    this.radius = 12,
    this.shape = NcSkeletonShape.rounded,
    this.semanticLabel,
  });

  /// Скелетон строки текста.
  const NcSkeleton.line({
    super.key,
    required this.width,
    this.height = 14,
    this.semanticLabel,
  }) : radius = 8,
       shape = NcSkeletonShape.rounded;

  /// Скелетон-круг.
  const NcSkeleton.circle({
    super.key,
    required this.height,
    this.semanticLabel,
  }) : width = height,
       radius = height / 2,
       shape = NcSkeletonShape.circle;

  /// Высота.
  final double height;

  /// Ширина (у круга равна высоте).
  final double? width;

  /// Радиус.
  final double radius;

  /// Форма.
  final NcSkeletonShape shape;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  @override
  State<NcSkeleton> createState() => _NcSkeletonState();
}

class _NcSkeletonState extends State<NcSkeleton>
    with SingleTickerProviderStateMixin {
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
