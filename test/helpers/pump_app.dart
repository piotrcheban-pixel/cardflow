import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'decks_fakes.dart';

/// Тестовый harness приложения CardFlow (итерация 1).
///
/// Повторяет продовую обвязку: `MaterialApp` (`material_ui`, ADR-001) +
/// `M3ETheme` в `builder` (M3EMaterialApp не принимает `routerConfig`, ADR-007),
/// локаль только `ru`, делегаты локализации — из `material_ui`.

/// `builder` с M3E-темой по системной яркости (как будет в `lib/ui/app.dart`).
Widget m3eThemeBuilder(BuildContext context, Widget? child) {
  final Brightness brightness = MediaQuery.platformBrightnessOf(context);
  return M3ETheme(
    data: brightness == Brightness.dark
        ? M3EThemeData.dark(seedColor: AppTheme.seedColor)
        : M3EThemeData.light(seedColor: AppTheme.seedColor),
    child: child!,
  );
}

/// Делегаты локализации для `material_ui` MaterialApp (не framework-версия).
final List<LocalizationsDelegate<dynamic>> ruLocalizationDelegates =
    <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ];

/// Собирает приложение с GoRouter и фейковым data-слоем.
Widget appWithRouter({
  required List<Override> overrides,
  required List<GoRoute> routes,
  String initialLocation = '/',
}) {
  final GoRouter router = GoRouter(
    initialLocation: initialLocation,
    routes: routes,
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: m3eThemeBuilder,
      routerConfig: router,
    ),
  );
}

/// Собирает приложение без роутера (один экран — `home`).
Widget appWithHome({required List<Override> overrides, required Widget home}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      builder: m3eThemeBuilder,
      home: home,
    ),
  );
}

/// Маршруты приложения итерации 1: «Колоды» (`/`) и «Колода» (`/decks/:id`).
List<GoRoute> decksRoutes() {
  return <GoRoute>[
    GoRoute(
      path: '/',
      builder: (BuildContext context, GoRouterState state) =>
          const DecksScreen(),
    ),
    GoRoute(
      path: '/decks/:id',
      builder: (BuildContext context, GoRouterState state) =>
          DeckScreen(deckId: state.pathParameters['id']!),
    ),
  ];
}

/// Подменяет data-слой фейками (без БД, плагинов и сети).
List<Override> decksOverrides({
  required DeckRepository deckRepository,
  CardRepository? cardRepository,
  DeckTransferService? transferService,
  FileGateway? fileGateway,
}) {
  return <Override>[
    deckRepositoryProvider.overrideWithValue(deckRepository),
    cardRepositoryProvider.overrideWithValue(
      cardRepository ?? FakeCardRepository(),
    ),
    deckTransferServiceProvider.overrideWithValue(
      transferService ?? FakeDeckTransferService(),
    ),
    fileGatewayProvider.overrideWithValue(fileGateway ?? FakeFileGateway()),
  ];
}

/// Достаёт `AppLocalizations` из смонтированного дерева (для `find.text`).
AppLocalizations l10nOf(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
}
