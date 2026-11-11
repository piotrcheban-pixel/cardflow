import 'dart:math' as math;

import 'package:cardflow/ui/m3e/m3e.dart' as m3e;
import 'package:cardflow/ui/motion.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:flutter/widgets.dart' show Brightness;
import 'package:flutter_test/flutter_test.dart';

/// Итерация 0, спайк S2: слой M3E изолирован и его токены совпадают со SPEC A4.4.
void main() {
  group('lib/ui/m3e: изоляция M3 Expressive-библиотеки (ADR-001)', () {
    test('токены движения M3E совпадают с AppMotion (SPEC A4.4)', () {
      final expressive = m3e.M3EMotion.expressiveSpatialDefault;
      expect(expressive.stiffness, AppMotion.expressiveStiffness);
      expect(expressive.damping, AppMotion.expressiveDampingRatio);

      final standard = m3e.M3EMotion.spatialDefault;
      expect(standard.stiffness, AppMotion.standardStiffness);
      expect(standard.damping, AppMotion.standardDampingRatio);

      final effects = m3e.M3EMotion.effectsDefault;
      expect(effects.stiffness, AppMotion.effectsStiffness);
      expect(effects.damping, AppMotion.effectsDampingRatio);
    });

    test('SpringDescription из AppMotion соответствует токенам M3E', () {
      final spring = AppMotion.expressiveSpring();
      final ratio =
          spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass));
      final m3eSpring = m3e.M3EMotion.expressiveSpatialDefault;
      expect(ratio, closeTo(m3eSpring.damping, 1e-12));
      expect(spring.stiffness, m3eSpring.stiffness);
    });

    test('M3E-тема строится из бренд-сида', () {
      final light = m3e.M3EThemeData.light(seedColor: AppTheme.seedColor);
      final dark = m3e.M3EThemeData.dark(seedColor: AppTheme.seedColor);

      expect(light.brightness, equals(Brightness.light));
      expect(dark.brightness, equals(Brightness.dark));
      expect(light.colorScheme, isNot(equals(dark.colorScheme)));
    });
  });
}
