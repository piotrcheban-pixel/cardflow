import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/theme/app_tokens.dart';
import 'package:cardflow/ui/theme/app_typography.dart';

/// Тема приложения CardFlow (SPEC A4.1, ADR-038).
///
/// Визуальная система собрана из токенов `lib/ui/theme/app_tokens.dart`:
/// светлая и тёмная палитры перенесены из эталонного макета Gemini/Stitch v2,
/// типографика — Inter (`app_typography.dart`), компоненты Material получают
/// единые радиусы, границы, отступы и состояния через `ThemeData`.
///
/// Здесь же заканчивается ADR-036 («тема — единственный файл»): брендовая
/// схема больше не выводится из сида, а задаётся явными ролями, чтобы совпасть
/// с макетом; `ColorScheme.fromSeed` используется только для режима
/// повышенного контраста и для динамического цвета платформы (A6.6, ADR-019).
abstract final class AppTheme {
  /// Сид-цвет бренда CardFlow: Indigo 600 (ADR-036, сохранён как fallback).
  static const Color seedColor = AppColors.lightPrimary;

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
    final ColorScheme resolved = _resolveScheme(
      brightness,
      scheme: scheme,
      highContrast: highContrast,
    );
    final TextTheme text = AppTypography.textTheme().apply(
      bodyColor: resolved.onSurface,
      displayColor: resolved.onSurface,
    );

