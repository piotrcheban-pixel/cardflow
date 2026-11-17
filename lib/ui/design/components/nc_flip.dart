import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../tokens/nc_radii.dart';

/// 3D-переворот (REDESIGN-SPEC §6.3-1, §8): `rotateY` 0→π на `expressive`,
/// перспектива 0,0012; при уменьшении движения — кроссфейд 120 мс.
///
/// Управляется снаружи ([revealed]) — экран сессии держит состояние стороны.
class NcFlip extends StatelessWidget {
  /// Создаёт переворот.
  const NcFlip({
    super.key,
    required this.revealed,
    required this.front,
    required this.back,
    this.onTap,
    this.semanticLabel,
  });

  /// Показана ли обратная сторона.
  final bool revealed;

  /// Лицевая сторона.
  final Widget front;

  /// Обратная сторона.
  final Widget back;

  /// Тап по монолиту (переворот).
  final VoidCallback? onTap;

  /// Текст семантики стороны.
  final String? semanticLabel;

  /// Перспектива переворота.
  static const double perspective = 0.0012;

  /// Длительность кроссфейда при уменьшении движения.
  static const Duration crossfadeDuration = Duration(milliseconds: 120);

  @override
  Widget build(BuildContext context) {
    final NcMotion motion = NcMotion.of(context);
    final Widget content;
    if (motion.flipAsCrossfade) {
      content = Stack(
        fit: StackFit.passthrough,
        children: <Widget>[
          AnimatedOpacity(
            opacity: revealed ? 0 : 1,
            duration: crossfadeDuration,
            child: IgnorePointer(ignoring: revealed, child: front),
          ),
          AnimatedOpacity(
            opacity: revealed ? 1 : 0,
            duration: crossfadeDuration,
            child: IgnorePointer(ignoring: !revealed, child: back),
          ),
        ],
      );
    } else {
      content = NcSpringBuilder(
        value: revealed ? 1 : 0,
        spring: motion.expressiveSpring(),
        builder: (BuildContext context, double value) {
          final double progress = value.clamp(0.0, 1.0);
          final double angle = math.pi * progress;
          final bool showBack = progress > 0.5;
          final Matrix4 transform = Matrix4.identity()
            ..setEntry(3, 2, perspective)
            ..rotateY(angle);
          if (showBack) transform.rotateY(math.pi);
          return Transform(
            alignment: Alignment.center,
            transform: transform,
            child: showBack ? back : front,
          );
        },
      );
    }

    final Widget sized = content;
    if (onTap == null) return sized;
    return NcTappable(
      onTap: onTap,
      semanticLabel: semanticLabel,
      focusRadius: NcRadii.xl,
      scaleOnPress: false,
      includeSemantics: semanticLabel != null,
      child: sized,
    );
  }
}
