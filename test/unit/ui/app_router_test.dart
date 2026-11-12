import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:cardflow/ui/router/app_router.dart';

void main() {
  group('AppRoutes', () {
    test('пути стартового экрана и колоды', () {
      expect(AppRoutes.decksPath, '/');
      expect(AppRoutes.deckPath('deck-1'), '/decks/deck-1');
    });
  });

  group('createAppRouter', () {
    test('содержит маршруты «Колоды» и «Колода» с именами', () {
      final router = createAppRouter();
      addTearDown(router.dispose);

      final routes = router.configuration.routes;
      expect(routes, hasLength(2));
      final decksRoute = routes[0] as GoRoute;
      final deckRoute = routes[1] as GoRoute;
      expect(decksRoute.path, '/');
      expect(decksRoute.name, AppRoutes.decks);
      expect(deckRoute.path, '/decks/:deckId');
      expect(deckRoute.name, AppRoutes.deck);
    });

    test('имена маршрутов заданы и уникальны', () {
      final router = createAppRouter();
      addTearDown(router.dispose);
      final names = router.configuration.routes
          .map((route) => (route as GoRoute).name)
          .toList();
      expect(names, containsAll(<String>[AppRoutes.decks, AppRoutes.deck]));
      expect(names.toSet(), hasLength(names.length));
    });
  });
}
