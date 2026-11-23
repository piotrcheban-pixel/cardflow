import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';

/// Адаптивная ступень типографики (аудит v4, V8).
///
/// Множитель считается по физическому разрешению экрана: на 2K шкала крупнее
/// в 1,24, на 4K — в 1,45 (верхняя граница шкалы). В `flutter test` множитель
/// всегда 1,0, чтобы вёрстка проверялась на эталонной шкале; сама функция
/// проверяется здесь.
void main() {
  group('AppAdaptive.factorForPhysical', () {
    test('FullHD и меньше — базовая шкала', () {
      expect(AppAdaptive.factorForPhysical(const Size(1920, 1080)), 1.0);
      expect(AppAdaptive.factorForPhysical(const Size(1366, 768)), 1.0);
      expect(AppAdaptive.factorForPhysical(const Size(1024, 768)), 1.0);
      // 800×600 при DPI 150 % — 533×400 логических, физически меньше FullHD.
      expect(AppAdaptive.factorForPhysical(const Size(800, 600)), 1.0);
    });

    test('2K (2560×1440) — крупнее на 24 %', () {
      expect(
        AppAdaptive.factorForPhysical(const Size(2560, 1440)),
        closeTo(1.24, 1e-9),
      );
    });

    test('4K (3840×2160) — верхняя граница 1,45', () {
      expect(
        AppAdaptive.factorForPhysical(const Size(3840, 2160)),
        closeTo(AppAdaptive.maxFactor, 1e-9),
      );
    });

    test('21:9 (2560×1080) — промежуточная ступень', () {
      final double factor = AppAdaptive.factorForPhysical(
        const Size(2560, 1080),
      );
      expect(factor, greaterThan(1.0));
      expect(factor, lessThan(1.24));
    });

    test('некорректный размер не ломает шкалу', () {
      expect(AppAdaptive.factorForPhysical(Size.zero), 1.0);
      expect(AppAdaptive.factorForPhysical(const Size(double.nan, 1080)), 1.0);
    });
  });

  test('в тестовом окружении множитель 1,0', () {
    expect(AppAdaptive.factorForCurrentWindow(), 1.0);
  });
}
