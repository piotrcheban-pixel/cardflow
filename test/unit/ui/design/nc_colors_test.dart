import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/tokens/nc_colors.dart';

import '../../../helpers/wcag.dart';

/// Токены цвета Nocturne (REDESIGN-SPEC §1.2–1.4, ADR-035).
void main() {
  group('NcColors: тёмная тема Nocturne — значения §1.2', () {
    final NcColors c = NcColors.dark();

    test('холст и поверхности', () {
      expect(c.ink0, const Color(0xFF07080B));
      expect(c.ink1, const Color(0xFF0C0E13));
      expect(c.ink2, const Color(0xFF12151C));
      expect(c.ink3, const Color(0xFF191D26));
      expect(c.ink4, const Color(0xFF222734));
      expect(c.ink5, const Color(0xFF2C3242));
      expect(c.hairline, const Color(0x14FFFFFF));
      expect(c.hairlineStrong, const Color(0x24FFFFFF));
      expect(c.scrim, const Color(0x8F000000));
    });

    test('текст', () {
      expect(c.textPrimary, const Color(0xFFF2EEE7));
      expect(c.textSecondary, const Color(0xFFABA79F));
      expect(c.textTertiary, const Color(0xFF8A8780));
      expect(c.textDisabled, const Color(0xFF4C4B48));
      expect(c.textOnAccent, const Color(0xFF17120A));
    });

    test('акценты Aurum и Iris', () {
      expect(c.aurum, const Color(0xFFE4C88F));
      expect(c.aurumBright, const Color(0xFFF3DDB0));
      expect(c.aurumDeep, const Color(0xFFB8955A));
      expect(c.aurumSoft.a, closeTo(0.14, 0.01));
      expect(c.aurumGlow.a, closeTo(0.28, 0.01));
      expect(c.iris, const Color(0xFFA99BFF));
      expect(c.irisDeep, const Color(0xFF6E5CE6));
      expect(c.irisSoft.a, closeTo(0.14, 0.01));
      expect(c.irisGlow.a, closeTo(0.30, 0.01));
      expect(c.accent, c.aurum);
    });

    test('семантика и оценки FSRS', () {
      expect(c.ember, const Color(0xFFF0806B));
      expect(c.onEmber, const Color(0xFF1C0B07));
      expect(c.amber, const Color(0xFFE9B25E));
      expect(c.onAmber, const Color(0xFF1C1305));
      expect(c.jade, const Color(0xFF66D3A3));
      expect(c.onJade, const Color(0xFF04170F));
      expect(c.glacier, const Color(0xFF7FC4F5));
      expect(c.onGlacier, const Color(0xFF05131D));
      for (final Color soft in <Color>[
        c.emberSoft,
        c.amberSoft,
        c.jadeSoft,
        c.glacierSoft,
      ]) {
        expect(soft.a, closeTo(0.14, 0.01));
      }
    });

    test('тепловая карта — 5 ступеней золота', () {
      expect(c.heat, hasLength(5));
      expect(c.heat[0], const Color(0xFF14171E));
      expect(c.heat[1], const Color(0xFF2E2A20));
      expect(c.heat[2], const Color(0xFF5C4C2E));
      expect(c.heat[3], const Color(0xFF9C7E48));
      expect(c.heat[4], const Color(0xFFE4C88F));
    });

    test('цвета Aurora — низкая прозрачность', () {
      expect(c.auroraAurum.a, closeTo(0.09, 0.01));
      expect(c.auroraIris.a, closeTo(0.08, 0.01));
      expect(c.auroraGlacier.a, closeTo(0.05, 0.01));
    });
  });

  group('NcColors: светлая тема Porcelain — значения §1.3', () {
    final NcColors c = NcColors.light();

    test('холст, поверхности и текст', () {
      expect(c.ink0, const Color(0xFFF5F2EC));
      expect(c.ink1, const Color(0xFFFAF8F4));
      expect(c.ink2, const Color(0xFFFFFFFF));
      expect(c.ink3, const Color(0xFFFFFFFF));
      expect(c.ink4, const Color(0xFFEEEAE2));
      expect(c.ink5, const Color(0xFFE2DDD3));
      expect(c.textPrimary, const Color(0xFF16151A));
      expect(c.textSecondary, const Color(0xFF5C5952));
      expect(c.textTertiary, const Color(0xFF726E67));
      expect(c.hairline, const Color(0x14000000));
      expect(c.hairlineStrong, const Color(0x24000000));
    });

    test('акценты: значения затемнены до нормы AA на Porcelain', () {
      // §1.3 задаёт #8E6B2E / #C4472F / #2B76B0; на холсте #F5F2EC это
      // 4,38 / 4,38 / 4,35 : 1 — ниже порога §10 (4,5). Значения затемнены
      // минимально (ADR-035, «Отступления», п. 6) и проверены тестом контраста.
      expect(c.aurum, const Color(0xFF886529));
      expect(c.ember, const Color(0xFFBC4129));
      expect(c.glacier, const Color(0xFF276EA5));
      expect(c.iris, const Color(0xFF5B48D6));
      expect(c.amber, const Color(0xFF946210));
      expect(c.jade, const Color(0xFF1A7A53));
      expect(c.textOnAccent, const Color(0xFFFFFFFF));
    });

    test('тепловая карта светлой темы — своя шкала, 5 ступеней', () {
      expect(c.heat, hasLength(5));
      expect(c.heat.first, isNot(c.ink2));
      expect(
        relativeLuminance(c.heat.first),
        greaterThan(relativeLuminance(c.heat.last)),
      );
    });
  });

  group('NcColors: контраст WCAG §10', () {
    for (final MapEntry<String, NcColors> entry in <String, NcColors>{
      'dark': NcColors.dark(),
      'light': NcColors.light(),
      'dark-high-contrast': NcColors.dark(highContrast: true),
      'light-high-contrast': NcColors.light(highContrast: true),
    }.entries) {
      final String theme = entry.key;
      final NcColors c = entry.value;

      test('$theme: текст на поверхностях ≥ 4,5 : 1', () {
        final Map<String, Color> surfaces = <String, Color>{
          'ink0': c.ink0,
          'ink1': c.ink1,
          'ink2': c.ink2,
          'ink3': c.ink3,
        };
        for (final MapEntry<String, Color> surface in surfaces.entries) {
          for (final MapEntry<String, Color> text in <String, Color>{
            'textPrimary': c.textPrimary,
            'textSecondary': c.textSecondary,
            'textTertiary': c.textTertiary,
          }.entries) {
            expect(
              contrastRatio(text.value, surface.value),
              greaterThanOrEqualTo(4.5),
              reason:
                  '$theme: ${text.key} на ${surface.key} = '
                  '${contrastRatio(text.value, surface.value).toStringAsFixed(2)}',
            );
          }
        }
      });

      test('$theme: on-цвета на акцентах ≥ 4,5 : 1', () {
        final List<(String, Color, Color)> pairs = <(String, Color, Color)>[
          ('aurum', c.aurum, c.textOnAccent),
          ('ember', c.ember, c.onEmber),
          ('amber', c.amber, c.onAmber),
          ('jade', c.jade, c.onJade),
          ('glacier', c.glacier, c.onGlacier),
        ];
        for (final (String name, Color background, Color foreground) in pairs) {
          expect(
            contrastRatio(foreground, background),
            greaterThanOrEqualTo(4.5),
            reason: '$theme: текст на $name',
          );
        }
      });

      test('$theme: акцентный текст на холсте ≥ 4,5 : 1', () {
        for (final MapEntry<String, Color> accent in <String, Color>{
          'aurum': c.aurum,
          'iris': c.iris,
          'ember': c.ember,
          'amber': c.amber,
          'jade': c.jade,
          'glacier': c.glacier,
        }.entries) {
          expect(
            contrastRatio(accent.value, c.ink0),
            greaterThanOrEqualTo(4.5),
            reason:
                '$theme: ${accent.key} на ink0 = '
                '${contrastRatio(accent.value, c.ink0).toStringAsFixed(2)}',
          );
        }
      });
    }
  });

  group('NcColors: повышенный контраст §1.4', () {
    test('текст светлеет, hairline усиливается, акцент сдвигается', () {
      final NcColors normal = NcColors.dark();
      final NcColors contrast = NcColors.dark(highContrast: true);
      expect(contrast.textSecondary, const Color(0xFFD8D4CC));
      expect(contrast.textTertiary, const Color(0xFFB3AFA7));
      expect(contrast.hairline.a, closeTo(0.24, 0.02));
      expect(contrast.aurum, isNot(normal.aurum));
      expect(
        relativeLuminance(contrast.aurum),
        greaterThan(relativeLuminance(normal.aurum)),
        reason: 'В тёмной теме контрастный акцент светлее обычного',
      );
    });

    test('светлая тема: акцент темнеет', () {
      final NcColors normal = NcColors.light();
      final NcColors contrast = NcColors.light(highContrast: true);
      expect(contrast.aurum, isNot(normal.aurum));
      expect(
        relativeLuminance(contrast.aurum),
        lessThan(relativeLuminance(normal.aurum)),
      );
      expect(contrast.textSecondary, isNot(normal.textSecondary));
    });

    test('поверхности и семантика не меняются', () {
      final NcColors normal = NcColors.dark();
      final NcColors contrast = NcColors.dark(highContrast: true);
      expect(contrast.ink0, normal.ink0);
      expect(contrast.ink3, normal.ink3);
      expect(contrast.ember, normal.ember);
      expect(contrast.jade, normal.jade);
    });
  });

  group('NcColors: dynamic color меняет только акцент §1.4', () {
    const Color systemPrimary = Color(0xFFFF4081);

    test('тёмная тема: акцент из HCT (тон 80, chroma ≤ 48)', () {
      final NcColors dynamic = NcColors.dark(dynamicAccent: systemPrimary);
      expect(dynamic.ink0, const Color(0xFF07080B));
      expect(dynamic.ink2, const Color(0xFF12151C));
      expect(dynamic.iris, NcColors.dark().iris);
      expect(dynamic.jade, NcColors.dark().jade);
      expect(dynamic.aurum, isNot(NcColors.dark().aurum));

      final Hct hct = Hct.fromInt(dynamic.aurum.toARGB32());
      expect(hct.tone, closeTo(80, 1.0));
      expect(hct.chroma, lessThanOrEqualTo(48.0));
      expect(hct.hue, closeTo(Hct.fromInt(systemPrimary.toARGB32()).hue, 2.0));
    });

    test('светлая тема: тон 40', () {
      final NcColors dynamic = NcColors.light(dynamicAccent: systemPrimary);
      final Hct hct = Hct.fromInt(dynamic.aurum.toARGB32());
      expect(hct.tone, closeTo(40, 1.0));
      expect(hct.chroma, lessThanOrEqualTo(48.0));
      expect(dynamic.ink0, const Color(0xFFF5F2EC));
    });

    test('производные акцента следуют за цветом и сохраняют альфы', () {
      final NcColors dynamic = NcColors.dark(dynamicAccent: systemPrimary);
      expect(dynamic.aurumBright, isNot(NcColors.dark().aurumBright));
      expect(dynamic.aurumDeep, isNot(NcColors.dark().aurumDeep));
      expect(dynamic.aurumSoft.a, closeTo(0.14, 0.01));
      expect(dynamic.aurumGlow.a, closeTo(0.28, 0.01));
      expect(
        relativeLuminance(dynamic.aurumBright),
        greaterThan(relativeLuminance(dynamic.aurum)),
      );
      expect(
        relativeLuminance(dynamic.aurumDeep),
        lessThan(relativeLuminance(dynamic.aurum)),
      );
    });

    test('без dynamic-акцента значения брендовые', () {
      expect(NcColors.dark(dynamicAccent: null).aurum, NcColors.dark().aurum);
    });

    test('сильно перенасыщенный акцент обрезается по chroma', () {
      final NcColors dynamic = NcColors.dark(
        dynamicAccent: const Color(0xFF00FF00),
      );
      expect(
        Hct.fromInt(dynamic.aurum.toARGB32()).chroma,
        lessThanOrEqualTo(48.0),
      );
    });
  });
}
