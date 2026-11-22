import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_contrast.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Контраст палитры (SPEC A4.1, аудит A6): инвариант AA держит guard-тест.
///
/// Все пары «текст/фон» и «нетекст/фон», которые встречаются в интерфейсе,
/// проверяются одной формулой WCAG 2.1 из `app_contrast.dart`. Новая роль,
/// добавленная в палитру, обязана попасть сюда — иначе регрессию контраста
/// (как в A1/D15: 1,36:1) поймает только аудитор.
void main() {
  final List<({String name, ColorScheme scheme})> schemes =
      <({String name, ColorScheme scheme})>[
        (name: 'light', scheme: AppColors.lightScheme()),
        (name: 'dark', scheme: AppColors.darkScheme()),
      ];

  for (final ({String name, ColorScheme scheme}) entry in schemes) {
    group('контраст ${entry.name}', () {
      final ColorScheme scheme = entry.scheme;
      final Map<String, (Color, Color)> pairs = <String, (Color, Color)>{
        'onSurface/surface': (scheme.onSurface, scheme.surface),
        'onSurface/surfaceContainerLowest': (
          scheme.onSurface,
          scheme.surfaceContainerLowest,
        ),
        'onSurfaceVariant/surface': (scheme.onSurfaceVariant, scheme.surface),
        'onSurfaceVariant/surfaceContainerLowest': (
          scheme.onSurfaceVariant,
          scheme.surfaceContainerLowest,
        ),
        'onPrimary/primary': (scheme.onPrimary, scheme.primary),
        'onSecondary/secondary': (scheme.onSecondary, scheme.secondary),
        'onTertiary/tertiary': (scheme.onTertiary, scheme.tertiary),
        'onError/error': (scheme.onError, scheme.error),
        'onErrorContainer/errorContainer': (
          scheme.onErrorContainer,
          scheme.errorContainer,
        ),
        'onTertiaryContainer/tertiaryContainer': (
          scheme.onTertiaryContainer,
          scheme.tertiaryContainer,
        ),
        'onPrimaryContainer/primaryContainer': (
          scheme.onPrimaryContainer,
          scheme.primaryContainer,
        ),
        'onSecondaryContainer/secondaryContainer': (
          scheme.onSecondaryContainer,
          scheme.secondaryContainer,
        ),
        'onSurface/surfaceContainerHigh': (
          scheme.onSurface,
          scheme.surfaceContainerHigh,
        ),
      };

      for (final MapEntry<String, (Color, Color)> pair in pairs.entries) {
        test(pair.key, () {
          final double ratio = contrastRatio(pair.value.$1, pair.value.$2);
          expect(
            ratio,
            greaterThanOrEqualTo(4.5),
            reason:
                '${entry.name}: ${pair.key} = ${ratio.toStringAsFixed(2)}:1',
          );
        });
      }

      test('кнопки оценок: текст на фоне', () {
        final List<(String, Color, Color)> ratingPairs =
            <(String, Color, Color)>[
              (
                'again',
                AppColors.ratingAgainForeground(scheme),
                AppColors.ratingAgainBackground(scheme),
              ),
              (
                'hard',
                AppColors.ratingHardForeground(scheme),
                AppColors.ratingHardBackground(scheme),
              ),
              (
                'good',
                AppColors.ratingGoodForeground(scheme),
                AppColors.ratingGoodBackground(scheme),
              ),
              (
                'easy',
                AppColors.ratingEasyForeground(scheme),
                AppColors.ratingEasyBackground(scheme),
              ),
            ];
        for (final (String name, Color foreground, Color background)
            in ratingPairs) {
          expect(
            contrastRatio(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '${entry.name}: оценка «$name»',
          );
        }
      });

      test('нетекстовые границы: ≥ 3:1', () {
        expect(
          contrastRatio(scheme.outline, scheme.surface),
          greaterThanOrEqualTo(3),
        );
      });

      // Баннер ошибки генерации (A1/D15): ссылка и текст на errorContainer.
      test('баннер ошибки: ссылка ≥ 4,5:1', () {
        expect(
          contrastRatio(scheme.onErrorContainer, scheme.errorContainer),
          greaterThanOrEqualTo(4.5),
        );
      });
    });
  }
}
