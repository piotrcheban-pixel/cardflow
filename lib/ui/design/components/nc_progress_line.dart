import 'package:material_ui/material_ui.dart';

import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';
import '../tokens/nc_radii.dart';

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
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final Color accent = color ?? theme.colors.aurum;
    final Widget line = LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 200;
        Widget track(double progress) {
          final double clamped = progress.clamp(0.0, 1.0);
          return SizedBox(
            height: height,
            width: width,
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      color: trackColor ?? theme.colors.ink5,
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(NcRadii.pill),
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    key: fillKey,
                    width: width * clamped,
                    height: height,
                    child: ClipRSuperellipse(
                      borderRadius: BorderRadius.circular(NcRadii.pill),
                      child: Stack(
                        children: <Widget>[
                          Positioned.fill(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: <Color>[
                                    Color.alphaBlend(
                                      accent.withValues(alpha: 0.85),
                                      NcColors.transparent,
                                    ),
                                    accent,
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Positioned(
                            right: 0,
                            top: 0,
                            bottom: 0,
                            width: 2,
                            child: ColoredBox(
                              color: Color.alphaBlend(
                                NcColors.white.withValues(alpha: 0.55),
                                accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }

        if (!animated) return track(value);
        return NcSpringBuilder(
          value: value.clamp(0.0, 1.0),
          spring: NcMotion.of(context).standardSpring(),
          builder: (BuildContext context, double progress) => track(progress),
        );
      },
    );
    if (semanticLabel == null) return line;
    return Semantics(
      label: semanticLabel,
      value: '${(value.clamp(0.0, 1.0) * 100).round()}%',
      child: line,
    );
  }
}
