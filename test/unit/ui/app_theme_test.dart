import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Контраст по WCAG 2.1 (relative luminance).
double _contrast(Color a, Color b) {
  final double la = a.computeLuminance();
  final double lb = b.computeLuminance();
  final double hi = la > lb ? la : lb;
  final double lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

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

  group('ADR-038: контраст ключевых пар ролей', () {
    test('основной текст и действия проходят WCAG AA (>= 4.5:1)', () {
      final ColorScheme light = AppTheme.light().colorScheme;
      final ColorScheme dark = AppTheme.dark().colorScheme;
      final Map<String, (Color, Color)> pairs = <String, (Color, Color)>{
        'light primary/onPrimary': (light.primary, light.onPrimary),
        'dark action/onAction': (
          AppColors.primaryAction(dark),
          AppColors.onPrimaryAction(dark),
        ),
        'light onSurface/surface': (light.onSurface, light.surface),
        'dark onSurface/surface': (dark.onSurface, dark.surface),
        'light onSurfaceVariant/surface': (
          light.onSurfaceVariant,
          light.surface,
        ),
        'dark onSurfaceVariant/surface': (dark.onSurfaceVariant, dark.surface),
        'light again': (
          AppColors.ratingAgainForeground(light),
          AppColors.ratingAgainBackground(light),
        ),
        'dark again': (
          AppColors.ratingAgainForeground(dark),
          AppColors.ratingAgainBackground(dark),
        ),
        'light good': (
          AppColors.ratingGoodForeground(light),
          AppColors.ratingGoodBackground(light),
        ),
        'dark good': (
          AppColors.ratingGoodForeground(dark),
          AppColors.ratingGoodBackground(dark),
        ),
        'light easy': (
          AppColors.ratingEasyForeground(light),
          AppColors.ratingEasyBackground(light),
        ),
        'dark easy': (
          AppColors.ratingEasyForeground(dark),
          AppColors.ratingEasyBackground(dark),
        ),
      };
      for (final MapEntry<String, (Color, Color)> pair in pairs.entries) {
        expect(
          _contrast(pair.value.$1, pair.value.$2),
          greaterThanOrEqualTo(4.5),
          reason: 'Контраст пары «${pair.key}» ниже AA 4.5:1',
        );
      }
    });
  });
}
