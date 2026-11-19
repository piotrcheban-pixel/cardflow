import 'package:material_ui/material_ui.dart';

/// Типографика CardFlow (ADR-038).
///
/// Шрифт — Inter (переменный, SIL OFL 1.1, `assets/fonts/Inter-Variable.ttf`);
/// шкала перенесена из макета Gemini/Stitch v2 (tailwind `fontSize`):
/// display 36/44, headline-lg 24/32, headline-md 20/28, body-md 15/22,
/// label-md 13/16, label-sm 11/14 + трекинг.
///
/// Шрифт для дислексии перекрывает семейство (`ThemeData.textTheme.apply`), но
/// размеры/веса/интерлиньяж остаются те же — переключатель доступности не ломает
/// визуальную иерархию.
abstract final class AppTypography {
  /// Семейство шрифта интерфейса.
  static const String fontFamily = 'Inter';

  /// Цифры фиксированной ширины для счётчиков и KPI.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// Собирает [TextTheme] из шкалы макета.
  static TextTheme textTheme() {
    const FontWeight regular = FontWeight.w400;
    const FontWeight medium = FontWeight.w500;
    const FontWeight semibold = FontWeight.w600;
    const FontWeight bold = FontWeight.w700;

    TextStyle style(
      double size,
      double height,
      FontWeight weight, {
      double letterSpacing = 0,
    }) => TextStyle(
      fontFamily: fontFamily,
      fontSize: size,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing,
    );

    return TextTheme(
      displayLarge: style(36, 44, bold, letterSpacing: -0.9),
      displayMedium: style(28, 34, bold, letterSpacing: -0.56),
      displaySmall: style(24, 32, semibold, letterSpacing: -0.48),
      headlineLarge: style(24, 32, semibold, letterSpacing: -0.48),
      headlineMedium: style(20, 28, semibold, letterSpacing: -0.3),
      headlineSmall: style(16, 24, semibold, letterSpacing: -0.16),
      titleLarge: style(18, 26, semibold, letterSpacing: -0.2),
      titleMedium: style(16, 24, semibold, letterSpacing: -0.16),
      titleSmall: style(14, 20, semibold, letterSpacing: -0.1),
      bodyLarge: style(15, 22, regular),
      bodyMedium: style(13, 18, regular),
      bodySmall: style(12, 16, regular),
      labelLarge: style(13, 16, semibold, letterSpacing: 0.1),
      labelMedium: style(11, 14, semibold, letterSpacing: 0.33),
      labelSmall: style(11, 14, medium, letterSpacing: 0.2),
    );
  }

  /// Стиль крупной цифры KPI (28/34, tabular).
  static TextStyle kpi(BuildContext context) =>
      Theme.of(context).textTheme.displayMedium!
          .copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w600);

  /// Стиль мелкой подписи-надзаголовка (11/14, uppercase, 0.03em).
  static TextStyle overline(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
        color: color ?? Theme.of(context).colorScheme.outline,
        letterSpacing: 0.66,
      );

  /// Стиль цифр в строках/прогрессе (tabular).
  static TextStyle numeric(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontFeatures: tabularFigures,
        fontWeight: FontWeight.w600,
        color: color,
      );
}
