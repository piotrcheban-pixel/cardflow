import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/review/review_card_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Итерация 7.19, группа C (отображение): на лицевой стороне только
/// questionMedia, на обратной — только answerMedia; ошибки чтения и
/// декодирования показываются явно.
void main() {
  final Uint8List png = Uint8List.fromList(
    img.encodePng(img.Image(width: 40, height: 30)),
  );
  final Uint8List broken = Uint8List.fromList(<int>[1, 2, 3, 4, 5]);

  Card cardWith({
    List<String> question = const <String>['q1'],
    List<String> answer = const <String>['a1'],
  }) => makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Какой формулой рассчитывают воздухопроницаемость?',
    back: r'$G = A \cdot \Delta P^{0.67} / R$',
    questionMediaIds: question,
    answerMediaIds: answer,
  );

  Future<void> pumpContent(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: SingleChildScrollView(child: Center(child: child)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget content(
    Card card, {
    required String side,
    Map<String, Uint8List> bytes = const <String, Uint8List>{},
  }) {
    return CardContentView(
      card: card,
      side: side,
      revealed: side == card.back,
      faceKey: const ValueKey<String>('face'),
      mediaBytes: bytes,
    );
  }

  testWidgets('C29: до переворота видны только изображения вопроса', (
    tester,
  ) async {
    final Card card = cardWith();
    await pumpContent(
      tester,
      content(
        card,
        side: card.front,
        bytes: <String, Uint8List>{'q1': png, 'a1': png},
      ),
    );

    expect(find.byKey(const ValueKey<String>('card-image-q1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('card-image-a1')), findsNothing);
  });

  testWidgets('C30: после переворота видны только изображения ответа', (
    tester,
  ) async {
    final Card card = cardWith();
    await pumpContent(
      tester,
      content(
        card,
        side: card.back,
        bytes: <String, Uint8List>{'q1': png, 'a1': png},
      ),
    );

    expect(find.byKey(const ValueKey<String>('card-image-a1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('card-image-q1')), findsNothing);
  });

  testWidgets('несколько изображений на стороне', (tester) async {
    final Card card = cardWith(
      question: <String>['q1', 'q2'],
      answer: <String>['a1', 'a2', 'a3'],
    );
    await pumpContent(
      tester,
      content(
        card,
        side: card.back,
        bytes: <String, Uint8List>{
          'q1': png,
          'q2': png,
          'a1': png,
          'a2': png,
          'a3': png,
        },
      ),
    );
    expect(find.byType(CardImageView), findsNWidgets(3));
  });

  testWidgets('старая карточка: единственное изображение — сторона вопроса', (
    tester,
  ) async {
    final Card card = makeCard(
      id: 'card-legacy',
      deckId: 'deck-1',
      front: 'Что на схеме?',
      back: 'Схема фермы',
      questionMediaIds: const <String>['legacy'],
    );
    await pumpContent(
      tester,
      content(
        card,
        side: card.front,
        bytes: <String, Uint8List>{'legacy': png},
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('card-image-legacy')),
      findsOneWidget,
    );

    await pumpContent(
      tester,
      content(card, side: card.back, bytes: <String, Uint8List>{'legacy': png}),
    );
    expect(find.byType(CardImageView), findsNothing);
  });

  testWidgets('A5/A6: отсутствующий файл — явное состояние, а не заглушка', (
    tester,
  ) async {
    final Card card = cardWith();
    await pumpContent(tester, content(card, side: card.front));

    expect(
      find.byKey(const ValueKey<String>('card-image-unavailable-q1')),
      findsOneWidget,
    );
    expect(find.byType(CardImageView), findsNothing);
    expect(find.text(l10nOf(tester).cardImageUnavailable), findsOneWidget);
  });

  testWidgets('A6: повреждённые байты — ошибка декодирования с повтором', (
    tester,
  ) async {
    final Card card = cardWith();
    await pumpContent(
      tester,
      content(card, side: card.front, bytes: <String, Uint8List>{'q1': broken}),
    );
    await tester.pump();

    // Ошибка отрисована внутри CardImageView: исходник не подменяется.
    expect(
      find.byKey(const ValueKey<String>('card-image-error')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-image-retry')),
      findsOneWidget,
    );
  });

  testWidgets('C29/C30 на экране обучения: ответ не виден до переворота', (
    tester,
  ) async {
    final Card card = cardWith();
    tester.view.physicalSize = const Size(800, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: ReviewCardView(
            front: card.front,
            back: card.back,
            revealed: false,
            onTap: () {},
            card: card,
            mediaBytes: <String, Uint8List>{'q1': png, 'a1': png},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('card-image-q1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('card-image-a1')), findsNothing);

    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: ReviewCardView(
            front: card.front,
            back: card.back,
            revealed: true,
            onTap: () {},
            card: card,
            mediaBytes: <String, Uint8List>{'q1': png, 'a1': png},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey<String>('card-image-a1')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('card-image-q1')), findsNothing);
  });
}
