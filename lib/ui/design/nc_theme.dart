import 'package:material_ui/material_ui.dart';

import 'tokens/nc_colors.dart';
import 'tokens/nc_depth.dart';
import 'tokens/nc_glass.dart';
import 'tokens/nc_radii.dart';
import 'tokens/nc_spacing.dart';
import 'tokens/nc_typography.dart';

/// Расширение темы Nocturne (`ThemeExtension`): цвета, типографика, глубина и
/// стекло как данные (REDESIGN-SPEC §13, ADR-035).
///
/// Виджеты получают токены через `NcTheme.of(context)`; Material-виджеты —
/// через `Theme.of(context).colorScheme`, который `AppTheme` проецирует из тех
/// же токенов (§1.5). Если расширения нет (тест с «голым» `MaterialApp`),
/// возвращается тёмная палитра Nocturne — виджет не падает.
@immutable
class NcTheme extends ThemeExtension<NcTheme> {
  const NcTheme({
    required this.colors,
    required this.typography,
    required this.depth,
    required this.glass,
    required this.highContrast,
    required this.glassEnabled,
  });

  /// Тёмная палитра по умолчанию (fallback, когда расширения нет).
  static final NcTheme fallback = NcTheme(
    colors: NcColors.dark(),
    typography: NcTypography.standard,
    depth: NcDepth.dark,
    glass: NcGlassMaterials.dark,
    highContrast: false,
    glassEnabled: true,
  );

  /// Палитра темы.
  final NcColors colors;

  /// Типографическая шкала (уже с учётом шрифта для дислексии).
  final NcTypography typography;

  /// Тени темы.
  final NcDepth depth;

  /// Материалы стекла темы.
  final NcGlassMaterials glass;

  /// Включён повышенный контраст (§1.4): стекло сплошное, Aurora выключена.
  final bool highContrast;

  /// Разрешено ли рисовать стекло (выключается при повышенном контрасте и в
  /// режиме «Стандартная анимация» на ровном фоне — §4.4).
  final bool glassEnabled;

  /// Тёмная ли тема.
  bool get isDark => colors.brightness == Brightness.dark;

  /// Отступы страницы по ширине окна.
  double pagePadding(double width) => NcSpace.pagePadding(width);

  /// Радиус монолита/листа.
  double get sheetRadius => NcRadii.xl;

  /// Расширение темы или `null`.
  static NcTheme? maybeOf(BuildContext context) =>
      Theme.of(context).extension<NcTheme>();

  /// Расширение темы; без него — [fallback] (тёмная палитра Nocturne).
  static NcTheme of(BuildContext context) => maybeOf(context) ?? fallback;

  @override
  NcTheme copyWith({
    NcColors? colors,
    NcTypography? typography,
    NcDepth? depth,
    NcGlassMaterials? glass,
    bool? highContrast,
    bool? glassEnabled,
  }) => NcTheme(
    colors: colors ?? this.colors,
    typography: typography ?? this.typography,
    depth: depth ?? this.depth,
    glass: glass ?? this.glass,
    highContrast: highContrast ?? this.highContrast,
    glassEnabled: glassEnabled ?? this.glassEnabled,
  );

  @override
  NcTheme lerp(ThemeExtension<NcTheme>? other, double t) {
    if (other is! NcTheme) return this;
    return NcTheme(
      colors: NcColors.lerp(colors, other.colors, t),
      typography: t < 0.5 ? typography : other.typography,
      depth: t < 0.5 ? depth : other.depth,
      glass: NcGlassMaterials.lerp(glass, other.glass, t),
      highContrast: t < 0.5 ? highContrast : other.highContrast,
      glassEnabled: t < 0.5 ? glassEnabled : other.glassEnabled,
    );
  }
}
