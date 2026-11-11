import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

/// Корневое приложение CardFlow: единственная локаль — `ru` (SPEC 3.1, 3.5).
///
/// База Material — официальный пакет `material_ui` (ADR-001). Системные строки
/// Material/Cupertino — делегаты `material_ui`, свой текст — из ARB.
class CardFlowApp extends StatelessWidget {
  /// Создаёт корневой виджет приложения.
  const CardFlowApp({super.key});

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
      home: const HomeShell(),
    );
  }
}

/// Корневой каркас итерации 0.
///
/// Экраны MVP (Колоды, Сессия, Статистика, Настройки) появятся в итерациях 1–7;
/// до этого приложение показывает только заголовок из ARB — без мёртвых кнопок.
class HomeShell extends StatelessWidget {
  /// Создаёт каркас.
  const HomeShell({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.appTitle)),
      body: const SizedBox.shrink(),
    );
  }
}
