import 'package:go_router/go_router.dart';

import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';

/// Имена маршрутов приложения (для тестов и навигации).
abstract final class AppRoutes {
  /// Список колод (стартовый экран).
  static const String decks = 'decks';

  /// Экран конкретной колоды.
  static const String deck = 'deck';

  /// Путь списка колод.
  static const String decksPath = '/';

  /// Путь экрана колоды по id.
  static String deckPath(String deckId) => '/decks/$deckId';
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
    ],
  );
}
