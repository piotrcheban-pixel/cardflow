import 'package:material_ui/material_ui.dart';

import '../haptics.dart';
import 'internal/nc_pressable.dart';
import 'internal/nc_spring_builder.dart';
import '../motion_scope.dart';
import '../nc_theme.dart';
import '../tokens/nc_colors.dart';

/// Переключатель Nocturne (REDESIGN-SPEC §8): 52 × 32, трек `ink5` → `aurum`,
/// бегунок `#F2EEE7` с тенью, перелёт на пружине `snap`; Space/Enter и
/// семантика `toggled`.
class NcSwitch extends StatelessWidget {
  /// Создаёт переключатель.
  const NcSwitch({
    super.key,
    required this.value,
    this.onChanged,
    this.semanticLabel,
    this.autofocus = false,
    this.focusNode,
  });

  /// Включён ли.
  final bool value;

  /// Переключение; `null` — неактивен.
  final ValueChanged<bool>? onChanged;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Запросить фокус при появлении.
  final bool autofocus;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Ширина трека.
  static const double width = 52;

  /// Высота трека.
  static const double height = 32;

  void _toggle(BuildContext context) {
    final ValueChanged<bool>? onChanged = this.onChanged;
    if (onChanged == null) return;
    NcHaptics.of(context).selectionClick();
    onChanged(!value);
  }

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool enabled = onChanged != null;
    final Color thumb = !enabled
        ? theme.colors.textDisabled
        : theme.isDark
        ? theme.colors.textPrimary
        : NcColors.white;

    final Widget trackWidget = SizedBox(
      width: width,
      height: height,
      child: NcSpringBuilder(
        value: value ? 1 : 0,
        spring: NcMotion.of(context).snapSpring(),
        builder: (BuildContext context, double progress) {
          final double clamped = progress.clamp(0.0, 1.0);
          return Stack(
            children: <Widget>[
              Positioned.fill(
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: Color.lerp(
                      theme.colors.ink5,
                      theme.colors.aurum,
                      clamped,
                    ),
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(height / 2),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 3 + clamped * (width - 26 - 6),
                top: 3,
                child: DecoratedBox(
                  decoration: ShapeDecoration(
                    color: thumb,
                    shadows: theme.depth.depth1,
                    shape: RoundedSuperellipseBorder(
                      borderRadius: BorderRadius.circular(13),
                    ),
                  ),
                  child: const SizedBox.square(dimension: 26),
                ),
              ),
            ],
          );
        },
      ),
    );

    return Semantics(
      toggled: value,
      enabled: enabled,
      label: semanticLabel,
      onTap: enabled ? () => _toggle(context) : null,
      child: ExcludeSemantics(
        child: NcTappable(
          onTap: enabled ? () => _toggle(context) : null,
          enabled: enabled,
          autofocus: autofocus,
          focusNode: focusNode,
          focusRadius: height / 2,
          scaleOnPress: false,
          haptic: null,
          includeSemantics: false,
          child: trackWidget,
        ),
      ),
    );
  }
}
