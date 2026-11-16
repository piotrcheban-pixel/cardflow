import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/motion_scope.dart';
import 'package:cardflow/ui/motion.dart';

/// `NcMotion`: пружины и флаги по настройке движения (REDESIGN-SPEC §6.4).
void main() {
  group('NcMotion.resolve: режимы движения', () {
    test('выразительный режим — все флаги включены', () {
      final NcMotion motion = NcMotion.resolve();
      expect(motion.preference, NcMotionPreference.expressive);
      expect(motion.isExpressive, isTrue);
      expect(motion.ambientDrift, isTrue);
      expect(motion.staggerEnabled, isTrue);
      expect(motion.celebrateEnabled, isTrue);
      expect(motion.flipAsCrossfade, isFalse);
      expect(motion.gentleSpring().stiffness, AppMotion.gentleStiffness);
      expect(motion.celebrateSpring().stiffness, AppMotion.celebrateStiffness);
    });

    test('стандартный режим: expressive/gentle/celebrate → standard', () {
      final NcMotion motion = NcMotion.resolve(
        preference: NcMotionPreference.standard,
      );
      expect(motion.isExpressive, isFalse);
      expect(motion.ambientDrift, isFalse);
      expect(motion.staggerEnabled, isFalse);
      expect(motion.celebrateEnabled, isFalse);
      expect(motion.flipAsCrossfade, isFalse);
      expect(motion.expressiveSpring().stiffness, AppMotion.standardStiffness);
      expect(motion.gentleSpring().stiffness, AppMotion.standardStiffness);
      expect(motion.celebrateSpring().stiffness, AppMotion.standardStiffness);
      // Переворот остаётся: это смысл, а не украшение (§6.4).
      expect(motion.flipEnabled, isTrue);
    });

    test('disableAnimations: переворот кроссфейдом, без дрейфа и искр', () {
      final NcMotion motion = NcMotion.resolve(disableAnimations: true);
      expect(motion.reduceMotion, isTrue);
      expect(motion.ambientDrift, isFalse);
      expect(motion.celebrateEnabled, isFalse);
      expect(motion.staggerEnabled, isFalse);
      expect(motion.flipAsCrossfade, isTrue);
      expect(motion.flipEnabled, isTrue);
      expect(motion.pageDuration, AppMotion.instant);
    });

    test('служебные пружины остаются в обоих режимах', () {
      final NcMotion standard = NcMotion.resolve(
        preference: NcMotionPreference.standard,
      );
      expect(standard.pressSpring().stiffness, AppMotion.pressStiffness);
      expect(standard.snapSpring().stiffness, AppMotion.snapStiffness);
      expect(standard.standardSpring().stiffness, AppMotion.standardStiffness);
    });

    test('равенство по настройке (для InheritedWidget)', () {
      expect(NcMotion.resolve(), NcMotion.resolve());
      expect(
        NcMotion.resolve(),
        isNot(NcMotion.resolve(preference: NcMotionPreference.standard)),
      );
      expect(
        NcMotion.resolve(disableAnimations: true),
        isNot(NcMotion.resolve()),
      );
    });

    test('пружины — SpringDescription', () {
      for (final SpringDescription spring in <SpringDescription>[
        NcMotion.resolve().expressiveSpring(),
        NcMotion.resolve().standardSpring(),
        NcMotion.resolve().pressSpring(),
        NcMotion.resolve().snapSpring(),
        NcMotion.resolve().gentleSpring(),
        NcMotion.resolve().celebrateSpring(),
        NcMotion.resolve().effectsSpring(),
      ]) {
        expect(spring.mass, 1);
      }
    });
  });

  group('NcMotionScope: доступ из дерева', () {
    testWidgets('of() берёт значение из scope, иначе — стандарт', (
      tester,
    ) async {
      late NcMotion inherited;
      await tester.pumpWidget(
        NcMotionScope(
          motion: NcMotion.resolve(disableAnimations: true),
          child: Builder(
            builder: (BuildContext context) {
              inherited = NcMotion.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(inherited.reduceMotion, isTrue);

      late NcMotion withoutScope;
      await tester.pumpWidget(
        Builder(
          builder: (BuildContext context) {
            withoutScope = NcMotion.of(context);
            return const SizedBox.shrink();
          },
        ),
      );
      expect(withoutScope.isExpressive, isTrue);
      expect(withoutScope.reduceMotion, isFalse);
    });
  });
}
