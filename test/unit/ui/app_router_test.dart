import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/ui/router/app_router.dart';

void main() {
  group('AppRoutes', () {
    test('пути списка, колоды, сессии, формы карточки, генерации, конструктора и настроек', () {
      expect(AppRoutes.decksPath, '/');
      expect(AppRoutes.deckPath('deck-1'), '/decks/deck-1');
      expect(AppRoutes.studyPath('deck-1'), '/decks/deck-1/study');
      expect(AppRoutes.feedPath('deck-1'), '/decks/deck-1/feed');
      expect(AppRoutes.practicePath('deck-1'), '/decks/deck-1/practice');
      expect(AppRoutes.testPath('deck-1'), '/decks/deck-1/test');
      expect(AppRoutes.typingPath('deck-1'), '/decks/deck-1/typing');
      expect(AppRoutes.cardNewPath('deck-1'), '/decks/deck-1/cards/new');
      expect(
        AppRoutes.cardEditPath('deck-1', 'card-1'),
        '/decks/deck-1/cards/card-1/edit',
      );
      expect(AppRoutes.generationPath, '/generate');
      expect(AppRoutes.deckGenerationPath('deck-1'), '/decks/deck-1/generate');
      expect(AppRoutes.generationSettingsPath, '/settings/generation');
      expect(AppRoutes.statisticsPath, '/statistics');
      expect(AppRoutes.settingsPath, '/settings');
      expect(AppRoutes.constructorPath, '/constructor');
      expect(
        AppRoutes.constructorDeckPath('deck-1'),
        '/constructor?deck=deck-1',
      );
      expect(AppRoutes.sessionClassicPath, '/session/classic');
      expect(AppRoutes.sessionFeedPath, '/session/feed');
    });

    test('план сессии читается только из extra типа SessionPlan', () {
      final SessionPlan plan = SessionPlan(
        cards: <Card>[
          Card(
            id: 'card-1',
            deckId: 'deck-1',
            front: 'Вопрос',
            back: 'Ответ',
            cardType: CardType.basic,
            state: CardState.newCard,
            createdAt: DateTime.utc(2026, 11, 14),
            updatedAt: DateTime.utc(2026, 11, 14),
          ),
        ],
      );

      expect(sessionPlanFromExtra(plan), plan);
      expect(sessionPlanFromExtra(null), isNull);
      expect(sessionPlanFromExtra('не план'), isNull);
    });
  });

  group('createAppRouter', () {
    test('содержит оболочку A6.1 и 15 верхнеуровневых маршрутов с уникальными именами', () {
      final router = createAppRouter();
      addTearDown(router.dispose);

      final routes = router.configuration.routes;
      expect(routes, hasLength(15));
      final shell = routes.first;
      expect(shell, isA<StatefulShellRoute>());
      final branchRoutes = <GoRoute>[
        for (final StatefulShellBranch branch
            in (shell as StatefulShellRoute).branches)
          for (final RouteBase route in branch.routes) route as GoRoute,
      ];
      expect(branchRoutes, hasLength(3));
      final goRoutes = <GoRoute>[
        ...routes.whereType<GoRoute>(),
        ...branchRoutes,
      ];
      final paths = <String>[for (final GoRoute route in goRoutes) route.path];
      final names = <String?>[for (final GoRoute route in goRoutes) route.name];

      expect(paths, contains('/'));
      expect(paths, contains('/statistics'));
      expect(paths, contains('/settings'));
      expect(paths, contains('/decks/:deckId'));
      expect(paths, contains('/decks/:deckId/study'));
      expect(paths, contains('/decks/:deckId/feed'));
      expect(paths, contains('/decks/:deckId/practice'));
      expect(paths, contains('/decks/:deckId/test'));
      expect(paths, contains('/decks/:deckId/typing'));
      expect(paths, contains('/decks/:deckId/generate'));
      expect(paths, contains('/generate'));
      expect(paths, contains('/decks/:deckId/cards/new'));
      expect(paths, contains('/decks/:deckId/cards/:cardId/edit'));
      expect(paths, contains('/settings/generation'));
      expect(paths, contains('/constructor'));
      expect(paths, contains('/session/classic'));
      expect(paths, contains('/session/feed'));
      expect(
        names,
        containsAll(<String>[
          AppRoutes.decks,
          AppRoutes.statistics,
          AppRoutes.settings,
          AppRoutes.deck,
          AppRoutes.study,
          AppRoutes.feed,
          AppRoutes.practice,
          AppRoutes.test,
          AppRoutes.typing,
          AppRoutes.deckGeneration,
          AppRoutes.generation,
          AppRoutes.cardNew,
          AppRoutes.cardEdit,
          AppRoutes.generationSettings,
          AppRoutes.constructor,
          AppRoutes.sessionClassic,
          AppRoutes.sessionFeed,
        ]),
      );
      expect(AppRoutes.generationSettings, 'generationSettings');
      expect(names.toSet(), hasLength(names.length));
    });
  });
}
