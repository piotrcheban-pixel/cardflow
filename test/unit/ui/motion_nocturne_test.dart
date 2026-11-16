import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/ui/motion.dart';

/// Токены движения Nocturne (REDESIGN-SPEC §6.1–6.2).
///
/// Существующие токены M3E (expressive/standard/effects) не менялись — их
/// проверяет `test/unit/ui/motion_test.dart`. Здесь — добавленные.
void main() {
  group('AppMotion: новые пружины §6.1', () {
    const Map<String, (double, double)> springs = <String, (double, double)>{
      'press': (1200, 0.70),
      'snap': (900, 0.85),
      'gentle': (170, 0.90),
      'celebrate': (260, 0.55),
    };

    test('stiffness и damping ratio по таблице', () {
      expect(AppMotion.pressStiffness, 1200);
      expect(AppMotion.pressDampingRatio, 0.70);
      expect(AppMotion.snapStiffness, 900);
      expect(AppMotion.snapDampingRatio, 0.85);
      expect(AppMotion.gentleStiffness, 170);
      expect(AppMotion.gentleDampingRatio, 0.90);
      expect(AppMotion.celebrateStiffness, 260);
      expect(AppMotion.celebrateDampingRatio, 0.55);
    });

    test('пружины строятся через withDampingRatio (ratio = табличному)', () {
      final Map<String, SpringDescription> resolved =
          <String, SpringDescription>{
            'press': AppMotion.pressSpring(),
            'snap': AppMotion.snapSpring(),
            'gentle': AppMotion.gentleSpring(),
            'celebrate': AppMotion.celebrateSpring(),
          };
      for (final MapEntry<String, SpringDescription> entry
          in resolved.entries) {
        final (double stiffness, double ratio) = springs[entry.key]!;
        final SpringDescription spring = entry.value;
        expect(spring.stiffness, stiffness);
        expect(spring.mass, 1);
        expect(
          spring.damping / (2 * math.sqrt(spring.stiffness * spring.mass)),
          closeTo(ratio, 1e-12),
          reason: '${entry.key}: damping должен быть ratio, а не абсолют',
        );
      }
    });

    test('порядок жёсткости: gentle < celebrate < expressive < standard', () {
      expect(AppMotion.gentleStiffness, lessThan(AppMotion.celebrateStiffness));
      expect(
        AppMotion.celebrateStiffness,
        lessThan(AppMotion.expressiveStiffness),
      );
      expect(
        AppMotion.expressiveStiffness,
        lessThan(AppMotion.standardStiffness),
      );
      expect(AppMotion.pressStiffness, greaterThan(AppMotion.snapStiffness));
    });
  });

  group('AppMotion: длительности и кривые §6.2', () {
    test('длительности', () {
      expect(AppMotion.instant, const Duration(milliseconds: 90));
      expect(AppMotion.fast, const Duration(milliseconds: 160));
      expect(AppMotion.base, const Duration(milliseconds: 240));
      expect(AppMotion.exit, const Duration(milliseconds: 180));
      expect(AppMotion.page, const Duration(milliseconds: 420));
      expect(AppMotion.breathe, const Duration(milliseconds: 4000));
      expect(AppMotion.shimmer, const Duration(milliseconds: 1400));
      expect(
        AppMotion.ambient,
        greaterThanOrEqualTo(const Duration(seconds: 48)),
      );
      expect(AppMotion.ambient, lessThanOrEqualTo(const Duration(seconds: 64)));
    });

    test('stagger: 28 мс на элемент, не больше 8 элементов', () {
      expect(AppMotion.staggerStep, const Duration(milliseconds: 28));
      expect(AppMotion.maxStaggerItems, 8);
      expect(AppMotion.staggerDelay(0), Duration.zero);
      expect(AppMotion.staggerDelay(3), const Duration(milliseconds: 84));
      expect(AppMotion.staggerDelay(8), const Duration(milliseconds: 224));
      expect(AppMotion.staggerDelay(100), const Duration(milliseconds: 224));
      expect(AppMotion.staggerDelay(-1), Duration.zero);
    });

    test('кривые', () {
      expect(AppMotion.instantCurve, const Cubic(0.2, 0, 0, 1));
      expect(AppMotion.fastCurve, const Cubic(0.2, 0, 0, 1));
      expect(AppMotion.baseCurve, const Cubic(0.05, 0.7, 0.1, 1));
      expect(AppMotion.exitCurve, const Cubic(0.3, 0, 0.8, 0.15));
      expect(AppMotion.pageCurve, isA<Curve>());
      expect(AppMotion.ambientCurve, Curves.easeInOutSine);
      expect(AppMotion.breatheCurve, Curves.easeInOutSine);
      expect(AppMotion.shimmerCurve, Curves.linear);
    });

    test('величины отклика', () {
      expect(AppMotion.pressScale, 0.96);
      expect(AppMotion.hoverLift, 2);
      expect(AppMotion.glowPulseMs, 600);
    });
  });
}
