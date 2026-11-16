import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_media_repository.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/provider_accounts_store.dart';
import 'package:cardflow/domain/review/daily_usage_repository.dart';
import 'package:cardflow/domain/review/practice_repository.dart';
import 'package:cardflow/domain/study/match_best_store.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/data/cards/card_image_refresher.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/session/leech_repository.dart';
import 'package:cardflow/domain/session/session_preset_repository.dart';
import 'package:cardflow/domain/settings/app_settings_store.dart';
import 'package:cardflow/domain/statistics/statistics_repository.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';
import 'package:cardflow/ui/study/match_screen.dart';
import 'package:cardflow/ui/study/multiple_choice_screen.dart';
import 'package:cardflow/ui/study/true_false_screen.dart';
import 'package:cardflow/ui/study/typing_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/session/session_constructor_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'decks_fakes.dart';
import 'generation_fakes.dart';
import 'review_fakes.dart';
import 'session_fakes.dart';
import 'settings_fakes.dart';

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

/// Маршруты приложения итерации 2: «Колоды», «Колода», сессия, форма карточки.
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
    GoRoute(
      path: '/decks/:id/study',
      builder: (BuildContext context, GoRouterState state) =>
          ReviewSessionScreen(
            deckId: state.pathParameters['id']!,
            ignoreDailyLimits: _ignoresDailyLimits(state),
          ),
    ),
    GoRoute(
      path: '/decks/:id/feed',
      builder: (BuildContext context, GoRouterState state) => FeedSessionScreen(
        deckId: state.pathParameters['id']!,
        ignoreDailyLimits: _ignoresDailyLimits(state),
      ),
    ),
    GoRoute(
      path: '/decks/:id/practice',
      builder: (BuildContext context, GoRouterState state) =>
          PracticeSessionScreen(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/decks/:id/test',
      builder: (BuildContext context, GoRouterState state) =>
          MultipleChoiceScreen(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/decks/:id/typing',
      builder: (BuildContext context, GoRouterState state) =>
          TypingScreen(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/decks/:id/match',
      builder: (BuildContext context, GoRouterState state) =>
          MatchScreen(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/decks/:id/true-false',
      builder: (BuildContext context, GoRouterState state) =>
          TrueFalseScreen(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/constructor',
      builder: (BuildContext context, GoRouterState state) =>
          SessionConstructorScreen(
            preselectedDeckId: state.uri.queryParameters['deck'],
          ),
    ),
    GoRoute(
      path: '/session/classic',
      builder: (BuildContext context, GoRouterState state) =>
          ReviewSessionScreen(plan: sessionPlanFromExtra(state.extra)),
    ),
    GoRoute(
      path: '/session/feed',
      builder: (BuildContext context, GoRouterState state) =>
          FeedSessionScreen(plan: sessionPlanFromExtra(state.extra)),
    ),
    GoRoute(
      path: '/decks/:id/cards/new',
      builder: (BuildContext context, GoRouterState state) =>
          CardFormScreen(deckId: state.pathParameters['id']!),
    ),
    GoRoute(
      path: '/decks/:id/cards/:cardId/edit',
      builder: (BuildContext context, GoRouterState state) => CardFormScreen(
        deckId: state.pathParameters['id']!,
        cardId: state.pathParameters['cardId'],
      ),
    ),
  ];
}

/// Подменяет data-слой фейками (без БД, плагинов и сети).
///
/// [generationSettingsStore] и [apiKeyStore] по умолчанию — in-memory фейки
/// (`FakeGenerationSettingsStore` / `FakeApiKeyStore`, ADR-013): экран настроек
/// генерации не должен трогать drift и `flutter_secure_storage` в тестах.
List<Override> decksOverrides({
  required DeckRepository deckRepository,
  CardRepository? cardRepository,
  ReviewRepository? reviewRepository,
  PracticeRepository? practiceRepository,
  Scheduler? scheduler,
  DeckTransferService? transferService,
  FileGateway? fileGateway,
  GenerationSettingsStore? generationSettingsStore,
  ProviderAccountsStore? providerAccountsStore,
  ApiKeyStore? apiKeyStore,
  CardMediaRepository? cardMediaRepository,
  CardImageGateway? imageGateway,
  SessionPresetRepository? sessionPresetRepository,
  LeechRepository? leechRepository,
  AppSettingsStore? appSettingsStore,
  StatisticsRepository? statisticsRepository,
  FakeExternalLinkLauncher? externalLinkLauncher,
  DailyUsageRepository? dailyUsageRepository,
  CardImageRefresher? cardImageRefresher,
  MatchBestStore? matchBestStore,
}) {
  return <Override>[
    deckRepositoryProvider.overrideWithValue(deckRepository),
    cardRepositoryProvider.overrideWithValue(
      cardRepository ?? FakeCardRepository(),
    ),
    reviewRepositoryProvider.overrideWithValue(
      reviewRepository ?? FakeReviewRepository(),
    ),
    practiceRepositoryProvider.overrideWithValue(
      practiceRepository ?? FakePracticeRepository(),
    ),
    schedulerProvider.overrideWithValue(scheduler ?? FsrsScheduler()),
    deckTransferServiceProvider.overrideWithValue(
      transferService ?? FakeDeckTransferService(),
    ),
    fileGatewayProvider.overrideWithValue(fileGateway ?? FakeFileGateway()),
    generationSettingsStoreProvider.overrideWithValue(
      generationSettingsStore ?? FakeGenerationSettingsStore(),
    ),
    providerAccountsStoreProvider.overrideWithValue(
      providerAccountsStore ?? FakeProviderAccountsStore(),
    ),
    apiKeyStoreProvider.overrideWithValue(apiKeyStore ?? FakeApiKeyStore()),
    cardMediaRepositoryProvider.overrideWithValue(
      cardMediaRepository ?? FakeCardMediaRepository(),
    ),
    imageGatewayProvider.overrideWithValue(
      imageGateway ?? FakeCardImageGateway(),
    ),
    sessionPresetRepositoryProvider.overrideWithValue(
      sessionPresetRepository ?? FakeSessionPresetRepository(),
    ),
    leechRepositoryProvider.overrideWithValue(
      leechRepository ?? FakeLeechRepository(),
    ),
    appSettingsStoreProvider.overrideWithValue(
      appSettingsStore ?? FakeAppSettingsStore(),
    ),
    statisticsRepositoryProvider.overrideWithValue(
      statisticsRepository ?? FakeStatisticsRepository(),
    ),
    externalLinkLauncherProvider.overrideWithValue(
      externalLinkLauncher ?? FakeExternalLinkLauncher(),
    ),
    dailyUsageRepositoryProvider.overrideWithValue(
      dailyUsageRepository ?? FakeDailyUsageRepository(),
    ),
    if (cardImageRefresher != null)
      cardImageRefresherProvider.overrideWithValue(cardImageRefresher),
    matchBestStoreProvider.overrideWithValue(
      matchBestStore ?? FakeMatchBestStore(),
    ),
  ];
}

/// Достаёт `AppLocalizations` из смонтированного дерева (для `find.text`).
AppLocalizations l10nOf(WidgetTester tester) {
  return AppLocalizations.of(tester.element(find.byType(Scaffold).first));
}

/// Маршрут просит игнорировать дневные лимиты (`?limits=ignore`, ADR-028).
bool _ignoresDailyLimits(GoRouterState state) =>
    state.uri.queryParameters[AppRoutes.dailyLimitsQuery] ==
    AppRoutes.ignoreDailyLimitsValue;
