import 'package:material_ui/material_ui.dart';

/// Тема приложения на ролях Material 3 (SPEC A4.1).
///
/// База Material — официальный пакет `material_ui` (ADR-001). Виджеты
/// используют только токены темы (`colorScheme`, `textTheme`, …); сырые цвета
/// допустимы только в этом файле — как определение бренд-сида.
abstract final class AppTheme {
  /// Сид-цвет бренда CardFlow.
  static const Color seedColor = Color(0xFF4F6BED);

  /// Светлая тема.
  static ThemeData light() => _build(Brightness.light);

  /// Тёмная тема.
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    return ThemeData(colorScheme: scheme, useMaterial3: true);
  }
}
