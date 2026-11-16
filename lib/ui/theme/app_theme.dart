import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/nc_theme.dart';
import 'package:cardflow/ui/design/tokens/nc_colors.dart';
import 'package:cardflow/ui/design/tokens/nc_depth.dart';
import 'package:cardflow/ui/design/tokens/nc_glass.dart';
import 'package:cardflow/ui/design/tokens/nc_radii.dart';
import 'package:cardflow/ui/design/tokens/nc_typography.dart';

/// Тема приложения Nocturne (REDESIGN-SPEC §1.5, §2.2, ADR-035).
///
/// База Material — официальный пакет `material_ui` (ADR-001): пока экраны не
/// переведены на компоненты `Nc*`, они выглядят «по-ночному» только за счёт
/// этой темы. Публичный API прежний (A6.6, ADR-019): [light]/[dark] принимают
/// динамическую схему платформы, повышенный контраст и шрифт для дислексии;
/// [seedColor] и [dyslexiaFontFamily] остаются (их читают тесты и хелперы).
///
/// Внутри: ручной `ColorScheme` (без `fromSeed`), `TextTheme` из токенов,
/// нулевые elevation, прозрачный фон под Aurora, темы компонентов и
/// `NcTheme` как `ThemeExtension`.
abstract final class AppTheme {
  /// Прежний сид-цвет бренда CardFlow (SPEC A4.1) — историческая точка для
  /// `M3EThemeData`/тестов. В Nocturne акцент берётся из [NcColors].
  static const Color seedColor = NcColors.legacySeed;

  /// Семейство шрифта для дислексии (assets/fonts, ADR-019 §6).
  static const String dyslexiaFontFamily = NcTypography.dyslexicFamily;

  /// Светлая тема «Porcelain».
  ///
  /// [scheme] — динамическая схема платформы (`DynamicColorBuilder`): из её
  /// `primary` строится **только акцент** (HCT, тон 40, chroma ≤ 48);
  /// поверхности, Iris и цвета оценок остаются брендовыми (ADR-035 §3).
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

