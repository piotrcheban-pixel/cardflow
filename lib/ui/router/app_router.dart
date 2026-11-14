import 'package:go_router/go_router.dart';

import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';

/// Имена маршрутов приложения (для тестов и навигации).
abstract final class AppRoutes {
  /// Список колод (стартовый экран).
  static const String decks = 'decks';

  /// Экран конкретной колоды.
  static const String deck = 'deck';

  /// Классическая сессия повторения.
  static const String study = 'study';

  /// Сессия в режиме «Лента» (SPEC A7.3).
  static const String feed = 'feed';

  /// Создание карточки.
  static const String cardNew = 'cardNew';

  /// Редактирование карточки.
  static const String cardEdit = 'cardEdit';

  /// Настройки генерации (OpenAI-совместимый сервер, ADR-013).
  static const String generationSettings = 'generationSettings';

  /// Экран генерации карточек с созданием новой колоды (A6.8).
  static const String generation = 'generation';

  /// Экран генерации карточек в существующую колоду (A6.3).
  static const String deckGeneration = 'deckGeneration';

  /// Путь списка колод.
  static const String decksPath = '/';

  /// Путь экрана колоды по id.
  static String deckPath(String deckId) => '/decks/$deckId';

  /// Путь сессии по колоде.
  static String studyPath(String deckId) => '/decks/$deckId/study';

  /// Путь сессии-ленты по колоде (SPEC A7.3).
  static String feedPath(String deckId) => '/decks/$deckId/feed';

  /// Путь создания карточки в колоде.
  static String cardNewPath(String deckId) => '/decks/$deckId/cards/new';

  /// Путь редактирования карточки.
  static String cardEditPath(String deckId, String cardId) =>
      '/decks/$deckId/cards/$cardId/edit';

  /// Путь экрана настроек генерации.
  static const String generationSettingsPath = '/settings/generation';

  /// Путь экрана генерации карточек (новая колода).
  static const String generationPath = '/generate';

  /// Путь экрана генерации карточек в существующую колоду.
  static String deckGenerationPath(String deckId) => '/decks/$deckId/generate';
}

/// Собирает маршрутизатор приложения (ADR: GoRouter).
///
/// Функция (а не глобальный синглтон) — чтобы widget-тесты создавали чистый
/// экземпляр без общего состояния между тестами.
GoRouter createAppRouter({String initialLocation = AppRoutes.decksPath}) {
  return GoRouter(
    initialLocation: initialLocation,
    routes: <RouteBase>[
      GoRoute(
        path: AppRoutes.decksPath,
        name: AppRoutes.decks,
        builder: (context, state) => const DecksScreen(),
      ),
      GoRoute(
        path: '/decks/:deckId',
        name: AppRoutes.deck,
        builder: (context, state) =>
            DeckScreen(deckId: state.pathParameters['deckId']!),
      ),
      GoRoute(
        path: '/decks/:deckId/study',
        name: AppRoutes.study,
        builder: (context, state) =>
            ReviewSessionScreen(deckId: state.pathParameters['deckId']!),
      ),
      GoRoute(
        path: '/decks/:deckId/feed',
        name: AppRoutes.feed,
        builder: (context, state) =>
            FeedSessionScreen(deckId: state.pathParameters['deckId']!),
      ),
      GoRoute(
        path: '/decks/:deckId/generate',
        name: AppRoutes.deckGeneration,
        builder: (context, state) =>
            GenerationScreen(deckId: state.pathParameters['deckId']),
      ),
      GoRoute(
        path: AppRoutes.generationPath,
        name: AppRoutes.generation,
        builder: (context, state) => const GenerationScreen(),
      ),
      GoRoute(
        path: '/decks/:deckId/cards/new',
        name: AppRoutes.cardNew,
        builder: (context, state) =>
            CardFormScreen(deckId: state.pathParameters['deckId']!),
      ),
      GoRoute(
        path: '/decks/:deckId/cards/:cardId/edit',
        name: AppRoutes.cardEdit,
        builder: (context, state) => CardFormScreen(
          deckId: state.pathParameters['deckId']!,
          cardId: state.pathParameters['cardId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.generationSettingsPath,
        name: AppRoutes.generationSettings,
        builder: (context, state) => const GenerationSettingsScreen(),
      ),
    ],
  );
}
