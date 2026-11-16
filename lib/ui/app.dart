import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/design/ambient/ambient_background.dart';
import 'package:cardflow/ui/design/haptics.dart';
import 'package:cardflow/ui/design/motion_scope.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

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

class _CardFlowAppState extends ConsumerState<CardFlowApp> {
  /// Router создаётся один раз: смена темы/настроек перестраивает приложение,
  /// но не должна сбрасывать навигацию (ADR-019).
  late final GoRouter _router = widget.router ?? createAppRouter();

  /// Единая точка тактильного отклика (REDESIGN-SPEC §7): экраны берут её
  /// через `NcHaptics.of(context)`. Флаг `enabled` обновляется из настроек.
  late final NcHaptics _haptics = NcHaptics();

  @override
  void dispose() {
    _haptics.dispose();
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
      ),
      darkTheme: AppTheme.dark(
        scheme: darkScheme,
        highContrast: settings.highContrast,
        dyslexiaFont: settings.dyslexiaFont,
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
        // Настройки движения и отклика передаются сверху: дизайн-система не
        // читает провайдеры сама (ADR-035 §7).
        final NcMotion motion = NcMotion.resolve(
          preference: switch (settings.motion) {
            MotionPreference.expressive => NcMotionPreference.expressive,
            MotionPreference.standard => NcMotionPreference.standard,
          },
          disableAnimations: media.disableAnimations,
        );
        _haptics.enabled = settings.haptics;
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(settings.textScale),
          ),
          child: NcMotionScope(
            motion: motion,
            child: NcHapticsScope(
              haptics: _haptics,
              // Фон Aurora под всем приложением; `Scaffold` прозрачен через
              // тему (REDESIGN-SPEC §4.5, шаг 1.6).
              child: NcAmbientBackground(
                child: M3ETheme(
                  data: data,
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
