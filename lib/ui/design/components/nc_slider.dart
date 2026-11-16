import 'package:material_ui/material_ui.dart';

import '../haptics.dart';
import '../nc_theme.dart';
import '../tokens/nc_radii.dart';

/// Слайдер Nocturne (REDESIGN-SPEC §8): трек 6 px `ink5`, активная часть —
/// градиент Aurum, бегунок 22 px, при перетаскивании — пузырь со значением
/// (`monoM`). Тактильный отклик — на каждой риске (`NcHaptics`, ≤ 40 мс).
class NcSlider extends StatelessWidget {
  /// Создаёт слайдер.
  const NcSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    this.onChanged,
    this.onChangeEnd,
    this.semanticLabel,
    this.valueLabel,
    this.enabled = true,
    this.focusNode,
  });

  /// Текущее значение.
  final double value;

  /// Минимум.
  final double min;

  /// Максимум.
  final double max;

  /// Число рисок (делений).
  final int? divisions;

  /// Изменение значения.
  final ValueChanged<double>? onChanged;

  /// Конец перетаскивания.
  final ValueChanged<double>? onChangeEnd;

  /// Текст семантики (из ARB).
  final String? semanticLabel;

  /// Подпись значения в пузыре (например, «90 %»); по умолчанию — число.
  final String Function(double value)? valueLabel;

  /// Включён ли слайдер.
  final bool enabled;

  /// Внешний узел фокуса.
  final FocusNode? focusNode;

  /// Высота трека.
  static const double trackHeight = 6;

  /// Диаметр бегунка.
  static const double thumbSize = 22;

  @override
  Widget build(BuildContext context) {
    final NcTheme theme = NcTheme.of(context);
    final bool active = enabled && onChanged != null;
    final String label = valueLabel?.call(value) ?? value.round().toString();
    final Widget slider = SliderTheme(
      data: SliderThemeData(
        trackHeight: trackHeight,
        activeTrackColor: theme.colors.aurum,
        inactiveTrackColor: theme.colors.ink5,
        disabledActiveTrackColor: theme.colors.ink4,
        disabledInactiveTrackColor: theme.colors.ink5,
        activeTickMarkColor: theme.colors.textOnAccent.withValues(alpha: 0.6),
        inactiveTickMarkColor: theme.colors.textTertiary,
        thumbColor: active ? theme.colors.aurum : theme.colors.textDisabled,
        overlayColor: theme.colors.aurum.withValues(alpha: 0.12),
        valueIndicatorColor: theme.colors.ink4,
        valueIndicatorTextStyle: theme.typography.monoM.copyWith(
          color: theme.colors.textPrimary,
        ),
        showValueIndicator: ShowValueIndicator.onDrag,
        trackShape: _NcSliderTrackShape(
          activeGradient: LinearGradient(
            colors: <Color>[theme.colors.aurumDeep, theme.colors.aurumBright],
          ),
          inactiveColor: theme.colors.ink5,
        ),
        thumbShape: _NcSliderThumbShape(
          color: active ? theme.colors.aurum : theme.colors.textDisabled,
          glow: active ? theme.depth.glow(theme.colors.aurum) : const [],
        ),
        valueIndicatorShape: _NcValueBubbleShape(background: theme.colors.ink4),
      ),
      child: Slider(
        value: value.clamp(min, max),
        min: min,
        max: max,
        divisions: divisions,
        label: label,
        focusNode: focusNode,
        onChanged: active
            ? (double next) {
                NcHaptics.of(context).selectionClick();
                onChanged!(next);
              }
            : null,
        onChangeEnd: active ? onChangeEnd : null,
      ),
    );
    if (semanticLabel == null) return slider;
    return Semantics(label: semanticLabel, child: slider);
  }
}

class _NcSliderTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _NcSliderTrackShape({
    required this.activeGradient,
    required this.inactiveColor,
  });

  final Gradient activeGradient;
  final Color inactiveColor;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final Rect trackRect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final Radius radius = Radius.circular(trackRect.height / 2);
    final Canvas canvas = context.canvas;
    canvas.drawRRect(
      RRect.fromRectAndRadius(trackRect, radius),
      Paint()..color = inactiveColor,
    );
    if (thumbCenter.dx <= trackRect.left + 0.5) return;
    final Rect activeRect = Rect.fromLTRB(
      trackRect.left,
      trackRect.top,
      thumbCenter.dx,
      trackRect.bottom,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(activeRect, radius),
      Paint()..shader = activeGradient.createShader(activeRect),
    );
  }
}

class _NcSliderThumbShape extends SliderComponentShape {
  const _NcSliderThumbShape({required this.color, required this.glow});

  final Color color;
  final List<BoxShadow> glow;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) =>
      const Size(NcSlider.thumbSize, NcSlider.thumbSize);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final Canvas canvas = context.canvas;
    for (final BoxShadow shadow in glow) {
      canvas.drawCircle(
        center + shadow.offset,
        NcSlider.thumbSize / 2 + shadow.spreadRadius,
        Paint()
          ..color = shadow.color
          ..maskFilter = MaskFilter.blur(
            BlurStyle.normal,
            shadow.blurRadius / 2,
          ),
      );
    }
    canvas.drawCircle(center, NcSlider.thumbSize / 2, Paint()..color = color);
    canvas.drawCircle(
      center,
      NcSlider.thumbSize / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = sliderTheme.thumbColor ?? color,
    );
  }
}

class _NcValueBubbleShape extends SliderComponentShape {
  const _NcValueBubbleShape({required this.background});

  final Color background;

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(56, 34);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final double opacity = activationAnimation.value;
    if (opacity <= 0) return;
    final Size labelSize = labelPainter.size;
    final Rect rect = Rect.fromCenter(
      center: Offset(center.dx, center.dy - 30),
      width: labelSize.width + 16,
      height: labelSize.height + 8,
    );
    final Canvas canvas = context.canvas;
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(NcRadii.xs)),
      Paint()..color = background.withValues(alpha: background.a * opacity),
    );
    labelPainter.paint(
      canvas,
      rect.topLeft +
          Offset(
            (rect.width - labelSize.width) / 2,
            (rect.height - labelSize.height) / 2,
          ),
    );
  }
}
