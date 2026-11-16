import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../nc_theme.dart';

/// Тонкое кольцо ожидания с градиентом `aurum` (REDESIGN-SPEC §8).
///
/// Для инлайн-ожидания: кнопки, проверка ключа, догрузка строки. Кольцо
/// вращается; в тестах — только `pump(Duration)`, не `pumpAndSettle` (§6.4).
class NcSpinner extends StatefulWidget {
  /// Создаёт спиннер.
  const NcSpinner({
    super.key,
    this.size = 18,
    this.strokeWidth = 2,
    this.color,
    this.semanticLabel,
    this.period = const Duration(milliseconds: 900),
  });

  /// Сторона кольца.
  final double size;

  /// Толщина кольца.
  final double strokeWidth;

  /// Базовый цвет (по умолчанию `aurum`).
  final Color? color;

  /// Текст семантики (из ARB, например «Загрузка»).
  final String? semanticLabel;

  /// Период полного оборота.
  final Duration period;

  @override
  State<NcSpinner> createState() => _NcSpinnerState();
}

class _NcSpinnerState extends State<NcSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.period,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final bool reduced = MediaQuery.disableAnimationsOf(context);
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
    final Color color = widget.color ?? theme.colors.aurum;
    final Widget ring = SizedBox.square(
      dimension: widget.size,
      child: CustomPaint(
        painter: _NcSpinnerPainter(
          color: color,
          trackColor: theme.colors.ink5,
          strokeWidth: widget.strokeWidth,
        ),
      ),
    );
    final Widget rotating = RotationTransition(turns: _controller, child: ring);
    if (widget.semanticLabel == null) return rotating;
    return Semantics(
      label: widget.semanticLabel,
      liveRegion: true,
      child: rotating,
    );
  }
}

class _NcSpinnerPainter extends CustomPainter {
  const _NcSpinnerPainter({
    required this.color,
    required this.trackColor,
    required this.strokeWidth,
  });

  final Color color;
  final Color trackColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = Rect.fromLTWH(
      strokeWidth / 2,
      strokeWidth / 2,
      size.width - strokeWidth,
      size.height - strokeWidth,
    );
    final Paint base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawArc(rect, 0, math.pi * 2, false, base);
    final Paint accent = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        colors: <Color>[color.withValues(alpha: 0), color],
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 1.35, false, accent);
  }

  @override
  bool shouldRepaint(_NcSpinnerPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.trackColor != trackColor ||
      oldDelegate.strokeWidth != strokeWidth;
}