  /// Тёмная тема «Nocturne» (основная).
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
    final bool isDark = brightness == Brightness.dark;
    final Color? dynamicAccent = scheme?.primary;
    final NcColors colors = isDark
        ? NcColors.dark(
            highContrast: highContrast,
            dynamicAccent: dynamicAccent,
          )
        : NcColors.light(
            highContrast: highContrast,
            dynamicAccent: dynamicAccent,
          );
    final NcTypography typography = dyslexiaFont
        ? NcTypography.standard.asDyslexic()
        : NcTypography.standard;
    final NcDepth depth = isDark ? NcDepth.dark : NcDepth.light;
    final NcGlassMaterials glass = isDark
        ? NcGlassMaterials.dark
        : NcGlassMaterials.light;
    final ColorScheme colorScheme = _colorScheme(colors);
    final TextTheme textTheme = typography.toTextTheme().apply(
      bodyColor: colors.textPrimary,
      displayColor: colors.textPrimary,
    );
    final NcTheme ncTheme = NcTheme(
      colors: colors,
      typography: typography,
      depth: depth,
      glass: glass,
      highContrast: highContrast,
      glassEnabled: !highContrast,
    );
    final BorderSide hairline = BorderSide(color: colors.hairline);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      // Фон даёт NcAmbientBackground в builder `MaterialApp.router` (§4.5).
      scaffoldBackgroundColor: NcColors.transparent,
      canvasColor: NcColors.transparent,
      extensions: <ThemeExtension<dynamic>>[ncTheme],
      appBarTheme: AppBarThemeData(
        backgroundColor: NcColors.transparent,
        surfaceTintColor: NcColors.transparent,
        foregroundColor: colors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: typography.titleM.copyWith(color: colors.textPrimary),
        iconTheme: IconThemeData(color: colors.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: colors.ink2,
        surfaceTintColor: NcColors.transparent,
        elevation: 0,
        shape: NcRadii.superellipse(NcRadii.l, side: hairline),
      ),
      listTileTheme: ListTileThemeData(
        textColor: colors.textPrimary,
        iconColor: colors.textSecondary,
        tileColor: NcColors.transparent,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colors.aurum,
          foregroundColor: colors.textOnAccent,
          disabledBackgroundColor: colors.ink4,
          disabledForegroundColor: colors.textDisabled,
          elevation: 0,
          textStyle: typography.labelL,
          minimumSize: const Size(NcRadii.xl, 56),
          shape: NcRadii.superellipse(NcRadii.pill),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colors.ink4,
          foregroundColor: colors.textPrimary,
          elevation: 0,
          textStyle: typography.labelL,
          shape: NcRadii.superellipse(NcRadii.pill),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colors.aurum,
          textStyle: typography.labelL,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: colors.ink2,
        hintStyle: typography.bodyM.copyWith(color: colors.textTertiary),
        labelStyle: typography.labelM.copyWith(color: colors.textSecondary),
        helperStyle: typography.bodyS.copyWith(color: colors.textTertiary),
        errorStyle: typography.bodyS.copyWith(color: colors.ember),
        // Material InputBorder не умеет superellipse: у NcTextField\n        // (этап 2) форма будет своя, здесь — радиусы Nocturne.\n        border: OutlineInputBorder(\n          borderRadius: NcRadii.borderRadius(NcRadii.s),\n          borderSide: hairline,\n        ),\n        enabledBorder: OutlineInputBorder(\n          borderRadius: NcRadii.borderRadius(NcRadii.s),\n          borderSide: hairline,\n        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: NcRadii.borderRadius(NcRadii.s),
          borderSide: BorderSide(color: colors.aurum, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: NcRadii.borderRadius(NcRadii.s),
          borderSide: BorderSide(color: colors.ember),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: NcRadii.borderRadius(NcRadii.s),
          borderSide: BorderSide(color: colors.ember, width: 1.5),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return colors.textPrimary;
          }
          return colors.textSecondary;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return colors.aurum;
          return colors.ink5;
        }),
        trackOutlineColor: const WidgetStatePropertyAll<Color>(
          NcColors.transparent,
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: colors.aurum,
        inactiveTrackColor: colors.ink5,
        thumbColor: colors.aurum,
        overlayColor: colors.aurumSoft,
        trackHeight: 6,
        valueIndicatorTextStyle: typography.monoM.copyWith(
          color: colors.textPrimary,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.ink4
                : colors.ink2,
          ),
          foregroundColor: WidgetStateProperty.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? colors.textPrimary
                : colors.textSecondary,
          ),
          side: WidgetStatePropertyAll<BorderSide>(hairline),
          textStyle: WidgetStatePropertyAll<TextStyle>(typography.labelM),
          elevation: const WidgetStatePropertyAll<double>(0),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: colors.ink4,
        selectedColor: colors.aurumSoft,
        disabledColor: colors.ink3,
        labelStyle: typography.labelM.copyWith(color: colors.textPrimary),
        side: hairline,
        shape: NcRadii.superellipse(NcRadii.pill),
        elevation: 0,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.ink1,
        modalBackgroundColor: colors.ink1,
        surfaceTintColor: NcColors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: colors.hairlineStrong,
        showDragHandle: true,
        shape: NcRadii.superellipse(NcRadii.xl),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.ink3,
        surfaceTintColor: NcColors.transparent,
        elevation: 0,
        titleTextStyle: typography.titleL.copyWith(color: colors.textPrimary),
        contentTextStyle: typography.bodyM.copyWith(
          color: colors.textSecondary,
        ),
        shape: NcRadii.superellipse(NcRadii.xl),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: colors.ink4,
        contentTextStyle: typography.bodyM.copyWith(color: colors.textPrimary),
        actionTextColor: colors.aurum,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: NcRadii.superellipse(NcRadii.s),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: colors.ink1,
        indicatorColor: colors.aurumSoft,
        surfaceTintColor: NcColors.transparent,
        elevation: 0,
        labelTextStyle: WidgetStatePropertyAll<TextStyle>(
          typography.labelM.copyWith(color: colors.textSecondary),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? colors.aurum
                : colors.textSecondary,
          ),
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: colors.ink1,
        indicatorColor: colors.aurumSoft,
        elevation: 0,
        selectedIconTheme: IconThemeData(color: colors.aurum),
        unselectedIconTheme: IconThemeData(color: colors.textSecondary),
        selectedLabelTextStyle: typography.labelM.copyWith(
          color: colors.textPrimary,
        ),
        unselectedLabelTextStyle: typography.labelM.copyWith(
          color: colors.textSecondary,
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: colors.ink3,
        surfaceTintColor: NcColors.transparent,
        elevation: 0,
        textStyle: typography.bodyM.copyWith(color: colors.textPrimary),
        shape: NcRadii.superellipse(NcRadii.m, side: hairline),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: colors.aurum,
        linearTrackColor: colors.ink5,
        circularTrackColor: colors.ink5,
      ),
      scrollbarTheme: ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll<Color>(colors.textDisabled),
        radius: const Radius.circular(NcRadii.xs),
        thickness: const WidgetStatePropertyAll<double>(6),
      ),
      dividerTheme: DividerThemeData(
        color: colors.hairline,
        thickness: 1,
        space: 1,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: colors.ink4,
          borderRadius: NcRadii.borderRadius(NcRadii.xs),
        ),
        textStyle: typography.bodyS.copyWith(color: colors.textPrimary),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: colors.aurum,
        selectionColor: colors.aurumSoft,
        selectionHandleColor: colors.aurum,
      ),
      iconTheme: IconThemeData(color: colors.textSecondary),
      splashColor: colors.aurumSoft,
      highlightColor: colors.aurumSoft,
    );
  }

  /// Ручной `ColorScheme` (без `fromSeed`) — проекция токенов §1.5.
  static ColorScheme _colorScheme(NcColors colors) => ColorScheme(
    brightness: colors.brightness,
    primary: colors.aurum,
    onPrimary: colors.textOnAccent,
    primaryContainer: colors.primaryContainer,
    onPrimaryContainer: colors.onPrimaryContainer,
    secondary: colors.iris,
    onSecondary: colors.onInverseSurface,
    secondaryContainer: colors.secondaryContainer,
    onSecondaryContainer: colors.onSecondaryContainer,
    tertiary: colors.jade,
    onTertiary: colors.onJade,
    tertiaryContainer: colors.tertiaryContainer,
    onTertiaryContainer: colors.onTertiaryContainer,
    error: colors.ember,
    onError: colors.onEmber,
    errorContainer: colors.errorContainer,
    onErrorContainer: colors.onErrorContainer,
    surface: colors.ink1,
    onSurface: colors.textPrimary,
    onSurfaceVariant: colors.textSecondary,
    surfaceContainerLowest: colors.ink0,
    surfaceContainerLow: colors.ink1,
    surfaceContainer: colors.ink2,
    surfaceContainerHigh: colors.ink3,
    surfaceContainerHighest: colors.ink4,
    surfaceDim: colors.ink0,
    surfaceBright: colors.ink4,
    outline: colors.hairlineStrong,
    outlineVariant: colors.hairline,
    inverseSurface: colors.inverseSurface,
    onInverseSurface: colors.onInverseSurface,
    inversePrimary: colors.inversePrimary,
    // §1.5: роль scrim — чистый чёрный (прозрачность применяет виджет);
    // токен NcColors.scrim (#000 56 %) используется оверлеями напрямую.
    scrim: NcColors.black,
    shadow: NcColors.black,
    // Без M3-тонирования поверхностей (§1.5).
    surfaceTint: NcColors.transparent,
  );
}
