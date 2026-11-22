import 'package:material_ui/material_ui.dart';

/// Дизайн-токены CardFlow (ADR-038).
///
/// Единственное место в `lib/ui/`, где живут «сырые» цвета, радиусы, отступы и
/// тени визуальной системы. Значения перенесены из эталонного макета
/// Gemini/Stitch v2 (`redesign/2/src/index.css`): светлая и тёмная палитры,
/// шкала типографики, скругления и тени.
///
/// Виджеты не используют числа/цвета напрямую — только [AppColors],
/// [AppRadii], [AppSpacing], [AppSizes] и тему (`colorScheme`, `textTheme`).
/// Это позволяет держать единый визуальный язык и переключать светлую/тёмную
/// тему без правок экранов.
abstract final class AppColors {
  // --- Светлая палитра -----------------------------------------------------
  static const Color lightPrimary = Color(0xFF3525CD);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFF4F46E5);
  static const Color lightOnPrimaryContainer = Color(0xFFDAD7FF);
  static const Color lightPrimaryFixed = Color(0xFFE2DFFF);
  static const Color lightPrimaryFixedDim = Color(0xFFC3C0FF);
  static const Color lightOnPrimaryFixed = Color(0xFF0F0069);

  static const Color lightSecondary = Color(0xFF006C49);
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  static const Color lightSecondaryContainer = Color(0xFF6CF8BB);
  static const Color lightOnSecondaryContainer = Color(0xFF00714D);
  static const Color lightSecondaryFixed = Color(0xFF6FFBBE);
  static const Color lightOnSecondaryFixed = Color(0xFF002113);

  static const Color lightTertiary = Color(0xFF95002B);
  static const Color lightOnTertiary = Color(0xFFFFFFFF);
  static const Color lightTertiaryContainer = Color(0xFFBF0F3C);
  static const Color lightOnTertiaryContainer = Color(0xFFFFD0D2);
  static const Color lightTertiaryFixed = Color(0xFFFFDADB);
  static const Color lightOnTertiaryFixed = Color(0xFF40000D);

  static const Color lightError = Color(0xFFBA1A1A);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFFFDAD6);
  static const Color lightOnErrorContainer = Color(0xFF93000A);

  static const Color lightSurface = Color(0xFFF8F9FF);
  static const Color lightOnSurface = Color(0xFF0B1C30);
  static const Color lightOnSurfaceVariant = Color(0xFF464555);
  static const Color lightSurfaceDim = Color(0xFFCBDBF5);
  static const Color lightSurfaceBright = Color(0xFFF8F9FF);
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFEFF4FF);
  static const Color lightSurfaceContainer = Color(0xFFE5EEFF);
  static const Color lightSurfaceContainerHigh = Color(0xFFDCE9FF);
  static const Color lightSurfaceContainerHighest = Color(0xFFD3E4FE);

  static const Color lightOutline = Color(0xFF777587);
  static const Color lightOutlineVariant = Color(0xFFC7C4D8);
  static const Color lightInverseSurface = Color(0xFF213145);
  static const Color lightOnInverseSurface = Color(0xFFEAF1FF);
  static const Color lightInversePrimary = Color(0xFFC3C0FF);
  static const Color lightSurfaceTint = Color(0xFF4D44E3);

  // --- Тёмная палитра ------------------------------------------------------
  static const Color darkPrimary = Color(0xFF818CF8);
  static const Color darkOnPrimary = Color(0xFF14122B);
  // A6: контейнер затемнён, чтобы onPrimaryContainer давал ≥ 4,5:1.
  static const Color darkPrimaryContainer = Color(0xFF4F46E5);
  static const Color darkOnPrimaryContainer = Color(0xFFEEF2FF);
  static const Color darkPrimaryFixed = Color(0xFF282463);
  static const Color darkPrimaryFixedDim = Color(0xFF4F46E5);
  static const Color darkOnPrimaryFixed = Color(0xFFE2DFFF);

  static const Color darkSecondary = Color(0xFF34D399);
  static const Color darkOnSecondary = Color(0xFF022C22);
  static const Color darkSecondaryContainer = Color(0xFF065F46);
  static const Color darkOnSecondaryContainer = Color(0xFFA7F3D0);
  static const Color darkSecondaryFixed = Color(0xFF064E3B);
  static const Color darkOnSecondaryFixed = Color(0xFFA7F3D0);

  static const Color darkTertiary = Color(0xFFFB7185);
  static const Color darkOnTertiary = Color(0xFF4C0519);
  // A6: контейнер затемнён, чтобы onTertiaryContainer давал ≥ 4,5:1.
  static const Color darkTertiaryContainer = Color(0xFF9F1239);
  static const Color darkOnTertiaryContainer = Color(0xFFFFE4E6);
  static const Color darkTertiaryFixed = Color(0xFF4C0519);
  static const Color darkOnTertiaryFixed = Color(0xFFFFDADB);

  static const Color darkError = Color(0xFFF87171);
  static const Color darkOnError = Color(0xFF450A0A);
  static const Color darkErrorContainer = Color(0xFF450A0A);
  static const Color darkOnErrorContainer = Color(0xFFFECACA);

  static const Color darkSurface = Color(0xFF090E1A);
  static const Color darkOnSurface = Color(0xFFF1F5F9);
  static const Color darkOnSurfaceVariant = Color(0xFFCBD5E1);
  static const Color darkSurfaceDim = Color(0xFF334155);
  static const Color darkSurfaceBright = Color(0xFF0F172A);
  static const Color darkSurfaceContainerLowest = Color(0xFF111827);
  static const Color darkSurfaceContainerLow = Color(0xFF172033);
  static const Color darkSurfaceContainer = Color(0xFF1E293B);
  static const Color darkSurfaceContainerHigh = Color(0xFF273549);
  static const Color darkSurfaceContainerHighest = Color(0xFF334155);

  static const Color darkOutline = Color(0xFF94A3B8);
  static const Color darkOutlineVariant = Color(0xFF293548);
  static const Color darkInverseSurface = Color(0xFFE2E8F0);
  static const Color darkOnInverseSurface = Color(0xFF0F172A);
  static const Color darkInversePrimary = Color(0xFF3525CD);
  static const Color darkSurfaceTint = Color(0xFF818CF8);

  /// Цвет тени карточек в светлой теме (тёмная тема теней не рисует).
  static const Color shadow = Color(0xFF0B1C30);

  /// Собирает светлую схему ролей Material 3 из палитры макета.
  static ColorScheme lightScheme() => ColorScheme(
    brightness: Brightness.light,
    primary: lightPrimary,
    onPrimary: lightOnPrimary,
    primaryContainer: lightPrimaryContainer,
    onPrimaryContainer: lightOnPrimaryContainer,
    secondary: lightSecondary,
    onSecondary: lightOnSecondary,
    secondaryContainer: lightSecondaryContainer,
    onSecondaryContainer: lightOnSecondaryContainer,
    tertiary: lightTertiary,
    onTertiary: lightOnTertiary,
    tertiaryContainer: lightTertiaryContainer,
    onTertiaryContainer: lightOnTertiaryContainer,
    error: lightError,
    onError: lightOnError,
    errorContainer: lightErrorContainer,
    onErrorContainer: lightOnErrorContainer,
    surface: lightSurface,
    onSurface: lightOnSurface,
    onSurfaceVariant: lightOnSurfaceVariant,
    outline: lightOutline,
    outlineVariant: lightOutlineVariant,
    surfaceDim: lightSurfaceDim,
    surfaceBright: lightSurfaceBright,
    surfaceContainerLowest: lightSurfaceContainerLowest,
    surfaceContainerLow: lightSurfaceContainerLow,
    surfaceContainer: lightSurfaceContainer,
    surfaceContainerHigh: lightSurfaceContainerHigh,
    surfaceContainerHighest: lightSurfaceContainerHighest,
    inverseSurface: lightInverseSurface,
    onInverseSurface: lightOnInverseSurface,
    inversePrimary: lightInversePrimary,
    surfaceTint: lightSurfaceTint,
    primaryFixed: lightPrimaryFixed,
    primaryFixedDim: lightPrimaryFixedDim,
    onPrimaryFixed: lightOnPrimaryFixed,
    secondaryFixed: lightSecondaryFixed,
    onSecondaryFixed: lightOnSecondaryFixed,
    tertiaryFixed: lightTertiaryFixed,
    onTertiaryFixed: lightOnTertiaryFixed,
  );

  /// Собирает тёмную схему ролей Material 3 из палитры макета.
  static ColorScheme darkScheme() => ColorScheme(
    brightness: Brightness.dark,
    primary: darkPrimary,
    onPrimary: darkOnPrimary,
    primaryContainer: darkPrimaryContainer,
    onPrimaryContainer: darkOnPrimaryContainer,
    secondary: darkSecondary,
    onSecondary: darkOnSecondary,
    secondaryContainer: darkSecondaryContainer,
    onSecondaryContainer: darkOnSecondaryContainer,
    tertiary: darkTertiary,
    onTertiary: darkOnTertiary,
    tertiaryContainer: darkTertiaryContainer,
    onTertiaryContainer: darkOnTertiaryContainer,
    error: darkError,
    onError: darkOnError,
    errorContainer: darkErrorContainer,
    onErrorContainer: darkOnErrorContainer,
    surface: darkSurface,
    onSurface: darkOnSurface,
    onSurfaceVariant: darkOnSurfaceVariant,
    outline: darkOutline,
    outlineVariant: darkOutlineVariant,
    surfaceDim: darkSurfaceDim,
    surfaceBright: darkSurfaceBright,
    surfaceContainerLowest: darkSurfaceContainerLowest,
    surfaceContainerLow: darkSurfaceContainerLow,
    surfaceContainer: darkSurfaceContainer,
    surfaceContainerHigh: darkSurfaceContainerHigh,
    surfaceContainerHighest: darkSurfaceContainerHighest,
    inverseSurface: darkInverseSurface,
    onInverseSurface: darkOnInverseSurface,
    inversePrimary: darkInversePrimary,
    surfaceTint: darkSurfaceTint,
    primaryFixed: darkPrimaryFixed,
    primaryFixedDim: darkPrimaryFixedDim,
    onPrimaryFixed: darkOnPrimaryFixed,
    secondaryFixed: darkSecondaryFixed,
    onSecondaryFixed: darkOnSecondaryFixed,
    tertiaryFixed: darkTertiaryFixed,
    onTertiaryFixed: darkOnTertiaryFixed,
  );

  /// Заливка основного действия в тёмной теме: indigo `#4F46E5`.
  ///
  /// В макете кнопка тоже `#4F46E5`; роль `primaryContainer` (#6366F1) для
  /// белой подписи даёт лишь 4.47:1 — ниже AA 4.5:1, поэтому действие
  /// использует отдельный, более тёмный токен (≥6:1).
  static const Color darkActionFill = Color(0xFF4F46E5);

  /// Цвет заливки основного действия: в тёмной теме — контрастный indigo,
  /// чтобы белая подпись проходила AA.
  static Color primaryAction(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? darkActionFill : scheme.primary;

  /// Цвет подписи основного действия (белый в обеих темах).
  static Color onPrimaryAction(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFFFFFF)
      : scheme.onPrimary;

  /// Фон карточки-оценки Again.
  static Color ratingAgainBackground(ColorScheme scheme) =>
      scheme.errorContainer;

  /// Текст карточки-оценки Again.
  static Color ratingAgainForeground(ColorScheme scheme) =>
      scheme.onErrorContainer;

  /// Фон карточки-оценки Hard.
  static Color ratingHardBackground(ColorScheme scheme) =>
      scheme.surfaceContainer;

  /// Текст карточки-оценки Hard.
  static Color ratingHardForeground(ColorScheme scheme) => scheme.onSurface;

  /// Фон карточки-оценки Good.
  static Color ratingGoodBackground(ColorScheme scheme) =>
      scheme.secondaryContainer;

  /// Текст карточки-оценки Good.
  static Color ratingGoodForeground(ColorScheme scheme) =>
      scheme.onSecondaryContainer;

  /// Фон карточки-оценки Easy.
  static Color ratingEasyBackground(ColorScheme scheme) => scheme.primaryFixed;

  /// Текст карточки-оценки Easy.
  static Color ratingEasyForeground(ColorScheme scheme) =>
      scheme.onPrimaryFixed;

  // --- Обратная связь режимов «Тест», «Ввод», «Верно/Неверно» ---------------
  // Единые цвета результата ответа: раньше были литералами в трёх экранах.

  /// Фон правильного ответа (режимы проверки ответа).
  static Color feedbackCorrectBackground(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF1B5E20)
      : const Color(0xFFE8F5E9);

  /// Текст правильного ответа.
  static Color feedbackCorrectForeground(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFC8E6C9)
      : const Color(0xFF1B5E20);

  /// Фон ответа «почти верно».
  static Color feedbackAlmostBackground(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFF5D4300)
      : const Color(0xFFFFF8E1);

  /// Текст ответа «почти верно».
  static Color feedbackAlmostForeground(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFFE082)
      : const Color(0xFF5D4300);

  /// Фон неверного ответа.
  static Color feedbackWrongBackground(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFB71C1C)
      : const Color(0xFFFFEBEE);

  /// Текст неверного ответа.
  static Color feedbackWrongForeground(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
      ? const Color(0xFFFFCDD2)
      : const Color(0xFFB71C1C);
}

/// Скругления системы.
abstract final class AppRadii {
  /// Мелкие элементы: чипы, иконки-квадраты.
  static const double xs = 6;

  /// Кнопки и поля ввода высотой 32–36.
  static const double sm = 8;

  /// Контролы и компактные кнопки.
  static const double control = 10;

  /// Поля ввода и вложенные панели.
  static const double input = 12;

  /// Карточки и панели.
  static const double card = 16;

  /// Крупные секции и модальные окна.
  static const double panel = 20;

  /// Pill-чипы, статусы, круглые кнопки.
  static const double pill = 999;

  /// [BorderRadius] карточки.
  static const BorderRadius cardRadius = BorderRadius.all(
    Radius.circular(card),
  );

  /// [BorderRadius] поля ввода.
  static const BorderRadius inputRadius = BorderRadius.all(
    Radius.circular(input),
  );

  /// [BorderRadius] pill-элемента.
  static const BorderRadius pillRadius = BorderRadius.all(
    Radius.circular(pill),
  );
}

/// Шкала отступов (4 px grid).
abstract final class AppSpacing {
  /// 4.
  static const double xxs = 4;

  /// 8.
  static const double xs = 8;

  /// 12.
  static const double sm = 12;

  /// 16.
  static const double md = 16;

  /// 20.
  static const double lg = 20;

  /// 24.
  static const double xl = 24;

  /// 32.
  static const double xxl = 32;

  /// 40.
  static const double xxxl = 40;

  /// 48.
  static const double huge = 48;
}

/// Размеры оболочки и контролов.
abstract final class AppSizes {
  /// Ширина постоянной боковой панели (макет: `w-60`).
  static const double sidebarWidth = 240;

  /// Высота верхней панели (макет: `h-14`).
  static const double headerHeight = 56;

  /// Ширина контента на широком экране (макет: `max-w-7xl`).
  static const double contentMaxWidth = 1280;

  /// Ширина формы генерации (макет: `max-w-4xl`).
  static const double formMaxWidth = 896;

  /// Ширина карточки сессии (было `max-w-[640px]` макета).
  ///
  /// Аудит 1.0 (находка D1): карточка — главный объект экрана, поэтому на ПК
  /// она занимает до 880 логических px и основную часть высоты области, а не
  /// 640×240 в верхнем углу.
  static const double studyCardMaxWidth = 880;

  /// Ширина диалога (макет: `max-w-lg`).
  static const double dialogMaxWidth = 512;

  /// Высота основной кнопки.
  static const double buttonHeight = 40;

  /// Высота крупной кнопки (главное действие страницы).
  static const double buttonHeightLarge = 44;

  /// Размер иконки в навигации.
  static const double navIcon = 20;

  /// Размер иконки в кнопках и строках.
  static const double icon = 18;

  /// Размер мелкой иконки.
  static const double iconSmall = 16;

  /// Минимальная высота интерактивной строки (доступность).
  static const double minTouchTarget = 44;

  /// Высота полосы прогресса.
  static const double progressHeight = 6;

  /// Толщина границы панели.
  static const double borderWidth = 1;

  /// Ширина боковой панели, начиная с которой она постоянная.
  static const double sidebarBreakpoint = 1024;

  /// Ширина компактной рейки навигации (только иконки).
  ///
  /// Аудит 1.0 (находка N6): на 640–1024 px постоянная панель не помещается,
  /// но и прятать разделы в бургер нельзя — путь до них становится длиннее.
  static const double navRailWidth = 72;

  /// Ширина, начиная с которой навигация — компактная рейка, а не `Drawer`.
  static const double railBreakpoint = 640;

  /// Ширина, начиная с которой сетка колод трёхколоночная.
  static const double gridBreakpoint = 1024;

  /// Ширина, начиная с которой сетка колод двухколоночная.
  static const double gridBreakpointTablet = 640;
}

/// Тени и границы поверхностей.
abstract final class AppShadows {
  /// Мягкая тень карточки (светлая тема).
  static List<BoxShadow> card(Brightness brightness) =>
      brightness == Brightness.dark
      ? const <BoxShadow>[]
      : <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ];

  /// Тень модального слоя.
  static List<BoxShadow> dialog(Brightness brightness) =>
      brightness == Brightness.dark
      ? const <BoxShadow>[]
      : <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.12),
            blurRadius: 32,
            offset: const Offset(0, 12),
          ),
        ];
}

/// Длительности коротких переходов (движение — `lib/ui/motion.dart`).
abstract final class AppDurations {
  /// Отклик на нажатие, hover, смена цвета.
  static const Duration quick = Duration(milliseconds: 120);

  /// Появление панели/диалога.
  static const Duration base = Duration(milliseconds: 180);

  /// Переход между состояниями экрана.
  static const Duration slow = Duration(milliseconds: 260);
}
