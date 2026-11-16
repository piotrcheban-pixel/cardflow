import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';

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
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Color fromColor = from ?? theme.colors.aurumDeep;
    final Color toColor = to ?? theme.colors.aurumBright;
    final Color track = trackColor ?? theme.colors.ink5;
    final double clamped = value.clamp(0.0, 1.0);

    Widget arc(double progress) => CustomPaint(
      size: Size.square(size),
      painter: _NcRingPainter(
        progress: progress,
        strokeWidth: strokeWidth,
        from: fromColor,
        to: toColor,
        track: track,
      ),
    );

    final Widget ring = animated
        ? NcSpringBuilder(
            value: clamped,
            spring: NcMotion.of(context).standardSpring(),
            builder: (BuildContext context, double progress) =>
                arc(progress.clamp(0.0, 1.0)),
          )
        : arc(clamped);

    final Widget content = SizedBox.square(
      dimension: size,
      child: Stack(
        alignment: Alignment.center,
        children: <Widget>[
          ring,
          Center(child: child),
        ],
      ),
    );
    if (semanticLabel == null) return content;
    return Semantics(
      label: semanticLabel,
      value: '${(clamped * 100).round()}%',
      child: content,
    );
  }
}

class _NcRingPainter extends CustomPainter {
  const _NcRingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.from,
    required this.to,
    required this.track,
  });

  final double progress;
  final double strokeWidth;
  final Color from;
  final Color to;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final Offset center = size.center(Offset.zero);
    final double radius = (size.shortestSide - strokeWidth) / 2;
    final Paint trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = track;
    canvas.drawCircle(center, radius, trackPaint);
    if (progress <= 0) return;

    final Rect rect = Rect.fromCircle(center: center, radius: radius);
    final Paint arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: <Color>[from, to],
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect);
    canvas.drawArc(rect, -math.pi / 2, math.pi * 2 * progress, false, arc);

    final double endAngle = -math.pi / 2 + math.pi * 2 * progress;
    final Offset end = Offset(
      center.dx + radius * math.cos(endAngle),
      center.dy + radius * math.sin(endAngle),
    );
    canvas.drawCircle(
      end,
      strokeWidth * 0.32,
      Paint()
        ..color = to.withValues(alpha: 0.35)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    canvas.drawCircle(end, strokeWidth * 0.18, Paint()..color = to);
  }

  @override
  bool shouldRepaint(_NcRingPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.strokeWidth != strokeWidth ||
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.track != track;
}
