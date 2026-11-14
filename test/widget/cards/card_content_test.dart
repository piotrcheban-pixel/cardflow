import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/review_card_view.dart';

import '../../helpers/pump_app.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);
  final png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  Card card({
    String front = 'Вопрос',
    String back = 'Ответ',
    CardType type = CardType.basic,
    String? occlusionJson,
    List<String> mediaIds = const <String>[],
  }) => Card(
    id: 'card-1',
    deckId: 'deck-1',
    front: front,
    back: back,
    cardType: type,
    state: CardState.newCard,
    createdAt: now,
    updatedAt: now,
    occlusionJson: occlusionJson,
    mediaIds: mediaIds,
  );

  Future<void> pumpClassic(
    WidgetTester tester,
    Card value, {
    Uint8List? image,
    bool revealed = false,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: ReviewCardView(
            front: value.front,
            back: value.back,
            card: value,
            mediaBytes: <String, Uint8List>{'media-1': ?image},
            revealed: revealed,
            onTap: () {},
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('классика: cloze скрывает ответ и раскрывает группу по тапу', (
    tester,
  ) async {
    await pumpClassic(
      tester,
      card(front: 'Столица {{c1::Париж}}', back: '', type: CardType.cloze),
    );

    expect(find.byKey(const ValueKey('cloze-gap-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloze-answer-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('cloze-gap-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cloze-answer-1')), findsOneWidget);
  });

  testWidgets('классика: общее раскрытие cloze показывает все ответы', (
    tester,
  ) async {
    await pumpClassic(
      tester,
      card(front: '{{c1::А}} и {{c2::Б}}', back: '', type: CardType.cloze),
      revealed: true,
    );

    expect(find.byKey(const ValueKey('cloze-answer-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloze-answer-2')), findsOneWidget);
  });

  testWidgets('лента: тот же cloze-рендер раскрывает один пропуск', (
    tester,
  ) async {
    final value = card(
      front: 'А {{c1::Б}} и {{c2::В}}',
      back: '',
      type: CardType.cloze,
    );
    await tester.pumpWidget(
      appWithHome(
        overrides: const [],
        home: Scaffold(
          body: FeedCardView(
            front: value.front,
            back: value.back,
            card: value,
            revealed: false,
            rated: false,
            rating: null,
            enabled: true,
            resetToken: 0,
            onTap: () {},
            onRate: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('cloze-gap-1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('cloze-gap-1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('cloze-answer-1')), findsOneWidget);
    expect(find.byKey(const ValueKey('cloze-answer-2')), findsNothing);
  });

  testWidgets('классика: LaTeX рендерится нативно и раскрывается по шагам', (
    tester,
  ) async {
    await pumpClassic(tester, card(front: r'$x=1$ затем $y=2$'));

    expect(find.byType(Math), findsOneWidget);
    expect(find.byKey(const ValueKey('latex-next-step')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('latex-next-step')));
    await tester.pump();
    expect(find.byType(Math), findsNWidgets(2));
  });

  testWidgets('ошибка LaTeX: исходный текст и предупреждение, карточка видна', (
    tester,
  ) async {
    await pumpClassic(tester, card(front: r'Ошибка $\frac{'));

    expect(find.textContaining('Ошибка', findRichText: true), findsWidgets);
    expect(find.text('Ошибка разметки формулы'), findsOneWidget);
    expect(find.byType(Math), findsNothing);
  });

  testWidgets('occlusion: общее раскрытие показывает маски, hide возвращает', (
    tester,
  ) async {
    const raw =
        '{"version":1,"masks":['
        '{"id":"m1","shape":"rectangle","x":0,"y":0,"width":1,"height":1}]}';
    await pumpClassic(
      tester,
      card(occlusionJson: raw, mediaIds: const <String>['media-1']),
      image: png,
      revealed: true,
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsNothing);
    await tester.ensureVisible(
      find.byKey(const ValueKey('occlusion-hide-all')),
    );
    await tester.tap(find.byKey(const ValueKey('occlusion-hide-all')));
    await tester.pump();
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsOneWidget);
  });

  testWidgets('occlusion: изображение, тап маски и показать/скрыть все', (
    tester,
  ) async {
    const raw =
        '{"version":1,"masks":['
        '{"id":"m1","shape":"rectangle","x":0,"y":0,"width":1,"height":1}]}';
    await pumpClassic(
      tester,
      card(occlusionJson: raw, mediaIds: const <String>['media-1']),
      image: png,
    );
    await tester.pump();

    expect(find.byType(Image), findsOneWidget);
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('occlusion-cover-m1')));
    await tester.pump();
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('occlusion-hide-all')));
    await tester.pump();
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('occlusion-show-all')));
    await tester.pump();
    expect(find.byKey(const ValueKey('occlusion-cover-m1')), findsNothing);
  });
}
