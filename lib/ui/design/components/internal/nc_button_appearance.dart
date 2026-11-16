import 'package:material_ui/material_ui.dart';

import '../../tokens/nc_radii.dart';
import '../nc_button.dart';
import '../../nc_theme.dart';

/// Оформление кнопки Nocturne как данные: заливка/градиент, текст, рамка, тени.
///
/// Одна точка правды для `NcButton` и `NcSplitButton` (стрелка меню должна
/// совпадать с главным сегментом пиксель в пиксель).
@immutable
class NcButtonAppearance {
  const NcButtonAppearance({
    this.gradient,
    this.color,
    required this.foreground,
    this.borderColor,
    this.shadows = const <BoxShadow>[],
    this.iconColor,
  });

  /// Градиент заливки (primary — Aurum, ai — Iris).
  final Gradient? gradient;

  /// Сплошная заливка.
  final Color? color;

  /// Цвет текста и иконки.
  final Color foreground;

  /// Цвет рамки (null — без рамки).
  final Color? borderColor;

  /// Тени (`glow` у главного CTA).
  final List<BoxShadow> shadows;

  /// Цвет иконки, если отличается от текста.
  final Color? iconColor;

  /// Вычисляет оформление варианта с учётом состояния.
  static NcButtonAppearance resolve(
    NcTheme theme,
    NcButtonVariant variant, {
    required bool enabled,
    required bool prominent,
    required bool hovered,
  }) {
    final colors = theme.colors;
    final List<BoxShadow> glow = prominent
        ? theme.depth.glow(colors.aurum)
        : const <BoxShadow>[];
    if (!enabled) {
      return NcButtonAppearance(
        color: colors.ink4,
        foreground: colors.textDisabled,
        iconColor: colors.textDisabled,
      );
    }
    switch (variant) {
      case NcButtonVariant.primary:
        return NcButtonAppearance(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.aurumBright, colors.aurumDeep],
          ),
          foreground: colors.textOnAccent,
          shadows: glow,
          iconColor: colors.textOnAccent,
        );
      case NcButtonVariant.secondary:
        return NcButtonAppearance(
          color: hovered ? colors.ink5 : colors.ink4,
          foreground: colors.textPrimary,
          borderColor: colors.hairlineStrong,
          shadows: prominent ? glow : const <BoxShadow>[],
        );
      case NcButtonVariant.ghost:
        return NcButtonAppearance(
          color: hovered ? colors.ink4 : null,
          foreground: colors.textPrimary,
          shadows: prominent ? glow : const <BoxShadow>[],
        );
      case NcButtonVariant.destructive:
        return NcButtonAppearance(
          color: hovered
              ? Color.alphaBlend(
                  colors.ember.withValues(alpha: 0.10),
                  colors.emberSoft,
                )
              : colors.emberSoft,
          foreground: colors.ember,
          borderColor: colors.ember.withValues(alpha: 0.30),
        );
      case NcButtonVariant.ai:
        return NcButtonAppearance(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[colors.iris, colors.irisDeep],
          ),
          foreground: colors.textOnAccent,
          shadows: theme.depth.glow(colors.iris),
          iconColor: colors.textOnAccent,
        );
    }
  }

  /// Оборачивает [child] заливкой/рамкой/тенями с радиусом [radius].
  Widget decorate(Widget child, {required double radius}) {
    final BorderRadius borderRadius = BorderRadius.circular(radius);
    return DecoratedBox(
      decoration: ShapeDecoration(
        color: gradient == null ? color : null,
        gradient: gradient,
        shadows: shadows,
        shape: RoundedSuperellipseBorder(
          borderRadius: borderRadius,
          side: borderColor == null
              ? BorderSide.none
              : BorderSide(color: borderColor!),
        ),
      ),
      child: ClipRSuperellipse(borderRadius: borderRadius, child: child),
    );
  }

  /// Высота кнопки по размеру (§8: 36 / 48 / 56).
  static double height(NcButtonSize size) => switch (size) {
    NcButtonSize.s => 36,
    NcButtonSize.m => 48,
    NcButtonSize.l => 56,
  };

  /// Горизонтальный отступ по размеру.
  static double horizontalPadding(NcButtonSize size) => switch (size) {
    NcButtonSize.s => 12,
    NcButtonSize.m => 20,
    NcButtonSize.l => 24,
  };

  /// Размер иконки по размеру кнопки.
  static double iconSize(NcButtonSize size) => switch (size) {
    NcButtonSize.s => 16,
    NcButtonSize.m => 18,
    NcButtonSize.l => 20,
  };

  /// Радиус кнопки — pill (§3.2).
  static const double radius = NcRadii.pill;
}
