import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/components/escape_to_back.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Экран критической ошибки старта (например, если БД не открылась).
///
/// Показывается вместо приложения, если инициализация БД/хранилища упала:
/// пользователю — только сообщение из ARB, без сырых исключений (SPEC A8.6).
class StartupErrorApp extends StatelessWidget {
  /// Создаёт экран ошибки старта.
  const StartupErrorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
      home: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context);
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  l10n.databaseOpenError,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Корневое приложение CardFlow: единственная локаль — `ru` (SPEC 3.1, 3.5).
///
/// База Material — официальный пакет `material_ui` (ADR-001). Системные строки
/// Material/Cupertino — делегаты `material_ui`, свой текст — из ARB.
///
/// Пользовательские настройки (A6.6, ADR-019) применяются здесь: тема,
/// dynamic color, повышенный контраст, шрифт для дислексии и масштаб текста.
///
/// M3 Expressive: `M3EMaterialApp` не принимает `routerConfig`/GoRouter, поэтому
/// корень — `MaterialApp.router`, а `M3ETheme` подключается в `builder` (ADR-007).
class CardFlowApp extends ConsumerStatefulWidget {
  /// Создаёт корневое приложение.
  ///
  /// [router] — override для widget-тестов (по умолчанию [createAppRouter]).
  const CardFlowApp({super.key, this.router});

  /// Маршрутизатор приложения (если не задан — создаётся стандартный).
  final GoRouter? router;

  @override
  ConsumerState<CardFlowApp> createState() => _CardFlowAppState();
}

class _CardFlowAppState extends ConsumerState<CardFlowApp>
    with WidgetsBindingObserver {
  /// Ключ навигатора: [EscapeToBack] стоит выше него и обрабатывает Esc.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Router создаётся один раз: смена темы/настроек перестраивает приложение,
  /// но не должна сбрасывать навигацию (ADR-019).
  late final GoRouter _router =
      widget.router ?? createAppRouter(navigatorKey: _navigatorKey);

  /// Адаптивная ступень типографики по физическому размеру экрана (2K/4K).
  ///
  /// Аудит v4 (V8): шкала была константой, поэтому на 2K приложение выглядело
  /// как растянутый FullHD. Ступень пересчитывается при изменении метрик окна.
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scale = AppAdaptive.factorForCurrentWindow();
    // Первый кадр: размер окна может появиться только после метрик.
    WidgetsBinding.instance.addPostFrameCallback((_) => _updateScale());
  }

  @override
  void didChangeMetrics() {
    _updateScale();
  }

  void _updateScale() {
    final double next = AppAdaptive.factorForCurrentWindow();
    if (!mounted || (next - _scale).abs() < 0.005) return;
    setState(() => _scale = next);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.router == null) _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AppSettings settings = ref.watch(effectiveAppSettingsProvider);
    if (!settings.dynamicColor) {
      return _buildApp(settings);
    }
    return DynamicColorBuilder(
      builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
        return _buildApp(
          settings,
          lightScheme: lightDynamic,
          darkScheme: darkDynamic,
        );
      },
    );
  }

  Widget _buildApp(
    AppSettings settings, {
    ColorScheme? lightScheme,
    ColorScheme? darkScheme,
  }) {
    return MaterialApp.router(
      onGenerateTitle: (context) => AppLocalizations.of(context).appTitle,
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: <LocalizationsDelegate<dynamic>>[
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      theme: AppTheme.light(
        scheme: lightScheme,
        highContrast: settings.highContrast,
        dyslexiaFont: settings.dyslexiaFont,
        scale: _scale,
      ),
      darkTheme: AppTheme.dark(
        scheme: darkScheme,
        highContrast: settings.highContrast,
        dyslexiaFont: settings.dyslexiaFont,
        scale: _scale,
      ),
      themeMode: switch (settings.theme) {
        AppThemePreference.system => ThemeMode.system,
        AppThemePreference.light => ThemeMode.light,
        AppThemePreference.dark => ThemeMode.dark,
      },
      routerConfig: _router,
      builder: (context, child) {
        // M3E-тема проецируется из Material-темы: так dynamic color, контраст
        // и шрифт дислексии из настроек действуют и на M3E-компоненты
        // (M3EResolvedTheme заменяет textTheme — ADR-019 §2).
        final M3EThemeData data = M3EThemeData.fromMaterial(Theme.of(context));
        final MediaQueryData media = MediaQuery.of(context);
        // Пользовательский масштаб применяется поверх системного, а не
        // вместо него: настройка доступности ОС продолжает работать.
        // Для линейных системных шкал (Windows/десктоп) пересчёт точный.
        final double probe = media.textScaler.scale(16);
        final double systemFactor = probe.isFinite && probe > 0
            ? probe / 16
            : 1;
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(systemFactor * settings.textScale),
          ),
          // Esc = системный «назад» на всех экранах и диалогах (N3).
          child: EscapeToBack(
            navigatorKey: _navigatorKey,
            child: M3ETheme(
              data: data,
              // Аудит v5 (V5-1): `M3EResolvedTheme` проецирует свою схему на
              // Material-тему, но в ней нет fixed-ролей (`primaryFixed`,
              // `onPrimaryFixed`) — Flutter подставлял вместо них `primary`, и
              // «Легко»/info-чипы заливались основным цветом. Внутренняя
              // Material-тема возвращает полную схему ролей; M3E-компоненты
              // продолжают читать свой inherited-тему.
              child: Theme(
                data: Theme.of(context),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
    );
  }
}
