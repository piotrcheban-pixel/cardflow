import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/nc_theme.dart';
import 'package:cardflow/ui/design/tokens/nc_colors.dart';
import 'package:cardflow/ui/design/tokens/nc_depth.dart';
import 'package:cardflow/ui/design/tokens/nc_glass.dart';
import 'package:cardflow/ui/design/tokens/nc_typography.dart';

/// `NcTheme` как `ThemeExtension` (REDESIGN-SPEC §13).
void main() {
  group('NcTheme: доступ из контекста', () {
    testWidgets('of() находит расширение темы', (tester) async {
      final NcTheme expected = NcTheme(
        colors: NcColors.dark(highContrast: true),
        typography: NcTypography.standard.asDyslexic(),
        depth: NcDepth.dark,
        glass: NcGlassMaterials.dark,
        highContrast: true,
        glassEnabled: false,
      );
      late NcTheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(extensions: <ThemeExtension<dynamic>>[expected]),
          home: Builder(
            builder: (BuildContext context) {
              resolved = NcTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.highContrast, isTrue);
      expect(resolved.glassEnabled, isFalse);
      expect(resolved.typography.bodyL.fontFamily, 'OpenDyslexic');
      expect(NcTheme.maybeOf(tester.element(find.byType(SizedBox))), isNotNull);
    });

    testWidgets('без расширения — тёмный fallback, виджет не падает', (
      tester,
    ) async {
      late NcTheme resolved;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (BuildContext context) {
              resolved = NcTheme.of(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(resolved.isDark, isTrue);
      expect(resolved.colors.ink0, const Color(0xFF07080B));
      expect(NcTheme.fallback.typography.displayXL.fontFamily, isLiterata());
    });
  });

  group('NcTheme: copyWith, lerp и флаги', () {
    test('copyWith меняет только указанные поля', () {
      final NcTheme base = NcTheme.fallback;
      final NcTheme changed = base.copyWith(highContrast: true);
      expect(changed.highContrast, isTrue);
      expect(changed.colors, base.colors);
      expect(changed.glass, base.glass);
    });

    test('lerp переключает флаги на середине и смешивает цвета', () {
      final NcTheme from = NcTheme.fallback;
      final NcTheme to = from.copyWith(
        colors: NcColors.light(),
        highContrast: true,
        glassEnabled: false,
      );
      final NcTheme mid = from.lerp(to, 0.5);
      expect(
        mid.colors.ink0,
        Color.lerp(from.colors.ink0, to.colors.ink0, 0.5),
      );
      expect(mid.highContrast, isTrue);
      expect(mid.glassEnabled, isFalse);
      expect(mid.colors.brightness, Brightness.light);
    });

    test('lerp с чужим расширением возвращает себя', () {
      final NcTheme base = NcTheme.fallback;
      expect(base.lerp(null, 0.5), base);
    });

    test('радиусы и отступы доступны из темы', () {
      final NcTheme theme = NcTheme.fallback;
      expect(theme.sheetRadius, 30);
      expect(theme.pagePadding(390), 20);
      expect(theme.pagePadding(1440), 40);
    });
  });

  group('NcColors.lerp', () {
    test('смешивает цвета и берёт brightness по половине', () {
      final NcColors a = NcColors.dark();
      final NcColors b = NcColors.light();
      final NcColors mid = NcColors.lerp(a, b, 0.5);
      expect(mid.ink0, Color.lerp(a.ink0, b.ink0, 0.5));
      expect(mid.aurum, Color.lerp(a.aurum, b.aurum, 0.5));
      expect(mid.heat, hasLength(5));
      expect(mid.brightness, Brightness.light);
      expect(NcColors.lerp(a, b, 0.25).brightness, Brightness.dark);
    });
  });

  group('NcColors: контейнеры и инверсия §1.5', () {
    test('тёмная тема', () {
      final NcColors c = NcColors.dark();
      expect(c.primaryContainer, const Color(0xFF2A2519));
      expect(c.secondaryContainer, const Color(0xFF221D3D));
      expect(c.tertiaryContainer, const Color(0xFF12291F));
      expect(c.errorContainer, const Color(0xFF2E1611));
      expect(c.inverseSurface, const Color(0xFFF2EEE7));
      expect(c.onInverseSurface, const Color(0xFF0C0E13));
    });

    test('светлая тема: свои контейнеры', () {
      final NcColors c = NcColors.light();
      expect(c.primaryContainer, isNot(NcColors.dark().primaryContainer));
      expect(c.inverseSurface, const Color(0xFF16151A));
      expect(c.onInverseSurface, const Color(0xFFF5F2EC));
    });

    test('dynamic color перекрашивает primaryContainer', () {
      final NcColors dynamic = NcColors.dark(
        dynamicAccent: const Color(0xFFFF4081),
      );
      expect(dynamic.primaryContainer, isNot(NcColors.dark().primaryContainer));
    });
  });
}

/// Матчер «семейство Literata» (читаемее, чем сравнение строк в тесте).
Matcher isLiterata() => equals('Literata');
