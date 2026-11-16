import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/tokens/nc_glass.dart';
import 'package:cardflow/ui/design/tokens/nc_colors.dart';
import 'package:cardflow/ui/design/tokens/nc_depth.dart';

/// Глубина и стекло Nocturne (REDESIGN-SPEC §3.3 и §4.1).
void main() {
  group('NcDepth: тени вместо elevation §3.3', () {
    final NcDepth dark = NcDepth.dark;

    test('depth0 — без теней', () {
      expect(dark.depth0, isEmpty);
      expect(NcDepth.level(0, dark: true), isEmpty);
    });

    test('depth1 / depth2 / depth3 — по две тени с параметрами таблицы', () {
      expect(dark.depth1, hasLength(2));
      expect(dark.depth1[0].offset, const Offset(0, 1));
      expect(dark.depth1[0].blurRadius, 2);
      expect(dark.depth1[0].color.a, closeTo(0.40, 0.02));
      expect(dark.depth1[1].offset, const Offset(0, 4));
      expect(dark.depth1[1].blurRadius, 12);
      expect(dark.depth1[1].color.a, closeTo(0.24, 0.02));

      expect(dark.depth2[0].offset, const Offset(0, 8));
      expect(dark.depth2[0].blurRadius, 24);
      expect(dark.depth2[0].color.a, closeTo(0.45, 0.02));
      expect(dark.depth2[1].offset, const Offset(0, 2));
      expect(dark.depth2[1].blurRadius, 6);

      expect(dark.depth3[0].offset, const Offset(0, 28));
      expect(dark.depth3[0].blurRadius, 64);
      expect(dark.depth3[0].color.a, closeTo(0.55, 0.02));
      expect(dark.depth3[1].offset, const Offset(0, 8));
      expect(dark.depth3[1].blurRadius, 20);
    });

    test('тени — производные от цвета холста, без сырых литералов', () {
      expect(dark.depth1.first.color, NcColors.black.withValues(alpha: 0.40));
      expect(NcDepth.level(1, dark: true), dark.depth1);
    });

    test('glow: одна цветная тень главного CTA', () {
      final List<BoxShadow> glow = dark.glow(const Color(0xFFE4C88F));
      expect(glow, hasLength(2));
      expect(glow[0].spreadRadius, 1);
      expect(glow[0].blurRadius, 0);
      expect(glow[0].color.a, closeTo(0.40, 0.02));
      expect(glow[1].offset, const Offset(0, 12));
      expect(glow[1].blurRadius, 32);
      expect(glow[1].color.a, closeTo(0.28, 0.02));
    });

    test('Porcelain: тени мягче (×0,5) и теплее', () {
      final NcDepth light = NcDepth.light;
      expect(light.depth1.first.color.a, closeTo(0.20, 0.02));
      expect(light.depth3.first.color.a, closeTo(0.275, 0.02));
      expect(light.shadowTint, const Color(0xFF3A2E1A));
      expect(dark.shadowTint, NcColors.black);
    });
  });

  group('NcGlass: материалы §4.1', () {
    final NcGlassMaterials glass = NcGlassMaterials.dark;

    test('три толщины: blur, tint, saturation, шум', () {
      expect(glass.thin.blurSigma, 16);
      expect(glass.thin.tint, NcColors.dark().ink1.withValues(alpha: 0.52));
      expect(glass.thin.saturation, closeTo(1.10, 0.001));
      expect(glass.thin.noiseOpacity, closeTo(0.02, 0.005));

      expect(glass.regular.blurSigma, 28);
      expect(glass.regular.tint, NcColors.dark().ink1.withValues(alpha: 0.62));
      expect(glass.regular.saturation, closeTo(1.15, 0.001));
      expect(glass.regular.noiseOpacity, closeTo(0.025, 0.005));

      expect(glass.thick.blurSigma, 44);
      expect(glass.thick.tint, NcColors.dark().ink2.withValues(alpha: 0.74));
      expect(glass.thick.saturation, closeTo(1.20, 0.001));
      expect(glass.thick.noiseOpacity, closeTo(0.03, 0.005));
    });

    test('рамка и блик: thin без rim light, regular/thick с бликом', () {
      expect(glass.thin.borderColor, NcColors.dark().hairlineStrong);
      expect(glass.thin.rimLightOpacity, 0);
      expect(glass.regular.rimLightOpacity, greaterThan(0));
      expect(glass.thick.rimLightOpacity, greaterThan(0));
    });

    test('high contrast: сплошная поверхность ink3 без размытия', () {
      final NcGlassMaterial solid = NcGlassMaterials.solid(NcColors.dark());
      expect(solid.blurSigma, 0);
      expect(solid.tint, NcColors.dark().ink3);
      expect(solid.noiseOpacity, 0);
      expect(solid.isSolid, isTrue);
      expect(glass.regular.isSolid, isFalse);
    });

    test('фильтр: compose(saturation, blur) и матрица насыщенности', () {
      final ui.ImageFilter filter = glass.regular.filter;
      expect(filter, isA<ui.ImageFilter>());
      final List<double> identity = NcGlassMaterials.saturationMatrix(1);
      expect(identity, hasLength(20));
      expect(identity[0], closeTo(1, 0.001));
      expect(identity[6], closeTo(1, 0.001));
      expect(identity[12], closeTo(1, 0.001));
      expect(identity[18], 1);
      expect(identity[19], 0);

      final List<double> boosted = NcGlassMaterials.saturationMatrix(1.2);
      expect(boosted[0], greaterThan(1));
      expect(boosted[6], greaterThan(1));
      expect(boosted[12], greaterThan(1));
      expect(boosted[19], 0);
    });
  });
}
