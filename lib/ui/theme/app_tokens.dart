import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// Адаптивная шкала интерфейса под 2K/4K (аудит v4, находки V8/V40).
///
/// Логические пиксели зависят от масштаба Windows: монитор 2560×1440 при
/// масштабе 150 % даёт окно 1707×940 логических px — по логическому размеру
/// его не отличить от FullHD. Поэтому размерная ступень считается по
/// **физическому** разрешению экрана (эффективная площадь), а не по логическим
/// пикселям:
///
/// * FullHD и меньше (эффективная площадь ≤ 1920×1080) — множитель 1,0;
/// * 2560×1440 — 1,24;
/// * 3840×2160 — 1,45 (верхняя граница шкалы).
///
/// Множитель применяется к шкале типографики и высотам контролов в
/// [AppTheme]; пользовательский масштаб текста (`TextScaler`) действует поверх.
/// В `flutter test` (`FLUTTER_TEST=true`) множитель всегда 1,0: тесты
/// проверяют вёрстку на эталонной шкале, а адаптивность подтверждается
/// измерениями живого приложения и юнит-тестом [factorForPhysical].
abstract final class AppAdaptive {
  /// Эталонная эффективная площадь (FullHD): ниже — множитель 1,0.
  static const double _referenceArea = 1920 * 1080;

  /// Максимальный множитель (4K).
  static const double maxFactor = 1.45;

  /// Отладочное переопределение (тесты виджетов и измерения).
  ///
  /// `null` — ступень считается по размеру экрана.
  static double? debugOverride;

  /// Идёт ли прогон `flutter test` (там адаптивность отключена).
  static bool get _isTestEnvironment =>
      Platform.environment['FLUTTER_TEST'] == 'true';

  /// Множитель для физического размера экрана.
  ///
  /// Площадь нормируется на FullHD, затем сжимается коэффициентом 0,72:
  /// 2K (площадь ×1,78) → 1,24; 4K (×4) → 1,45 (клампится).
  static double factorForPhysical(Size physicalSize) {
    final double width = physicalSize.width;
    final double height = physicalSize.height;
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return 1;
    }
    final double ratio = math.sqrt(width * height / _referenceArea);
    final double factor = 1 + (ratio - 1) * 0.72;
    return factor.clamp(1, maxFactor);
  }

  /// Множитель текущего окна приложения (по физическому размеру экрана).
  ///
  /// Используется корнем приложения для сборки темы: тема пересобирается при
  /// изменении размера окна/монитора.
  static double factorForCurrentWindow() {
    final double? override = debugOverride;
    if (override != null) return override;
    if (_isTestEnvironment) return 1;
    final views = WidgetsBinding.instance.platformDispatcher.views;
    if (views.isEmpty) return 1;
    return factorForPhysical(views.first.physicalSize);
  }

  /// Множитель текущего окна: учитывает DPI, поэтому зависит от монитора,
  /// а не от того, как приложение развёрнуто на экране.
  static double factorForContext(BuildContext context) {
    final double? override = debugOverride;
    if (override != null) return override;
    if (_isTestEnvironment) return 1;
    final MediaQueryData? media = MediaQuery.maybeOf(context);
    if (media == null) return 1;
    return factorForPhysical(media.size * media.devicePixelRatio);
  }
}

/// Роль оценки в общем тон-ряду панели оценок.
///
/// Тема не зависит от домена: `Rating` проецируется в роль на слое UI
/// (`review_toolbar.dart`), а цвета живут здесь.
enum RatingRole {
  /// «Не знаю» — ошибка/забывание.
  again,

  /// «Сложно» — нейтральный тон.
  hard,

  /// «Знаю» — успех.
  good,

