import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';

/// Типографика CardFlow (ADR-038, аудит v4 V8/V40).
///
/// Шрифт — Inter (переменный, SIL OFL 1.1, `assets/fonts/Inter-Variable.ttf`).
/// Шкала — одна система уровней, а не набор случайных кеглей:
///
/// * `displayLarge` 38 — hero-числа, крупные экраны состояния;
/// * `displayMedium` 30 — заголовок страницы (адаптивно до 37–44 на 2K/4K);
/// * `displaySmall`/`headlineLarge` 26 — заголовок раздела/диалога;
/// * `headlineMedium` 22 — вопрос карточки по умолчанию;
/// * `titleLarge` 21 — заголовок панели;
/// * `titleMedium` 18 — имя колоды, подзаголовок;
/// * `titleSmall` 16 — компактный заголовок;
/// * `bodyLarge` 17 — основной текст (на FullHD не мельче 16);
/// * `bodyMedium` 15 — вторичный текст;
/// * `bodySmall` 14 — подписи;
/// * `labelLarge` 15 — текст кнопок;
/// * `labelMedium`/`labelSmall` 13 — надзаголовки и микроподписи.
///
/// Все размеры умножаются на [scale] — адаптивную ступень экрана
/// ([AppAdaptive]): на 2K шкала крупнее в 1,24 раза, на 4K — в 1,45.
/// Пользовательский масштаб текста (`TextScaler`) действует поверх темы.
///
/// Шрифт для дислексии перекрывает семейство (`ThemeData.textTheme.apply`), но
/// размеры/веса/интерлиньяж остаются те же — переключатель доступности не ломает
/// визуальную иерархию.
abstract final class AppTypography {
  /// Семейный шрифт интерфейса.
  static const String fontFamily = 'Inter';

  /// Цифры фиксированной ширины для счётчиков и KPI.
  static const List<FontFeature> tabularFigures = <FontFeature>[
    FontFeature.tabularFigures(),
  ];

  /// Кегль вопроса карточки сессии (лицевая сторона), базовый уровень.
  static const double reviewQuestionSize = 32;

  /// Кегль ответа карточки сессии (обратная сторона), базовый уровень.
  ///
  /// Аудит v4 (V4): ответ — главный текст оборота, он не может быть мельче
  /// повторённого вопроса. На 2K адаптивный множитель поднимает его до ~27.
  static const double reviewAnswerSize = 24;

  /// Кегль повторённого вопроса на обороте карточки.
  static const double reviewQuestionEchoSize = 16;

  /// Собирает [TextTheme] из шкалы.
  ///
  /// [scale] — адаптивный множитель размера экрана (1,0 / 1,24 / 1,45).
  static TextTheme textTheme({double scale = 1}) {
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
      fontSize: size * scale,
      height: height / size,
      fontWeight: weight,
      letterSpacing: letterSpacing * scale,
    );

    return TextTheme(
      displayLarge: style(38, 46, bold, letterSpacing: -0.9),
      displayMedium: style(30, 38, bold, letterSpacing: -0.6),
      displaySmall: style(26, 34, semibold, letterSpacing: -0.5),
      headlineLarge: style(26, 34, semibold, letterSpacing: -0.5),
      headlineMedium: style(22, 31, semibold, letterSpacing: -0.3),
      headlineSmall: style(19, 27, semibold, letterSpacing: -0.2),
      titleLarge: style(21, 29, semibold, letterSpacing: -0.2),
      titleMedium: style(18, 26, semibold, letterSpacing: -0.15),
      titleSmall: style(16, 23, semibold, letterSpacing: -0.1),
      bodyLarge: style(17, 25, regular),
      bodyMedium: style(15, 22, regular),
      bodySmall: style(14, 20, regular),
      labelLarge: style(15, 20, semibold, letterSpacing: 0.1),
      labelMedium: style(13, 18, semibold, letterSpacing: 0.5),
      labelSmall: style(13, 18, medium, letterSpacing: 0.2),
    );
  }

  /// Стиль крупной цифры KPI (30/38, tabular).
  static TextStyle kpi(BuildContext context) =>
      Theme.of(context).textTheme.displayMedium!
          .copyWith(fontFeatures: tabularFigures, fontWeight: FontWeight.w600);

  /// Крупная цифра KPI 38 px (статистика).
  static TextStyle kpiLarge(BuildContext context) =>
      kpi(context).copyWith(fontSize: 38 * _scaleOf(context));

  /// Микроподпись 13/18 (чипы версий, легенды, подписи в панели).
  ///
  /// Аудит v4 (V40): кеглей меньше 13 в продукте больше нет.
  static TextStyle caption(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelSmall!
          .copyWith(height: 1.35, letterSpacing: 0.2, color: color);

  /// Стиль мелкой подписи-надзаголовка (13/18, uppercase, 0.05em).
  static TextStyle overline(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.labelMedium!.copyWith(
        // Текст, а не граница: outline (#777587) на светлой поверхности
        // даёт 4.27:1 — ниже AA для мелких подписей.
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
      );

  /// Стиль цифр в строках/прогрессе (tabular).
  static TextStyle numeric(BuildContext context, {Color? color}) =>
      Theme.of(context).textTheme.bodyMedium!.copyWith(
        fontFeatures: tabularFigures,
        fontWeight: FontWeight.w600,
        color: color,
      );

  /// Адаптивный множитель текущего окна (тема уже учитывает его).
  static double _scaleOf(BuildContext context) =>
      AppAdaptive.factorForContext(context);
}
