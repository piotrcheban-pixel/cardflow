import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

/// Корневое приложение CardFlow: единственная локаль — `ru` (SPEC 3.1, 3.5).
///
/// База Material — официальный пакет `material_ui` (ADR-001). Системные строки
/// Material/Cupertino — делегаты `material_ui`, свой текст — из ARB.
///
/// M3 Expressive: `M3EMaterialApp` не принимает `routerConfig`/GoRouter, поэтому
/// корень — `MaterialApp.router`, а `M3ETheme` подключается в `builder` (ADR-007).
class CardFlowApp extends StatelessWidget {
  /// Создаёт корневое приложение.
  ///
  /// [router] — override для widget-тестов (по умолчанию [createAppRouter]).
  const CardFlowApp({super.key, this.router});

  /// Маршрутизатор приложения (если не задан — создаётся стандартный).
  final GoRouter? router;

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
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
      routerConfig: router ?? createAppRouter(),
      builder: (context, child) {
        final brightness = Theme.of(context).brightness;
        final data = brightness == Brightness.dark
            ? M3EThemeData.dark(seedColor: AppTheme.seedColor)
            : M3EThemeData.light(seedColor: AppTheme.seedColor);
        return M3ETheme(data: data, child: child ?? const SizedBox.shrink());
      },
    );
  }
}