    final ThemeData base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: resolved,
      textTheme: text,
      fontFamily: AppTypography.fontFamily,
      scaffoldBackgroundColor: resolved.surface,
      canvasColor: resolved.surface,
      dividerColor: resolved.outlineVariant,
      splashFactory: InkSparkle.splashFactory,
      visualDensity: VisualDensity.standard,
      // Находка A3: у клавиатурного фокуса видимый отклик. `focusColor` —
      // подсветка InkWell/ListTile, кольцо у панелей рисует `AppPanel`.
      focusColor: resolved.primary.withValues(alpha: 0.14),
      hoverColor: resolved.primary.withValues(alpha: 0.06),
    );

    final ThemeData themed = base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: resolved.surfaceContainerLowest,
        foregroundColor: resolved.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: AppSizes.headerHeight,
        centerTitle: false,
        titleTextStyle: text.titleMedium?.copyWith(color: resolved.onSurface),
        shape: Border(
          bottom: BorderSide(
            color: resolved.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
        iconTheme: IconThemeData(color: resolved.onSurfaceVariant),
        actionsIconTheme: IconThemeData(color: resolved.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        color: resolved.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.cardRadius,
          side: BorderSide(
            color: resolved.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primaryAction(resolved),
          foregroundColor: AppColors.onPrimaryAction(resolved),
          disabledBackgroundColor: resolved.surfaceContainerHigh,
          disabledForegroundColor: resolved.onSurfaceVariant.withValues(
            alpha: 0.6,
          ),
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          textStyle: text.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          ),
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: resolved.onSurface,
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          textStyle: text.labelLarge,
          side: BorderSide(
            color: resolved.outlineVariant,
            width: AppSizes.borderWidth,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: resolved.primary,
          minimumSize: const Size(0, AppSizes.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          textStyle: text.labelLarge,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: resolved.onSurfaceVariant,
          highlightColor: resolved.surfaceContainer,
          minimumSize: const Size(
            AppSizes.minTouchTarget,
            AppSizes.minTouchTarget,
          ),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: resolved.surfaceContainerLowest,
        isDense: false,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm + 4,
          vertical: AppSpacing.sm + 2,
        ),
        hintStyle: text.bodyLarge?.copyWith(color: resolved.outline),
        labelStyle: text.bodyMedium?.copyWith(color: resolved.onSurfaceVariant),
        helperStyle: text.bodySmall?.copyWith(color: resolved.outline),
        errorStyle: text.bodySmall?.copyWith(color: resolved.error),
        prefixIconColor: resolved.outline,
        suffixIconColor: resolved.outline,
        border: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: BorderSide(
            color: resolved.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: BorderSide(
            color: resolved.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: BorderSide(color: resolved.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: BorderSide(color: resolved.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: AppRadii.inputRadius,
          borderSide: BorderSide(color: resolved.error, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return resolved.onPrimary;
          }
          return resolved.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith<Color>((states) {
          if (states.contains(WidgetState.selected)) {
            return resolved.primary;
          }
          return resolved.surfaceContainerHigh;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith<Color>(
          (states) => states.contains(WidgetState.selected)
              ? Colors.transparent
              : resolved.outlineVariant,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: resolved.primary,
        inactiveTrackColor: resolved.surfaceContainerHigh,
        thumbColor: resolved.primary,
        overlayColor: resolved.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: resolved.primary,
        linearTrackColor: resolved.surfaceContainer,
        circularTrackColor: Colors.transparent,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: resolved.surfaceContainerLow,
        selectedColor: resolved.primary,
        disabledColor: resolved.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        side: BorderSide.none,
        labelStyle: text.labelLarge?.copyWith(color: resolved.onSurface),
        secondaryLabelStyle: text.labelLarge?.copyWith(
          color: resolved.onPrimary,
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: resolved.outlineVariant,
        thickness: AppSizes.borderWidth,
        space: AppSizes.borderWidth,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: resolved.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.panel)),
        ),
        titleTextStyle: text.titleLarge?.copyWith(fontSize: 20),
        contentTextStyle: text.bodyLarge?.copyWith(
          color: resolved.onSurfaceVariant,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: resolved.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalBarrierColor: resolved.inverseSurface.withValues(alpha: 0.45),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadii.panel),
          ),
        ),
        showDragHandle: true,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: resolved.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: resolved.onInverseSurface,
        ),
        actionTextColor: resolved.inversePrimary,
        elevation: 0,
        insetPadding: const EdgeInsets.all(AppSpacing.md),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.input)),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: resolved.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.input)),
          side: BorderSide(
            color: resolved.outlineVariant,
            width: AppSizes.borderWidth,
          ),
        ),
        textStyle: text.bodyMedium?.copyWith(color: resolved.onSurface),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: resolved.inverseSurface,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadii.xs)),
        ),
        textStyle: text.bodySmall?.copyWith(color: resolved.onInverseSurface),
        waitDuration: const Duration(milliseconds: 400),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: resolved.onSurfaceVariant,
        textColor: resolved.onSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.xxs,
        ),
        minVerticalPadding: AppSpacing.xs,
        titleTextStyle: text.bodyLarge?.copyWith(
          fontWeight: FontWeight.w500,
          color: resolved.onSurface,
        ),
        subtitleTextStyle: text.bodySmall?.copyWith(
          color: resolved.onSurfaceVariant,
        ),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: resolved.primary,
        selectionColor: resolved.primary.withValues(alpha: 0.2),
        selectionHandleColor: resolved.primary,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          textStyle: WidgetStatePropertyAll<TextStyle?>(text.labelLarge),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return resolved.primary;
            }
            return resolved.onSurfaceVariant;
          }),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return resolved.surfaceContainerLowest;
            }
            return resolved.surfaceContainerLow;
          }),
          side: WidgetStatePropertyAll<BorderSide>(
            BorderSide(color: resolved.outlineVariant),
          ),
          shape: const WidgetStatePropertyAll<OutlinedBorder>(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(AppRadii.control)),
            ),
          ),
          minimumSize: const WidgetStatePropertyAll<Size>(
            Size(0, AppSizes.buttonHeight),
          ),
          padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
            EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          ),
          elevation: const WidgetStatePropertyAll<double>(0),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: resolved.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: resolved.surfaceContainer,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll<TextStyle?>(
          text.labelSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: resolved.onSurfaceVariant,
          ),
        ),
      ),
    );

    if (!dyslexiaFont) return themed;
    return themed.copyWith(
      textTheme: themed.textTheme.apply(fontFamily: dyslexiaFontFamily),
      primaryTextTheme: themed.primaryTextTheme.apply(
        fontFamily: dyslexiaFontFamily,
      ),
    );
  }

  static ColorScheme _resolveScheme(
    Brightness brightness, {
    ColorScheme? scheme,
    required bool highContrast,
  }) {
    final ColorScheme brand =
        scheme ??
        (brightness == Brightness.light
            ? AppColors.lightScheme()
            : AppColors.darkScheme());
    if (!highContrast) return brand;
    // Повышенный контраст: сохраняем тон бренда, но повышаем контраст ролей
    // (M3 `contrastLevel: 1`) — иначе переключатель доступности перестал бы
    // влиять на схему (A6.6, ADR-019 §2).
    return ColorScheme.fromSeed(
      seedColor: brand.primary,
      brightness: brightness,
      contrastLevel: 1,
      dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
    );
  }
}
