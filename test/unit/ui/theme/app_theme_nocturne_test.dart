import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/nc_theme.dart';
import 'package:cardflow/ui/design/tokens/nc_colors.dart';
import 'package:cardflow/ui/design/tokens/nc_glass.dart';
import 'package:cardflow/ui/design/tokens/nc_radii.dart';
import 'package:cardflow/ui/design/tokens/nc_typography.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../../helpers/wcag.dart';

/// Тема Nocturne: роли `ColorScheme` §1.5, токены в `NcTheme`, настройки A6.6
/// и применение шрифтов (REDESIGN-SPEC §1.5, §2.2, ADR-035).
void main() {
  group('AppTheme: публичный API прежний', () {
    test('light/dark и константы', () {
      expect(AppTheme.light().brightness, Brightness.light);
      expect(AppTheme.dark().brightness, Brightness.dark);
      expect(AppTheme.seedColor, NcColors.legacySeed);
      expect(AppTheme.dyslexiaFontFamily, 'OpenDyslexic');
      expect(AppTheme.dark().useMaterial3, isTrue);
    });
  });

  group('AppTheme: ColorScheme из токенов §1.5', () {
    final ColorScheme dark = AppTheme.dark().colorScheme;
    final NcColors darkColors = NcColors.dark();
    final ColorScheme light = AppTheme.light().colorScheme;
    final NcColors lightColors = NcColors.light();

    test('тёмная тема: роли', () {
      expect(dark.primary, darkColors.aurum);
      expect(dark.onPrimary, darkColors.textOnAccent);
      expect(dark.primaryContainer, const Color(0xFF2A2519));
      expect(dark.onPrimaryContainer, darkColors.aurumBright);
      expect(dark.secondary, darkColors.iris);
      expect(dark.secondaryContainer, const Color(0xFF221D3D));
      expect(dark.tertiary, darkColors.jade);
      expect(dark.error, darkColors.ember);
      expect(dark.surface, darkColors.ink1);
      expect(dark.onSurface, darkColors.textPrimary);
      expect(dark.onSurfaceVariant, darkColors.textSecondary);
      expect(dark.surfaceContainerLowest, darkColors.ink0);
      expect(dark.surfaceContainerLow, darkColors.ink1);
      expect(dark.surfaceContainer, darkColors.ink2);
      expect(dark.surfaceContainerHigh, darkColors.ink3);
      expect(dark.surfaceContainerHighest, darkColors.ink4);
      expect(dark.outline, darkColors.hairlineStrong);
      expect(dark.outlineVariant, darkColors.hairline);
      expect(dark.inverseSurface, const Color(0xFFF2EEE7));
      expect(dark.onInverseSurface, const Color(0xFF0C0E13));
      expect(dark.scrim, NcColors.black);
      expect(dark.shadow, NcColors.black);
      expect(dark.surfaceTint, NcColors.transparent);
    });

    test('светлая тема: роли из Porcelain', () {
      expect(light.primary, lightColors.aurum);
      expect(light.onPrimary, lightColors.textOnAccent);
      expect(light.surface, lightColors.ink1);
      expect(light.onSurface, lightColors.textPrimary);
      expect(light.secondary, lightColors.iris);
      expect(light.surfaceTint, NcColors.transparent);
      expect(light.brightness, Brightness.light);
    });

    test('контраст primary/onPrimary по WCAG', () {
      for (final ColorScheme scheme in <ColorScheme>[dark, light]) {
        expect(
          contrastRatio(scheme.onPrimary, scheme.primary),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          contrastRatio(scheme.onSurface, scheme.surface),
          greaterThanOrEqualTo(4.5),
        );
      }
    });
  });

  group('AppTheme: фон, elevation и форма', () {
    final ThemeData dark = AppTheme.dark();

    test('scaffold прозрачный — фон рисует Aurora', () {
      expect(dark.scaffoldBackgroundColor, NcColors.transparent);
      expect(dark.canvasColor, NcColors.transparent);
    });

    test('elevation 0 у компонентов, surfaceTint прозрачный', () {
      expect(dark.cardTheme.elevation, 0);
      expect(dark.cardTheme.surfaceTintColor, NcColors.transparent);
      expect(dark.appBarTheme.elevation, 0);
      expect(dark.appBarTheme.scrolledUnderElevation, 0);
      expect(dark.dialogTheme.elevation, 0);
      expect(dark.bottomSheetTheme.elevation, 0);
      expect(dark.popupMenuTheme.elevation, 0);
      expect(dark.snackBarTheme.elevation, 0);
      expect(
        dark.filledButtonTheme.style?.elevation?.resolve(<WidgetState>{}) ?? 0,
        0,
      );
    });

    test('формы — superellipse с радиусами Nocturne', () {
      final ShapeBorder cardShape = dark.cardTheme.shape!;
      expect(cardShape, isA<RoundedSuperellipseBorder>());
      expect(
        (cardShape as RoundedSuperellipseBorder).borderRadius,
        NcRadii.borderRadius(NcRadii.l),
      );
    });

    test('темы компонентов заполнены токенами', () {
      expect(dark.dividerTheme.color, NcColors.dark().hairline);
      expect(dark.sliderTheme.activeTrackColor, NcColors.dark().aurum);
      expect(dark.sliderTheme.inactiveTrackColor, NcColors.dark().ink5);
      expect(dark.progressIndicatorTheme.color, NcColors.dark().aurum);
      expect(dark.textSelectionTheme.cursorColor, NcColors.dark().aurum);
      expect(dark.navigationBarTheme.indicatorColor, NcColors.dark().aurumSoft);
    });
  });

  group('AppTheme: NcTheme как ThemeExtension', () {
    test('присутствует в обеих темах и содержит токены', () {
      final NcTheme dark = AppTheme.dark().extension<NcTheme>()!;
      final NcTheme light = AppTheme.light().extension<NcTheme>()!;
      expect(dark.colors, NcColors.dark());
      expect(light.colors, NcColors.light());
      expect(dark.typography.displayXL.fontFamily, 'Literata');
      expect(dark.isDark, isTrue);
      expect(light.isDark, isFalse);
      expect(dark.glassEnabled, isTrue);
    });
  });

  group('AppTheme: шрифты §2.2', () {
    test('TextTheme строится из токенов', () {
      final TextTheme theme = AppTheme.dark().textTheme;
      expect(theme.bodyLarge?.fontFamily, 'Onest');
      expect(theme.bodyLarge?.fontSize, 16);
      expect(theme.bodyMedium?.fontFamily, 'Onest');
      expect(theme.displayLarge?.fontFamily, 'Literata');
      expect(theme.displayLarge?.fontSize, 64);
      expect(theme.headlineSmall?.fontSize, 28);
      expect(theme.labelSmall?.letterSpacing, closeTo(0.88, 0.01));
      // Цвет текста из токенов, иначе Material-текст был бы чёрным.
      expect(theme.bodyLarge?.color, NcColors.dark().textPrimary);
      expect(theme.displayLarge?.color, NcColors.dark().textPrimary);
    });

    test('dyslexiaFont заменяет все роли, включая Literata и моно', () {
      final ThemeData theme = AppTheme.dark(dyslexiaFont: true);
      final TextTheme text = theme.textTheme;
      for (final TextStyle? style in <TextStyle?>[
        text.displayLarge,
        text.displayMedium,
        text.headlineMedium,
        text.headlineSmall,
        text.bodyLarge,
        text.bodyMedium,
        text.bodySmall,
        text.titleLarge,
        text.labelSmall,
      ]) {
        expect(style?.fontFamily, AppTheme.dyslexiaFontFamily);
      }
      final NcTheme nc = theme.extension<NcTheme>()!;
      for (final TextStyle style in nc.typography.roles) {
        expect(style.fontFamily, AppTheme.dyslexiaFontFamily);
      }
      expect(
        nc.typography.bodyL.height,
        closeTo(NcTypography.standard.bodyL.height! * 1.1, 0.001),
      );
    });
  });

  group('AppTheme: повышенный контраст §1.4', () {
    test('акцент сдвигается, стекло выключается', () {
      final ThemeData normal = AppTheme.dark();
      final ThemeData contrast = AppTheme.dark(highContrast: true);
      expect(contrast.colorScheme.primary, isNot(normal.colorScheme.primary));
      expect(contrast.extension<NcTheme>()!.highContrast, isTrue);
      expect(contrast.extension<NcTheme>()!.glassEnabled, isFalse);
      expect(normal.extension<NcTheme>()!.glassEnabled, isTrue);
      final NcGlassMaterial solid = NcGlassMaterials.solid(NcColors.dark());
      expect(solid.isSolid, isTrue);
    });
  });

  group('AppTheme: dynamic color меняет только акцент (ADR-035 §3)', () {
    final ColorScheme dynamic = ColorScheme.fromSeed(
      seedColor: const Color(0xFFFF4081),
      brightness: Brightness.dark,
    );

    test('акцент отличается от брендового, поверхности — нет', () {
      final ThemeData theme = AppTheme.dark(scheme: dynamic);
      expect(theme.colorScheme.primary, isNot(NcColors.dark().aurum));
      expect(theme.extension<NcTheme>()!.colors.ink0, const Color(0xFF07080B));
      expect(theme.extension<NcTheme>()!.colors.ink2, NcColors.dark().ink2);
      expect(theme.extension<NcTheme>()!.colors.iris, NcColors.dark().iris);
      expect(theme.extension<NcTheme>()!.colors.jade, NcColors.dark().jade);
    });

    test('акцент — HCT с тоном 80 и chroma ≤ 48', () {
      final ThemeData theme = AppTheme.dark(scheme: dynamic);
      final Hct hct = Hct.fromInt(theme.colorScheme.primary.toARGB32());
      expect(hct.tone, closeTo(80, 1.0));
      expect(hct.chroma, lessThanOrEqualTo(48.0));
    });

    test('светлая тема: тон 40', () {
      final ColorScheme lightDynamic = ColorScheme.fromSeed(
        seedColor: const Color(0xFFFF4081),
        brightness: Brightness.light,
      );
      final ThemeData theme = AppTheme.light(scheme: lightDynamic);
      final Hct hct = Hct.fromInt(theme.colorScheme.primary.toARGB32());
      expect(hct.tone, closeTo(40, 1.0));
      expect(hct.chroma, lessThanOrEqualTo(48.0));
    });

    test('без схемы акцент брендовый', () {
      expect(AppTheme.dark().colorScheme.primary, NcColors.dark().aurum);
    });
  });
}
