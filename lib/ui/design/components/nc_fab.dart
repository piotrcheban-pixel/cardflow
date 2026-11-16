import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import 'internal/nc_pressable.dart';
import 'internal/nc_spring_builder.dart';
import 'internal/nc_scroll_collapse.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';

/// Плавающая кнопка Nocturne (REDESIGN-SPEC §8): extended pill 56 с
/// `primary` + `glow`; при прокрутке вниз сжимается до круга 56, при
/// прокрутке вверх — разворачивается (`NcScrollCollapseScope`).
class NcFab extends StatelessWidget {
  /// Создаёт FAB.
  const NcFab({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon = Icons.add_rounded,
    this.semanticLabel,
  });

  /// Подпись (ARB); в свёрнутом виде скрыта, но остаётся в семантике.
  final String label;

  /// Действие.
  final VoidCallback? onPressed;

  /// Иконка.
  final IconData icon;

  /// Текст семантики (по умолчанию [label]).
  final String? semanticLabel;

  /// Диаметр свёрнутого FAB (§8).
  static const double collapsedSize = 56;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool collapsed = NcScrollCollapse.of(context);
    final TextStyle labelStyle = theme.typography.labelL;
    final TextPainter painter = TextPainter(
      text: TextSpan(text: label, style: labelStyle),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final double expandedWidth = collapsedSize + 12 + painter.width + 24;
    painter.dispose();

    return NcTappable(
      onTap: onPressed,
      enabled: onPressed != null,
      semanticLabel: semanticLabel ?? label,
      focusRadius: NcRadii.pill,
      child: NcSpringBuilder(
        value: collapsed ? 0 : 1,
        spring: NcMotion.of(context).standardSpring(),
        builder: (BuildContext context, double value) {
          final double width = lerpDouble(
            collapsedSize,
            expandedWidth,
            value.clamp(0.0, 1.0),
          )!;
          return SizedBox(
            height: collapsedSize,
            width: width,
            child: ClipRSuperellipse(
              borderRadius: BorderRadius.circular(NcRadii.pill),
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: expandedWidth,
                maxWidth: expandedWidth,
                child: SizedBox(
                  width: expandedWidth,
                  height: collapsedSize,
                  child: DecoratedBox(
                    decoration: ShapeDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: <Color>[
                          theme.colors.aurumBright,
                          theme.colors.aurumDeep,
                        ],
                      ),
                      shadows: theme.depth.glow(theme.colors.aurum),
                      shape: RoundedSuperellipseBorder(
                        borderRadius: BorderRadius.circular(NcRadii.pill),
                      ),
                    ),
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: collapsedSize,
                          height: collapsedSize,
                          child: Center(
                            child: Icon(
                              icon,
                              size: 24,
                              color: theme.colors.textOnAccent,
                            ),
                          ),
                        ),
                        if (!collapsed)
                          Expanded(
                            child: Text(
                              label,
                              maxLines: 1,
                              overflow: TextOverflow.clip,
                              softWrap: false,
                              style: labelStyle.copyWith(
                                color: theme.colors.textOnAccent,
                              ),
                            ),
                          ),
                        if (!collapsed) const SizedBox(width: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
