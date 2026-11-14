import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/ui/router/app_router.dart';

void main() {
  group('AppRoutes', () {
    test(
      'пути списка, колоды, сессии, формы карточки, генерации, конструктора и настроек',
      () {
        expect(AppRoutes.decksPath, '/');
        expect(AppRoutes.deckPath('deck-1'), '/decks/deck-1');
        expect(AppRoutes.studyPath('deck-1'), '/decks/deck-1/study');
        expect(AppRoutes.feedPath('deck-1'), '/decks/deck-1/feed');
        expect(AppRoutes.cardNewPath('deck-1'), '/decks/deck-1/cards/new');
        expect(
          AppRoutes.cardEditPath('deck-1', 'card-1'),
          '/decks/deck-1/cards/card-1/edit',
        );
        expect(AppRoutes.generationPath, '/generate');
        expect(
          AppRoutes.deckGenerationPath('deck-1'),
          '/decks/deck-1/generate',
        );
        expect(AppRoutes.generationSettingsPath, '/settings/generation');
        expect(AppRoutes.constructorPath, '/constructor');
        expect(
          AppRoutes.constructorDeckPath('deck-1'),
          '/constructor?deck=deck-1',
        );
        expect(AppRoutes.sessionClassicPath, '/session/classic');
        expect(AppRoutes.sessionFeedPath, '/session/feed');
      },
    );

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
    test('содержит 12 маршрутов (итерации 2, 3c, 4, 6) с уникальными именами', () {
      final router = createAppRouter();
      addTearDown(router.dispose);

      final routes = router.configuration.routes;
      expect(routes, hasLength(12));
      final paths = <String>[];
      final names = <String?>[];
      for (final route in routes) {
        final goRoute = route as GoRoute;
        paths.add(goRoute.path);
        names.add(goRoute.name);
      }

      expect(paths, contains('/'));
      expect(paths, contains('/decks/:deckId'));
      expect(paths, contains('/decks/:deckId/study'));
      expect(paths, contains('/decks/:deckId/feed'));
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
          AppRoutes.deck,
          AppRoutes.study,
          AppRoutes.feed,
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
