import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:material_ui/material_ui.dart';

import '../../motion.dart';
import '../tokens/nc_colors.dart';

/// Переходы страниц Nocturne (REDESIGN-SPEC §6.5, ADR-035).
///
/// Новая страница появляется fade + scale 0,98→1 + сдвигом 12 px снизу,
/// предыдущая — scale 1→0,98 и затемнением 24 %. На iOS/macOS остаётся
/// Cupertino-переход: только он сохраняет жест «назад» (отступление ADR-035,
/// п. 4).
///
/// Подключается через `ThemeData.pageTransitionsTheme` — роутер не меняется.
class NcPageTransitionsBuilder extends PageTransitionsBuilder {
  /// Создаёт билдер переходов.
  const NcPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _NcPageTransition(
    animation: animation,
    secondaryAnimation: secondaryAnimation,
    child: child,
  );
}

/// Набор переходов для `PageTransitionsTheme`.
abstract final class NcPageTransitions {
  /// Билдеры по платформам: Nocturne везде, кроме iOS/macOS (жест «назад»).
  static const PageTransitionsTheme theme = PageTransitionsTheme(
    builders: <TargetPlatform, PageTransitionsBuilder>{
      TargetPlatform.android: NcPageTransitionsBuilder(),
      TargetPlatform.fuchsia: NcPageTransitionsBuilder(),
      TargetPlatform.linux: NcPageTransitionsBuilder(),
      TargetPlatform.windows: NcPageTransitionsBuilder(),
      TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    },
  );
}

class _NcPageTransition extends StatelessWidget {
  const _NcPageTransition({
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Animation<double> enter = CurvedAnimation(
      parent: animation,
      curve: AppMotion.pageCurve,
      reverseCurve: AppMotion.exitCurve,
    );
    final Animation<double> exit = CurvedAnimation(
      parent: secondaryAnimation,
      curve: AppMotion.baseCurve,
    );
    return FadeTransition(
      opacity: enter,
      child: AnimatedBuilder(
        animation: Listenable.merge(<Listenable>[enter, exit]),
        child: child,
        builder: (BuildContext context, Widget? child) {
          final double t = enter.value.clamp(0.0, 1.0);
          final double e = exit.value.clamp(0.0, 1.0);
          final double scale = (0.98 + 0.02 * t) * (1 - 0.02 * e);
          return Transform.translate(
            offset: Offset(0, 12 * (1 - t)),
            child: Transform.scale(
              scale: scale,
              child: Stack(
                fit: StackFit.passthrough,
                children: <Widget>[
                  child ?? const SizedBox.shrink(),
                  if (e > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ColoredBox(
                          color: NcColors.black.withValues(alpha: 0.24 * e),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
