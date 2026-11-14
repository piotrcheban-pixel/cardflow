import 'package:material_ui/material_ui.dart';

/// Тема приложения на ролях Material 3 (SPEC A4.1).
///
/// База Material — официальный пакет `material_ui` (ADR-001). Виджеты
/// используют только токены темы (`colorScheme`, `textTheme`, …); сырые цвета
/// допустимы только в этом файле — как определение бренд-сида.
///
/// С итерации 7 (A6.6, ADR-019 §2) тема учитывает пользовательские настройки:
/// динамическую схему платформы, повышенный контраст и шрифт для дислексии.
abstract final class AppTheme {
  /// Сид-цвет бренда CardFlow.
  static const Color seedColor = Color(0xFF4F6BED);

  /// Семейство шрифта для дислексии (assets/fonts, ADR-019 §6).
  static const String dyslexiaFontFamily = 'OpenDyslexic';

  /// Светлая тема.
  static ThemeData light({
    ColorScheme? scheme,
    bool highContrast = false,
    bool dyslexiaFont = false,
  }) => _build(
    Brightness.light,
    scheme: scheme,
    highContrast: highContrast,
    dyslexiaFont: dyslexiaFont,
  );

  /// Тёмная тема.
  static ThemeData dark({
    ColorScheme? scheme,
    bool highContrast = false,
    bool dyslexiaFont = false,
  }) => _build(
    Brightness.dark,
    scheme: scheme,
    highContrast: highContrast,
    dyslexiaFont: dyslexiaFont,
  );

  static ThemeData _build(
    Brightness brightness, {
    ColorScheme? scheme,
    required bool highContrast,
    required bool dyslexiaFont,
  }) {
    final ColorScheme resolved =
        scheme ??
        ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: brightness,
          contrastLevel: highContrast ? 1 : 0,
        );
    final ThemeData base = ThemeData(colorScheme: resolved, useMaterial3: true);
    if (!dyslexiaFont) return base;
    return base.copyWith(
      textTheme: base.textTheme.apply(fontFamily: dyslexiaFontFamily),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: dyslexiaFontFamily,
      ),
    );
  }
}
