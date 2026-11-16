import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Контраст WCAG 2.1 (relative luminance) — для тестов дизайн-системы.
///
/// Пороги REDESIGN-SPEC §10: текст ≥ 4,5 : 1, крупный текст ≥ 3 : 1,
/// иконки управления ≥ 3 : 1. Компоненты `Color` в Flutter — sRGB 0…1.
double _toLinear(double channel) {
  if (channel <= 0.03928) return channel / 12.92;
  return math.pow((channel + 0.055) / 1.055, 2.4).toDouble();
}

/// Относительная яркость цвета по WCAG 2.1.
double relativeLuminance(Color color) =>
    0.2126 * _toLinear(color.r) +
    0.7152 * _toLinear(color.g) +
    0.0722 * _toLinear(color.b);

/// Контраст между двумя цветами.
double contrastRatio(Color a, Color b) {
  final double la = relativeLuminance(a);
  final double lb = relativeLuminance(b);
  final double hi = math.max(la, lb);
  final double lo = math.min(la, lb);
  return (hi + 0.05) / (lo + 0.05);
}
