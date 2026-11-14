import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cardflow/ui/router/app_router.dart';

void main() {
  group('AppRoutes', () {
    test(
      'пути списка, колоды, сессии, формы карточки, генерации и настроек',
      () {
        expect(AppRoutes.decksPath, '/');
        expect(AppRoutes.deckPath('deck-1'), '/decks/deck-1');
        expect(AppRoutes.studyPath('deck-1'), '/decks/deck-1/study');
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
      },
    );
  });

  group('createAppRouter', () {
    test(
      'содержит 8 маршрутов (итерации 2, 3c и настройки генерации) с именами',
      () {
        final router = createAppRouter();
        addTearDown(router.dispose);

        final routes = router.configuration.routes;
        expect(routes, hasLength(8));
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
        expect(paths, contains('/decks/:deckId/generate'));
        expect(paths, contains('/generate'));
        expect(paths, contains('/decks/:deckId/cards/new'));
        expect(paths, contains('/decks/:deckId/cards/:cardId/edit'));
        expect(paths, contains('/settings/generation'));
        expect(
          names,
          containsAll(<String>[
            AppRoutes.decks,
            AppRoutes.deck,
            AppRoutes.study,
            AppRoutes.deckGeneration,
            AppRoutes.generation,
            AppRoutes.cardNew,
            AppRoutes.cardEdit,
            AppRoutes.generationSettings,
          ]),
        );
        expect(AppRoutes.generationSettings, 'generationSettings');
        expect(names.toSet(), hasLength(names.length));
      },
    );
  });
}