  /// «Легко» — акцент.
  easy,
}

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
  //
  // Дизайн-система v3 (ADR-045): кобальтовый акцент на нейтральном графите.
  // Предыдущая палитра была построена вокруг indigo #3525CD и голубоватых
  // поверхностей #E5EEFF — на больших плоскостях она читалась как фиолетовая.
  // Теперь поверхности нейтральные (серый без синего сдвига), а цвет продукта
  // живёт только в акценте, состояниях и оценках.
  static const Color lightPrimary = Color(0xFF1E4FD8);
  static const Color lightOnPrimary = Color(0xFFFFFFFF);
  static const Color lightPrimaryContainer = Color(0xFFD8E2FF);
  static const Color lightOnPrimaryContainer = Color(0xFF0B2A78);
  static const Color lightPrimaryFixed = Color(0xFFDCE6FF);
  static const Color lightPrimaryFixedDim = Color(0xFFB3C6FF);
  static const Color lightOnPrimaryFixed = Color(0xFF001849);

  static const Color lightSecondary = Color(0xFF0F6B5C);
  static const Color lightOnSecondary = Color(0xFFFFFFFF);
  static const Color lightSecondaryContainer = Color(0xFFC9EFE6);
  static const Color lightOnSecondaryContainer = Color(0xFF063E36);
  static const Color lightSecondaryFixed = Color(0xFF9FF2DF);
  static const Color lightOnSecondaryFixed = Color(0xFF00201A);

  static const Color lightTertiary = Color(0xFF8A5300);
  static const Color lightOnTertiary = Color(0xFFFFFFFF);
  static const Color lightTertiaryContainer = Color(0xFFFFDF9E);
  static const Color lightOnTertiaryContainer = Color(0xFF2B1700);
  static const Color lightTertiaryFixed = Color(0xFFFFE9C2);
  static const Color lightOnTertiaryFixed = Color(0xFF2B1700);

  static const Color lightError = Color(0xFFB3261E);
  static const Color lightOnError = Color(0xFFFFFFFF);
  static const Color lightErrorContainer = Color(0xFFF9DEDC);
  static const Color lightOnErrorContainer = Color(0xFF410E0B);

  static const Color lightSurface = Color(0xFFF6F7F9);
  static const Color lightOnSurface = Color(0xFF14181F);
  static const Color lightOnSurfaceVariant = Color(0xFF4A5260);
  static const Color lightSurfaceDim = Color(0xFFD9DDE3);
  static const Color lightSurfaceBright = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLowest = Color(0xFFFFFFFF);
  static const Color lightSurfaceContainerLow = Color(0xFFF0F2F5);
  static const Color lightSurfaceContainer = Color(0xFFE9EBEF);
  static const Color lightSurfaceContainerHigh = Color(0xFFE1E4E9);
  static const Color lightSurfaceContainerHighest = Color(0xFFD8DCE2);

  static const Color lightOutline = Color(0xFF6E7683);
  static const Color lightOutlineVariant = Color(0xFFCDD2DA);
  static const Color lightInverseSurface = Color(0xFF242A33);
  static const Color lightOnInverseSurface = Color(0xFFF0F2F6);
  static const Color lightInversePrimary = Color(0xFF9DB7FF);
  static const Color lightSurfaceTint = Color(0xFF1E4FD8);

  // --- Тёмная палитра ------------------------------------------------------
  static const Color darkPrimary = Color(0xFF7FA5FF);
  static const Color darkOnPrimary = Color(0xFF06143A);
  // A6: контейнер затемнён, чтобы onPrimaryContainer давал ≥ 4,5:1.
  static const Color darkPrimaryContainer = Color(0xFF1E3A8A);
  static const Color darkOnPrimaryContainer = Color(0xFFD8E2FF);
  static const Color darkPrimaryFixed = Color(0xFF1E3A8A);
  static const Color darkPrimaryFixedDim = Color(0xFF2F55B8);
  static const Color darkOnPrimaryFixed = Color(0xFFD8E2FF);

  static const Color darkSecondary = Color(0xFF5CD3BC);
  static const Color darkOnSecondary = Color(0xFF00201A);
  static const Color darkSecondaryContainer = Color(0xFF0C4A42);
  static const Color darkOnSecondaryContainer = Color(0xFFC9EFE6);
  static const Color darkSecondaryFixed = Color(0xFF0C4A42);
  static const Color darkOnSecondaryFixed = Color(0xFFC9EFE6);

  static const Color darkTertiary = Color(0xFFF0B45A);
  static const Color darkOnTertiary = Color(0xFF2B1700);
  // A6: контейнер затемнён, чтобы onTertiaryContainer давал ≥ 4,5:1.
  static const Color darkTertiaryContainer = Color(0xFF6B4200);
  static const Color darkOnTertiaryContainer = Color(0xFFFFDF9E);
  static const Color darkTertiaryFixed = Color(0xFF6B4200);
  static const Color darkOnTertiaryFixed = Color(0xFFFFDF9E);

  static const Color darkError = Color(0xFFFFB4AB);
  static const Color darkOnError = Color(0xFF690005);
  static const Color darkErrorContainer = Color(0xFF93000A);
  static const Color darkOnErrorContainer = Color(0xFFFFDAD6);

  static const Color darkSurface = Color(0xFF0B0E13);
  static const Color darkOnSurface = Color(0xFFE7EAF0);
  static const Color darkOnSurfaceVariant = Color(0xFFB9C0CC);
  static const Color darkSurfaceDim = Color(0xFF3A414D);
  static const Color darkSurfaceBright = Color(0xFF1A2029);
  static const Color darkSurfaceContainerLowest = Color(0xFF10141A);
  static const Color darkSurfaceContainerLow = Color(0xFF151A22);
  static const Color darkSurfaceContainer = Color(0xFF1B2028);
  static const Color darkSurfaceContainerHigh = Color(0xFF222833);
  static const Color darkSurfaceContainerHighest = Color(0xFF2A3140);

  static const Color darkOutline = Color(0xFF9AA3B2);
  static const Color darkOutlineVariant = Color(0xFF2E3644);
  static const Color darkInverseSurface = Color(0xFFE7EAF0);
  static const Color darkOnInverseSurface = Color(0xFF11161D);
  static const Color darkInversePrimary = Color(0xFF1E4FD8);
  static const Color darkSurfaceTint = Color(0xFF7FA5FF);

  /// Цвет тени карточек в светлой теме (тёмная тема теней не рисует).
  static const Color shadow = Color(0xFF0A0F1A);

  /// Граница интерактивного контрола (кнопка, поле, чип, сегмент).
  ///
  /// Аудит `review_final` (F25): `outlineVariant` на белом даёт 1,71:1 —
  /// граница не читается. `outline` даёт 4,55:1 (светлая) и 6,6:1 (тёмная)
  /// и остаётся спокойной: это тонкая линия, а не рамка.
  static Color controlBorder(ColorScheme scheme) => scheme.outline;

  /// Фон кнопки оценки.
  ///
  /// Иерархия одного действия (ADR-045): «Знаю» — единственная залитая
  /// кнопка (главный ответ), «Легко» — спокойная тонировка secondary,
  /// «Затрудняюсь» — нейтральная поверхность, «Не знаю» — тихая тонировка
  /// error. Четыре кислотные плашки запрещены: карточка остаётся главным
  /// объектом экрана.
  static Color ratingSurface(ColorScheme scheme, RatingRole role) {
    final Color base = scheme.surfaceContainerLowest;
    return switch (role) {
      RatingRole.again => Color.alphaBlend(
        scheme.error.withValues(alpha: 0.08),
        base,
      ),
      RatingRole.hard => Color.alphaBlend(
        scheme.onSurface.withValues(alpha: 0.05),
        base,
      ),
      RatingRole.good => scheme.primary,
      RatingRole.easy => scheme.secondaryContainer,
    };
  }

  /// Цвет подписи оценки (парный к [ratingSurface], ≥ 4,5:1).
  static Color ratingForeground(ColorScheme scheme, RatingRole role) =>
      switch (role) {
        RatingRole.again => scheme.error,
        RatingRole.hard => scheme.onSurface,
        RatingRole.good => scheme.onPrimary,
        RatingRole.easy => scheme.onSecondaryContainer,
      };

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

  /// Фон карточки-оценки Again (тон-ряд, светло-розовая тонировка).
  static Color ratingAgainBackground(ColorScheme scheme) =>
      ratingSurface(scheme, RatingRole.again);

  /// Текст карточки-оценки Again.
  static Color ratingAgainForeground(ColorScheme scheme) =>
      ratingForeground(scheme, RatingRole.again);

  /// Фон карточки-оценки Hard (нейтральная тонировка).
  static Color ratingHardBackground(ColorScheme scheme) =>
      ratingSurface(scheme, RatingRole.hard);

  /// Текст карточки-оценки Hard.
  static Color ratingHardForeground(ColorScheme scheme) =>
      ratingForeground(scheme, RatingRole.hard);

  /// Фон карточки-оценки Good (спокойная мятная тонировка).
  static Color ratingGoodBackground(ColorScheme scheme) =>
      ratingSurface(scheme, RatingRole.good);

  /// Текст карточки-оценки Good.
  static Color ratingGoodForeground(ColorScheme scheme) =>
      ratingForeground(scheme, RatingRole.good);

  /// Фон карточки-оценки Easy (спокойная индиго-тонировка).
  static Color ratingEasyBackground(ColorScheme scheme) =>
      ratingSurface(scheme, RatingRole.easy);

  /// Текст карточки-оценки Easy.
  static Color ratingEasyForeground(ColorScheme scheme) =>
      ratingForeground(scheme, RatingRole.easy);

  // --- Обратная связь режимов «Тест», «Ввод», «Верно/Неверно» ---------------
  // Единые цвета результата ответа: раньше были литералами в трёх экранах.

  /// Фон статуса «к повторению»: акцент, а не тревога (аудит v4, V16).
  static Color dueBackground(ColorScheme scheme) => scheme.primaryFixed;

  /// Текст статуса «к повторению».
  static Color dueForeground(ColorScheme scheme) => scheme.onPrimaryFixed;

  /// Фон статуса «всё повторено».
  static Color readyBackground(ColorScheme scheme) => scheme.secondaryContainer;

  /// Текст статуса «всё повторено».
  static Color readyForeground(ColorScheme scheme) =>
      scheme.onSecondaryContainer;

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

  /// Ширина боковой панели с адаптивным множителем (240 → 298 → 312).
  ///
  /// Аудит `review_final` (F02/F18): при ×1,45 на 4K бренд и подписи навигации
  /// не помещались в фиксированные 240 px. Панель растёт вместе с типографикой,
  /// но не больше 320 px — иначе она съедает контент.
  static double sidebarWidthFor(BuildContext context) =>
      (sidebarWidth * AppAdaptive.factorForContext(context).clamp(1.0, 1.3))
          .clamp(sidebarWidth, 320.0);

  /// Высота верхней панели (макет: `h-14`).
  static const double headerHeight = 56;

  /// Высота верхней панели с адаптивным множителем (56 → 64 → 67).
  static double headerHeightFor(BuildContext context) =>
      (headerHeight * AppAdaptive.factorForContext(context).clamp(1.0, 1.2))
          .clamp(headerHeight, 72.0);

  /// Ширина контента на FullHD (эталон): одна колонка для всех страниц.
  static const double contentMaxWidth = 1280;

  /// Ширина формы генерации (эталон): узкая колонка полей ≤ 720.
  static const double formMaxWidth = 640;

  /// Ширина диалога (макет: `max-w-lg`).
  static const double dialogMaxWidth = 512;

  /// Высота основной кнопки (аудит v4, V38: единая шкала 44–48 px).
  static const double buttonHeight = 44;

  /// Высота крупной кнопки (главное действие страницы).
  static const double buttonHeightLarge = 48;

  /// Высота вложенной страницы-шапки (колода, генерация, конструктор).
  static const double subpageHeaderHeight = 64;

  /// Единственная адаптивная ширина контентной колонки (F09/F02).
  ///
  /// FullHD — 1280 (эталон макета); 2K — 1280 (окно 1707 лог. px, колонка
  /// 75 %); 4K — до 2600 (68 % окна). Все страницы и вложенные экраны берут
  /// ширину отсюда, поэтому кромка контента не прыгает при переходе.
  static double pageWidth(BuildContext context) {
    final double window = MediaQuery.sizeOf(context).width;
    if (window <= 0 || !window.isFinite) return contentMaxWidth;
    final double sidebar = window >= sidebarBreakpoint
        ? sidebarWidthFor(context)
        : 0;
    final double rail = window >= railBreakpoint && window < sidebarBreakpoint
        ? navRailWidth * AppAdaptive.factorForContext(context).clamp(1.0, 1.3)
        : 0;
    final double available = math.max(
      0,
      window -
          sidebar -
          rail -
          _horizontalPagePadding(window) * 2 -
          AppSpacing.xxl,
    );
    // 0,9 доступной ширины: колонка занимает основную часть площади, но
    // сохраняет поля по краям (воздух) и не превращается в «резинку».
    return (available * 0.9).clamp(contentMaxWidth, 2600.0);
  }

  /// Горизонтальные поля страницы: 24 на десктопе, 16 на узком.
  static double _horizontalPagePadding(double windowWidth) =>
      windowWidth >= sidebarBreakpoint ? AppSpacing.xl : AppSpacing.md;

  /// Адаптивная ширина детальной страницы — та же колонка, что и у страниц
  /// (F09: раньше 1120×factor давала прыжок 174 px).
  static double detailsWidth(BuildContext context) => pageWidth(context);

  /// Адаптивная ширина формы и мастеров: узкая колонка полей внутри страницы.
  ///
  /// F30/V4: поля 45–75 знаков. 640 базовых px при кегле 18–19 даёт ~60 знаков;
  /// адаптивный множитель сохраняет пропорцию на 2K/4K.
  static double formWidth(BuildContext context) {
    final double factor = AppAdaptive.factorForContext(context);
    // F30/V4: не шире 720 даже на 4K — иначе строки полей длиннее 75 знаков.
    return (formMaxWidth * factor.clamp(1.0, 1.45)).clamp(formMaxWidth, 720.0);
  }

  /// Ширина широкой формы: 640–920 px (генерация, провайдеры).
  ///
  /// Аудит 2.0 (P2-18): колонка генерации занимала 607 px из 1006 доступных,
  /// и заголовок рвался («ИИ» на отдельной строке). Широкая форма использует
  /// 82 % контентной ширины, но не выходит за 920 px (строки остаются
  /// читаемыми) и никогда не шире самой страницы (телефон — вся ширина).
  static double wideFormWidth(BuildContext context) {
    final double page = pageWidth(context);
    final double upper = math.max(AppSpacing.xs, math.min(920.0, page));
    final double lower = math.min(formMaxWidth, upper);
    return (page * 0.82).clamp(lower, upper);
  }

  /// Ширина карточки сессии: главный объект экрана на десктопе.
  ///
  /// Аудит v7 (G3/G19): раньше это был **фиксированный** максимум 960 — на 2K
  /// карточка занимала 54 % ширины окна, на 4K — 24 % (вертикальная полоса).
  /// Теперь ширина считается от окна ([studyCardWidth]); константа — только
  /// верхняя граница на очень широких экранах.
  static const double studyCardMaxWidth = 2600;

  /// Доля ширины окна, которую занимает карточка сессии (аудит v7, G3: ≥60 %).
  static const double studyCardWidthFactor = 0.72;

  /// Ширина карточки сессии для ширины окна [windowWidth].
  ///
  /// На узких экранах (< 900) карточка занимает всю доступную ширину, иначе —
  /// [studyCardWidthFactor] окна, но не меньше 60 % (требование гейта G3) и не
  /// больше [studyCardMaxWidth].
  static double studyCardWidth(double windowWidth) {
    if (windowWidth <= 0 || !windowWidth.isFinite) return studyCardMaxWidth;
    final double available = math.max(0, windowWidth - AppSpacing.xxl);
    if (windowWidth < 900) return available;
    final double preferred = math.min(
      windowWidth * studyCardWidthFactor,
      studyCardMaxWidth,
    );
    return math.max(preferred, math.min(available, windowWidth * 0.6));
  }

  /// Базовый предел ширины текстовой колонки карточки: 45–75 знаков (G7).
  ///
  /// Умножается на адаптивный множитель окна: на 2K/4K строки не растягиваются
  /// на всю ширину карточки, а остаются читаемой колонкой (~60 знаков).
  static const double studyTextColumnBase = 900;

  /// Высота кнопки оценки (G2: не меньше 56 лог. px на любом размере).
  static const double ratingButtonHeight = 56;

  /// Высота кнопки оценки в низком окне (один ряд, аудит v8 G10).
  ///
  /// Не меньше [ratingButtonHeight]: доступность не зависит от высоты окна,
  /// компактность даёт один ряд вместо сетки 2×2 и меньшие поля.
  static const double ratingButtonCompactHeight = 56;

  /// Предел адаптивного множителя для кнопки оценки (G2: 56–68 px).
  static const double ratingButtonMaxScale = 1.2;

  /// Множитель контролов оценки: 1,0 / 1,24 / 1,45 → клампится 1,0–1,2.
  static double controlScale(BuildContext context) =>
      AppAdaptive.factorForContext(context).clamp(1.0, ratingButtonMaxScale);

  /// Кегль подписи оценки (G2: не меньше 16 px при масштабе текста 90 %).
  static const double ratingLabelBase = 18;

  /// Высота главного действия карточки «Показать ответ» (G1: ≥56).
  static const double revealButtonHeight = 56;

  /// Ширина главного действия карточки: не полоса на всю карточку (F17).
  static const double revealButtonMaxWidth = 360;

  /// Минимальная высота карточки сессии, базовый уровень (× адаптивный множитель).
  ///
  /// Используется только как запасное значение вне `MediaQuery`
  /// (см. [studyCardMinHeightFor]); в интерфейсе карточка занимает не меньше
  /// 62 % рабочей области под шапкой (F01/V3).
  static const double studyCardMinHeight = 430;

  /// Минимальная высота карточки: 62 % рабочей области под шапкой.
  ///
  /// Аудит `review_final` (F01): высота считалась от кеглей (430×factor), и на
  /// 4K@100 % карточка была 29,6 % экрана. Теперь минимум задаёт рабочая
  /// область: 2K live — ~540 (60,3 % body), 4K — ~1298 (60 %).
  static double studyCardMinHeightFor(BuildContext context) {
    final MediaQueryData? media = MediaQuery.maybeOf(context);
    if (media == null) return studyCardMinHeight;
    final double bodyHeight = media.size.height - headerHeightFor(context);
    if (bodyHeight <= 0) return studyCardMinHeight;
    return math.min(bodyHeight, (bodyHeight * 0.62).clamp(240.0, 1600.0));
  }

  /// Порог «низкого окна» для компактной панели оценок в один ряд.
  static const double compactPanelHeight = 430;

  /// Размер иконки в навигации (шкала 16/20/24, аудит v4 V39).
  static const double navIcon = 20;

  /// Размер иконки в кнопках и строках.
  static const double icon = 20;

  /// Размер мелкой иконки.
  static const double iconSmall = 16;

  /// Крупная иконка панели/диалога.
  static const double iconLarge = 24;

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

  /// Ширина, до которой экран считается мобильным: узкий телефон.
  ///
  /// Owner-note (итерация «Фикс мобильного Empty State»): на телефоне
  /// горизонтальные блоки «иконка + текст + действие» обрушаются в колонку,
  /// а внутренние отступы панелей уменьшаются — иначе от 390 px остаётся
  /// меньше 280 px контента. Порог 600 px — телефоны 360/390/412 в портрете;
  /// планшет и десктоп сохраняют горизонтальный ряд.
  static const double mobileBreakpoint = 600;
}

