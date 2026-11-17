import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/design.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/shell/app_shell.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import 'pump_app.dart';

/// Стенд экрана Nocturne для тестов этапа 3 (REDESIGN-SPEC §9).
///
/// Повторяет продовую обвязку `lib/ui/app.dart`: тема `AppTheme`, фон Aurora,
/// `NcMotionScope`/`NcHapticsScope` и проекция `M3ETheme`; отличие — тема
/// задаётся параметром (для golden и проверки светлой), а `textScaler`
/// приходит напрямую (настройка `AppSettings.textScale` клампится до 1,4,
/// §10 требует проверки 2,0).
@immutable
class NcScreenConfig {
  /// Создаёт конфигурацию стенда.
  const NcScreenConfig({
    this.brightness = Brightness.dark,
    this.highContrast = false,
    this.textScale = 1,
    this.size = const Size(390, 740),
    this.motion = NcMotionPreference.expressive,
    this.reduceMotion = true,
    this.hapticsEnabled = true,
  });

  /// Тёмная (Nocturne) или светлая (Porcelain) тема.
  final Brightness brightness;

  /// Повышенный контраст (§1.4).
  final bool highContrast;

  /// Масштаб текста (§10: до 2,0).
  final double textScale;

  /// Размер окна теста в логических px.
  final Size size;

  /// Режим движения (§6.4).
  final NcMotionPreference motion;

  /// Системное «уменьшить движение»; по умолчанию `true` — снимки и
  /// `pumpAndSettle` детерминированы.
  final bool reduceMotion;

  /// Включён ли тактильный отклик.
  final bool hapticsEnabled;

  /// Копия с заменой полей.
  NcScreenConfig copyWith({
    Brightness? brightness,
    bool? highContrast,
    double? textScale,
    Size? size,
    NcMotionPreference? motion,
    bool? reduceMotion,
    bool? hapticsEnabled,
  }) => NcScreenConfig(
    brightness: brightness ?? this.brightness,
    highContrast: highContrast ?? this.highContrast,
    textScale: textScale ?? this.textScale,
    size: size ?? this.size,
    motion: motion ?? this.motion,
    reduceMotion: reduceMotion ?? this.reduceMotion,
    hapticsEnabled: hapticsEnabled ?? this.hapticsEnabled,
  );
}

/// Приложение-стенд вокруг экрана: продовая обвязка `CardFlowApp` без
/// `DynamicColorBuilder` (golden не зависят от системы).
///
/// [home] и [router] взаимоисключающие: экран без навигации или приложение
/// с `GoRouter` (для оболочки и переходов).
Widget ncScreenApp({
  Widget? home,
  GoRouter? router,
  List<Override> overrides = const <Override>[],
  NcScreenConfig config = const NcScreenConfig(),
  NcHaptics? haptics,
}) {
  assert(home != null || router != null, 'Нужен home или router');
  final ThemeData theme = config.brightness == Brightness.dark
      ? AppTheme.dark(highContrast: config.highContrast)
      : AppTheme.light(highContrast: config.highContrast);
  final NcHaptics actualHaptics =
      haptics ?? NcHaptics(enabled: config.hapticsEnabled);
  Widget wrap(BuildContext context, Widget? child) {
    final M3EThemeData data = M3EThemeData.fromMaterial(Theme.of(context));
    return NcMotionScope(
      motion: NcMotion.resolve(
        preference: config.motion,
        disableAnimations: config.reduceMotion,
      ),
      child: NcHapticsScope(
        haptics: actualHaptics,
        child: NcAmbientBackground(
          child: M3ETheme(
            data: data,
            child: MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(config.textScale)),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
      ),
    );
  }

  final Widget app = router == null
      ? MaterialApp(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: ruLocalizationDelegates,
          theme: theme,
          builder: wrap,
          home: home,
        )
      : MaterialApp.router(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: ruLocalizationDelegates,
          theme: theme,
          builder: wrap,
          routerConfig: router,
        );
  return ProviderScope(overrides: overrides, child: app);
}

/// Минимальный роутер для проверки **одной оболочки**: три ветки
/// `StatefulShellRoute` с пустым содержимым. Нужен там, где экран ветки ещё
/// Material (его overflow не относится к оболочке) — например, textScale 2,0
/// на этапе 3.1.
GoRouter shellOnlyRouter({Widget? screen}) {
  Widget branch(BuildContext context, GoRouterState state) =>
      screen ?? const SizedBox.expand();
  return GoRouter(
    initialLocation: '/',
    routes: <RouteBase>[
      StatefulShellRoute.indexedStack(
        builder: (
          BuildContext context,
          GoRouterState state,
          StatefulNavigationShell navigationShell,
        ) => AppShell(navigationShell: navigationShell),
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/', builder: branch)],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/statistics', builder: branch)],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[GoRoute(path: '/settings', builder: branch)],
          ),
        ],
      ),
    ],
  );
}

/// Монтирует экран на стенде; [settle] = false для повторяющихся анимаций
/// (`NcSkeleton`, спиннер) — тогда ждём фиксированный кадр.
Future<void> pumpNcScreen(
  WidgetTester tester, {
  Widget? home,
  GoRouter? router,
  List<Override> overrides = const <Override>[],
  NcScreenConfig config = const NcScreenConfig(),
  NcHaptics? haptics,
  bool settle = true,
}) async {
  tester.view.physicalSize = config.size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ncScreenApp(
      home: home,
      router: router,
      overrides: overrides,
      config: config,
      haptics: haptics,
    ),
  );
  await tester.pump();
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Монтирует экран при `textScale` 2,0 на телефоне 360 × 740 и проверяет, что
/// дерево не сообщило об overflow (§10).
Future<void> pumpNcScreenAtTextScale2(
  WidgetTester tester, {
  Widget? home,
  GoRouter? router,
  List<Override> overrides = const <Override>[],
  bool settle = true,
}) async {
  await pumpNcScreen(
    tester,
    home: home,
    router: router,
    overrides: overrides,
    config: const NcScreenConfig(
      size: Size(360, 740),
      textScale: 2,
      reduceMotion: true,
    ),
    settle: settle,
  );
  expect(
    tester.takeException(),
    isNull,
    reason: 'textScale 2,0 не должен давать overflow (REDESIGN-SPEC §10)',
  );
}
