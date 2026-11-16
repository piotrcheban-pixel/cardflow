import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/tokens/nc_colors.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

void main() {
  group('AppTheme — настройки A6.6', () {
    test('шрифт дислексии меняет fontFamily темы', () {
      expect(
        AppTheme.light(dyslexiaFont: true).textTheme.bodyMedium?.fontFamily,
        AppTheme.dyslexiaFontFamily,
      );
      expect(
        AppTheme.dark(dyslexiaFont: true).textTheme.bodyMedium?.fontFamily,
        AppTheme.dyslexiaFontFamily,
      );
      expect(
        AppTheme.light().textTheme.bodyMedium?.fontFamily,
        isNot(AppTheme.dyslexiaFontFamily),
      );
    });

    test(
      'повышенный контраст меняет схему, обе темы используют useMaterial3',
      () {
        final normal = AppTheme.light();
        final contrast = AppTheme.light(highContrast: true);
        expect(contrast.useMaterial3, isTrue);
        expect(contrast.colorScheme.primary, isNot(normal.colorScheme.primary));
        expect(
          AppTheme.dark(highContrast: true).colorScheme.primary,
          isNot(AppTheme.dark().colorScheme.primary),
        );
      },
    );

    test('динамическая схема задаёт только акцент, поверхности брендовые', () {
      // До редизайна Nocturne (`REDESIGN-SPEC` §1.5, ADR-035 §3) схема из
      // `DynamicColorBuilder` подставлялась как есть. Теперь из её `primary`
      // строится только акцент (HCT: тон 40 в светлой теме, chroma ≤ 48),
      // поэтому проверка усилена: акцент следует за системой, а холст остаётся
      // порцеляновым.
      final ColorScheme dynamic = ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF4081),
        brightness: Brightness.light,
      );
      final ThemeData themed = AppTheme.light(scheme: dynamic);
      expect(themed.colorScheme.primary, isNot(NcColors.light().aurum));
      expect(themed.colorScheme.surface, NcColors.light().ink1);
      expect(themed.scaffoldBackgroundColor, NcColors.transparent);
    });
  });
}
