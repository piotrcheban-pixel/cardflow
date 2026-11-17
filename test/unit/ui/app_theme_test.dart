import 'package:flutter_test/flutter_test.dart';

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

    test('динамическая схема подставляется как есть', () {
      final scheme = AppTheme.light().colorScheme;
      final themed = AppTheme.light(scheme: scheme);
      expect(themed.colorScheme.primary, scheme.primary);
    });
  });
}
