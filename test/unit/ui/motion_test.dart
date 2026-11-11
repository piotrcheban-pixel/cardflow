import 'dart:math' as math;

import 'package:cardflow/ui/motion.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AppMotion: токены движения M3 Expressive (SPEC A4.4)', () {
    test('expressive: stiffness 380, damping ratio 0.8', () {
      expect(AppMotion.expressiveStiffness, 380);
      expect(AppMotion.expressiveDampingRatio, 0.8);

      final spring = AppMotion.expressiveSpring();
      expect(spring.stiffness, 380);
      expect(spring.mass, 1);
      expect(
        spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass)),
        closeTo(0.8, 1e-12),
      );
    });

    test('standard: stiffness 700, damping ratio 0.9', () {
      expect(AppMotion.standardStiffness, 700);
      expect(AppMotion.standardDampingRatio, 0.9);

      final spring = AppMotion.standardSpring();
      expect(spring.stiffness, 700);
      expect(
        spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass)),
        closeTo(0.9, 1e-12),
      );
    });

    test(
      'expressive-пружина мягче стандартной, стандартная не даёт overshoot',
      () {
        expect(
          AppMotion.expressiveStiffness,
          lessThan(AppMotion.standardStiffness),
        );
        expect(
          AppMotion.expressiveDampingRatio,
          lessThan(AppMotion.standardDampingRatio),
        );
        expect(AppMotion.standardDampingRatio, lessThan(1.0));
        expect(AppMotion.effectsDampingRatio, 1.0);
      },
    );

    test('damping — абсолютный коэффициент, а не ratio (частая ошибка)', () {
      final spring = AppMotion.expressiveSpring();
      expect(spring.damping, isNot(closeTo(0.8, 1e-6)));
      expect(spring.damping, greaterThan(1));
    });

    test('effects-пружина критически задемпфирована, без overshoot', () {
      final spring = AppMotion.effectsSpring();
      expect(
        spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass)),
        closeTo(1.0, 1e-12),
      );
    });
  });
}