/// Тени и границы поверхностей.
abstract final class AppShadows {
  /// Мягкая тень карточки (светлая тема): два слоя вместо одного плоского.
  ///
  /// Аудит `review_final` (F01/F25): тень 4 % на 6 px не отделяла белую
  /// карточку от поверхности — глубина достигается двумя слоями (контактный
  /// 0,05/4 px и рассеянный 0,06/16 px), без «тяжёлой» рамки.
  static List<BoxShadow> card(Brightness brightness) =>
      brightness == Brightness.dark
      ? const <BoxShadow>[]
      : <BoxShadow>[
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
          BoxShadow(
            color: AppColors.shadow.withValues(alpha: 0.06),
            blurRadius: 18,
            offset: const Offset(0, 6),
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
///
/// Аудит v4 (A1–A22): одна шкала вместо девяти случайных длительностей.
abstract final class AppDurations {
  /// Отклик на нажатие, hover, смена цвета (быстрая).
  static const Duration quick = Duration(milliseconds: 120);

  /// Смена состояния: цвет, фокус, раскрытие подсказки.
  static const Duration base = Duration(milliseconds: 200);

  /// Переход между карточками, появление панели, смена шага.
  static const Duration medium = Duration(milliseconds: 220);

  /// Переход между состояниями экрана, появление диалога.
  static const Duration slow = Duration(milliseconds: 280);

  /// Переворот карточки: 280 мс — в требованиях 280–350.
  static const Duration flip = Duration(milliseconds: 300);

  /// Длительность появления списка/панели экрана.
  static const Duration enter = Duration(milliseconds: 240);
}
