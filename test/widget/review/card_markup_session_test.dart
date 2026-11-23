import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

void main() {
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  Future<void> pumpSession(
    WidgetTester tester,
    Card card, {
    required String location,
  }) async {
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(
            summaries: <DeckSummary>[
              makeSummary(
                id: 'deck-1',
                name: 'Колода',
                totalCards: 1,
                newCards: 1,
              ),
            ],
          ),
          cardRepository: FakeCardRepository(cards: <Card>[card]),
          reviewRepository: FakeReviewRepository(),
          cardMediaRepository: FakeCardMediaRepository(
            bytesById: <String, dynamic>{'media-1': png}.cast(),
          ),
        ),
        routes: decksRoutes(),
        initialLocation: location,
      ),
    );
    if (location.endsWith('/feed')) {
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 30));
      await tester.pump(const Duration(milliseconds: 30));
    } else {
      await tester.pumpAndSettle();
    }
  }

  testWidgets('классика: cloze из production-экрана раскрывается по тапу', (
    tester,
  ) async {
    await pumpSession(
      tester,
      makeCard(
        id: 'cloze-1',
        deckId: 'deck-1',
        front: 'Столица {{c1::Париж}}',
        back: '',
        cardType: CardType.cloze,
      ),
      location: '/decks/deck-1/study',
    );

    expect(find.byKey(const ValueKey('cloze-gap-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloze-gap-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cloze-answer-1')), findsOneWidget);
  });

  testWidgets('лента: cloze из production-экрана раскрывается по тапу', (
    tester,
  ) async {
    await pumpSession(
      tester,
      makeCard(
        id: 'cloze-2',
        deckId: 'deck-1',
        front: 'Столица {{c1::Париж}}',
        back: '',
        cardType: CardType.cloze,
      ),
      location: '/decks/deck-1/feed',
    );
    await tester.pump(const Duration(milliseconds: 30));

    expect(find.byKey(const ValueKey('cloze-gap-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloze-gap-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cloze-answer-1')), findsOneWidget);
  });

  testWidgets('классика: изображение и маска приходят через media provider', (
    tester,
  ) async {
    await pumpSession(
      tester,
      makeCard(
        id: 'occlusion-1',
        deckId: 'deck-1',
        front: 'Схема',
        back: 'Ответ',
        mediaIds: const <String>['media-1'],
        occlusionJson:
            '{"version":1,"masks":[{"id":"m1","shape":"rectangle",'
            '"x":0,"y":0,"width":1,"height":1}]}',
      ),
      location: '/decks/deck-1/study',
    );

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsOneWidget);
    // Карточка сессии имеет постоянную высоту и прокручиваемое тело:
    // элемент маски прокручиваем к видимой области (F27).
    await tester.ensureVisible(
      find.byKey(const ValueKey('occlusion-cover-m1')),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('occlusion-cover-m1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsNothing);
  });
}
