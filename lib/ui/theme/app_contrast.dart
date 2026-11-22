import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Контраст цветов по WCAG 2.1 (SPEC A4.1, аудит A1/D15/A6).
///
/// Единственное место с формулой относительной яркости: тесты палитры и
/// проверки конкретных пар (ссылка в баннере ошибки, чипы оценок) считают
/// контраст одинаково. Формула — WCAG 2.1 §1.4.3.
double relativeLuminance(Color color) {
  double channel(double value) => value <= 0.03928
      ? value / 12.92
      : math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

/// Отношение контраста двух непрозрачных цветов (1…21).
double contrastRatio(Color first, Color second) {
  final double a = relativeLuminance(first);
  final double b = relativeLuminance(second);
  final double lighter = math.max(a, b);
  final double darker = math.min(a, b);
  return (lighter + 0.05) / (darker + 0.05);
}

/// Контраст текста на фоне не ниже AA для обычного текста (4,5:1).
bool meetsAaTextContrast(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= 4.5;

/// Контраст нетекстовых элементов не ниже AA (3:1).
bool meetsAaGraphicsContrast(Color foreground, Color background) =>
    contrastRatio(foreground, background) >= 3;
