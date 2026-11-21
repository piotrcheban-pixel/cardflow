import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/ui/cards/content/card_content_view.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Красная фаза 7.19 (дефект D3): единственное изображение карточки —
/// иллюстрация **вопроса**; на обратной стороне до 7.19 оно тоже рисовалось,
/// раскрывая ответ. Проверка на `CardContentView` (общий рендер классики, ленты,
/// тренировки и режимов «Тест»/«Ввод»/«Верно-неверно»).
void main() {
  final Uint8List png = Uint8List.fromList(
    img.encodePng(img.Image(width: 32, height: 24)),
  );

  testWidgets('обратная сторона не показывает изображение вопроса', (
    tester,
  ) async {
    final Card card = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Какой формулой рассчитывают воздухопроницаемость?',
      back: r'$G = A \cdot \Delta P^{0.67} / R$',
      mediaIds: const <String>['formula'],
    );

    tester.view.physicalSize = const Size(800, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: Scaffold(
          body: CardContentView(
            card: card,
            side: card.back,
            revealed: true,
            faceKey: const ValueKey<String>('face'),
            mediaBytes: <String, Uint8List>{'formula': png},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(CardImageView),
      findsNothing,
      reason: 'изображение вопроса не должно раскрывать ответ на обороте',
    );
  });
}
