import 'package:material_ui/material_ui.dart';

import '../../motion.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';

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
  const NcSkeleton.circle({super.key, required this.height, this.semanticLabel})
    : width = height,
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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: AppMotion.shimmer,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced =
        MediaQuery.disableAnimationsOf(context) ||
        NcMotion.of(context).reduceMotion;
    if (reduced) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final double width = widget.width ?? widget.height;
    final Widget skeleton = SizedBox(
      width: width,
      height: widget.height,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) => CustomPaint(
          painter: _NcSkeletonPainter(
            base: theme.colors.ink2,
            highlight: theme.colors.textPrimary.withValues(alpha: 0.06),
            progress: _controller.value,
            radius: widget.radius,
            circle: widget.shape == NcSkeletonShape.circle,
          ),
        ),
      ),
    );
    if (widget.semanticLabel == null) return skeleton;
    return Semantics(label: widget.semanticLabel, child: skeleton);
  }
}

class _NcSkeletonPainter extends CustomPainter {
  const _NcSkeletonPainter({
    required this.base,
    required this.highlight,
    required this.progress,
    required this.radius,
    required this.circle,
  });

  final Color base;
  final Color highlight;
  final double progress;
  final double radius;
  final bool circle;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final Paint background = Paint()..color = base;
    final Rect rect = Offset.zero & size;
    if (circle) {
      canvas.drawCircle(rect.center, size.shortestSide / 2, background);
    } else {
      canvas.drawRRect(
        RRect.fromRectAndRadius(rect, Radius.circular(radius)),
        background,
      );
    }
    final double band = size.width * 0.6;
    final double left = -band + progress * (size.width + band * 2);
    final Paint shine = Paint()
      ..shader = LinearGradient(
        colors: <Color>[NcColors.transparent, highlight, NcColors.transparent],
      ).createShader(Rect.fromLTWH(left, 0, band, size.height));
    if (circle) {
      canvas.save();
      canvas.clipPath(Path()..addOval(rect));
      canvas.drawRect(Rect.fromLTWH(left, 0, band, size.height), shine);
      canvas.restore();
    } else {
      canvas.save();
      canvas.clipRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius)));
      canvas.drawRect(Rect.fromLTWH(left, 0, band, size.height), shine);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_NcSkeletonPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.base != base ||
      oldDelegate.highlight != highlight ||
      oldDelegate.radius != radius ||
      oldDelegate.circle != circle;
}
