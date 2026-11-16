import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/tokens/nc_typography.dart';

/// Типографическая шкала Nocturne (REDESIGN-SPEC §2, ADR-035).
void main() {
  group('NcTypography: семейства и роли §2.2', () {
    const NcTypography t = NcTypography.standard;

    test('семейства', () {
      expect(NcTypography.sansFamily, 'Onest');
      expect(NcTypography.serifFamily, 'Literata');
      expect(NcTypography.monoFamily, 'JetBrainsMono');
      expect(NcTypography.dyslexicFamily, 'OpenDyslexic');
    });

    test('Literata-роли: размеры, интерлиньяж, вес, трекинг', () {
      expect(t.displayXL.fontFamily, 'Literata');
      expect(t.displayXL.fontSize, 64);
      expect(t.displayXL.height, 1);
      expect(t.displayXL.fontWeight, FontWeight.w500);
      expect(t.displayXL.letterSpacing, closeTo(-1.28, 0.01));

      expect(t.displayL.fontSize, 44);
      expect(t.displayL.height, closeTo(48 / 44, 0.001));
      expect(t.displayL.letterSpacing, closeTo(-0.66, 0.01));

      expect(t.headline.fontSize, 30);
      expect(t.headline.height, closeTo(36 / 30, 0.001));
      expect(t.headline.letterSpacing, closeTo(-0.3, 0.01));

      expect(t.question.fontSize, 28);
      expect(t.question.height, closeTo(36 / 28, 0.001));
      expect(t.question.letterSpacing, closeTo(-0.14, 0.01));

      expect(t.answer.fontFamily, 'Literata');
      expect(t.answer.fontSize, 19);
      expect(t.answer.height, closeTo(30 / 19, 0.001));
      expect(t.answer.fontWeight, FontWeight.w400);
      expect(t.answer.letterSpacing, 0);
    });

    test('варианты Literata: opsz по роли и wght 450 у question', () {
      expect(_variation(t.displayXL, 'opsz'), 72);
      expect(_variation(t.displayL, 'opsz'), 48);
      expect(_variation(t.headline, 'opsz'), 32);
      expect(_variation(t.question, 'opsz'), 28);
      expect(_variation(t.answer, 'opsz'), 18);
      expect(_variation(t.question, 'wght'), 450);
      expect(_variation(t.headline, 'wght'), isNull);
    });

    test('Onest-роли интерфейса', () {
      expect(t.titleL.fontFamily, 'Onest');
      expect(t.titleL.fontSize, 20);
      expect(t.titleL.height, closeTo(26 / 20, 0.001));
      expect(t.titleL.fontWeight, FontWeight.w600);
      expect(t.titleL.letterSpacing, closeTo(-0.1, 0.01));

      expect(t.titleM.fontSize, 17);
      expect(t.titleM.height, closeTo(22 / 17, 0.001));
      expect(t.titleM.letterSpacing, closeTo(-0.034, 0.001));

      expect(t.titleS.fontSize, 15);
      expect(t.titleS.letterSpacing, 0);

      expect(t.bodyL.fontSize, 16);
      expect(t.bodyL.height, closeTo(24 / 16, 0.001));
      expect(t.bodyL.fontWeight, FontWeight.w400);

      expect(t.bodyM.fontSize, 14);
      expect(t.bodyM.height, closeTo(20 / 14, 0.001));

      expect(t.bodyS.fontSize, 13);
      expect(t.bodyS.height, closeTo(18 / 13, 0.001));
      expect(t.bodyS.letterSpacing, closeTo(0.013, 0.001));

      expect(t.labelL.fontSize, 15);
      expect(t.labelL.fontWeight, FontWeight.w600);
      expect(t.labelL.letterSpacing, closeTo(0.03, 0.001));

      expect(t.labelM.fontSize, 13);
      expect(t.labelM.height, closeTo(16 / 13, 0.001));
      expect(t.labelM.letterSpacing, closeTo(0.039, 0.001));
    });

    test('overline: 650 через FontVariation, трекинг +8 %', () {
      expect(t.overline.fontFamily, 'Onest');
      expect(t.overline.fontSize, 11);
      expect(t.overline.height, closeTo(14 / 11, 0.001));
      expect(t.overline.letterSpacing, closeTo(0.88, 0.01));
      expect(_variation(t.overline, 'wght'), 650);
    });

    test('моноширинные роли: JetBrains Mono и табличные цифры', () {
      expect(t.monoM.fontFamily, 'JetBrainsMono');
      expect(t.monoM.fontSize, 12);
      expect(t.monoM.height, closeTo(16 / 12, 0.001));
      expect(t.monoM.fontWeight, FontWeight.w500);
      expect(
        t.monoM.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      expect(t.monoL.fontSize, 22);
      expect(t.monoL.height, closeTo(26 / 22, 0.001));
      expect(t.monoL.letterSpacing, closeTo(-0.22, 0.01));
      expect(
        t.monoL.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );
    });
  });

  group('NcTypography: проекция в TextTheme', () {
    final TextTheme theme = NcTypography.standard.toTextTheme();

    test('роли, которые проверяют существующие тесты и экраны', () {
      expect(theme.displayLarge?.fontFamily, 'Literata');
      expect(theme.displayLarge?.fontSize, 64);
      expect(theme.displayMedium?.fontSize, 44);
      expect(theme.headlineMedium?.fontSize, 30);
      expect(theme.headlineSmall?.fontSize, 28);

      expect(theme.bodyLarge?.fontFamily, 'Onest');
      expect(theme.bodyLarge?.fontSize, 16);
      expect(theme.bodyMedium?.fontFamily, 'Onest');
      expect(theme.bodyMedium?.fontSize, 14);
      expect(theme.bodySmall?.fontSize, 13);

      expect(theme.titleLarge?.fontSize, 20);
      expect(theme.titleMedium?.fontSize, 17);
      expect(theme.titleSmall?.fontSize, 15);

      expect(theme.labelLarge?.fontSize, 15);
      expect(theme.labelMedium?.fontSize, 13);
      expect(theme.labelSmall?.fontSize, 11);
      expect(theme.labelSmall?.letterSpacing, closeTo(0.88, 0.01));
    });

    test('все 15 слотов TextTheme заполнены шрифтами Nocturne', () {
      final List<TextStyle?> styles = <TextStyle?>[
        theme.displayLarge,
        theme.displayMedium,
        theme.displaySmall,
        theme.headlineLarge,
        theme.headlineMedium,
        theme.headlineSmall,
        theme.titleLarge,
        theme.titleMedium,
        theme.titleSmall,
        theme.bodyLarge,
        theme.bodyMedium,
        theme.bodySmall,
        theme.labelLarge,
        theme.labelMedium,
        theme.labelSmall,
      ];
      for (final TextStyle? style in styles) {
        expect(style?.fontFamily, isNotNull);
        expect(
          <String>['Onest', 'Literata'].contains(style?.fontFamily),
          isTrue,
          reason: 'Слот TextTheme должен быть на Onest или Literata',
        );
      }
    });
  });

  group('NcTypography: шрифт для дислексии (§2.1, ADR-019)', () {
    final NcTypography dyslexic = NcTypography.standard.asDyslexic();
    final TextTheme theme = dyslexic.toTextTheme();

    test('все роли заменяются на OpenDyslexic', () {
      for (final TextStyle style in dyslexic.roles) {
        expect(style.fontFamily, 'OpenDyslexic');
      }
      expect(theme.bodyLarge?.fontFamily, 'OpenDyslexic');
      expect(theme.displayLarge?.fontFamily, 'OpenDyslexic');
      expect(theme.labelSmall?.fontFamily, 'OpenDyslexic');
      expect(dyslexic.monoM.fontFamily, 'OpenDyslexic');
    });

    test('интерлиньяж +10 %, трекинг 0, вариации сняты', () {
      expect(
        dyslexic.bodyL.height,
        closeTo(NcTypography.standard.bodyL.height! * 1.1, 0.001),
      );
      expect(
        dyslexic.displayXL.height,
        closeTo(NcTypography.standard.displayXL.height! * 1.1, 0.001),
      );
      for (final TextStyle style in dyslexic.roles) {
        expect(style.letterSpacing, 0);
        expect(style.fontVariations ?? const <FontVariation>[], isEmpty);
      }
    });

    test('размеры и насыщенность сохраняются', () {
      expect(dyslexic.bodyL.fontSize, NcTypography.standard.bodyL.fontSize);
      expect(
        dyslexic.question.fontWeight,
        NcTypography.standard.question.fontWeight,
      );
    });

    test('исходная шкала не мутируется', () {
      expect(NcTypography.standard.bodyL.fontFamily, 'Onest');
      expect(
        NcTypography.standard.toTextTheme().bodyLarge?.fontFamily,
        'Onest',
      );
    });
  });
}

double? _variation(TextStyle style, String axis) {
  for (final FontVariation variation
      in style.fontVariations ?? const <FontVariation>[]) {
    if (variation.axis == axis) return variation.value;
  }
  return null;
}
