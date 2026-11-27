import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/ui/cards/content/card_image_view.dart';
import 'package:cardflow/ui/review/feed_card_view.dart';
import 'package:cardflow/ui/review/review_card_view.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// TASK 04, часть 6: изображение в «Ленте» и «Классике» использует один бюджет.
///
/// Дефект: лента передавала `imageMaxHeight = max(96, min(160, h * 0.24))`, а
/// классика — `max(140, h * 0.42)`, поэтому на телефоне фото в ленте было в
/// 2–3 раза меньше. Правила `BoxFit`, пропорций и `maxHeight` теперь считает
/// `CardImageBudget.side` для обоих режимов.
void main() {
  final Uint8List png = Uint8List.fromList(
    img.encodePng(img.Image(width: 800, height: 600)),
  );

  const MediaMetadata metadata = MediaMetadata(
    provider: 'wikimedia',
    sourceUrl: 'https://upload.wikimedia.org/mitochondria.jpg',
    author: 'Иван Петров',
    license: 'CC BY-SA 4.0',
    kind: GeneratedCardImageKind.photo,
  );

  Card cardWithImage() => makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Какой органоид синтезирует АТФ?',
    back: 'Митохондрия',
    mediaIds: const <String>['media-1'],
  );

  Future<void> pumpCard(
    WidgetTester tester, {
    required bool feed,
    required Size size,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final Card card = cardWithImage();
    final Map<String, Uint8List> media = <String, Uint8List>{'media-1': png};
    final Map<String, MediaMetadata> mediaMetadata = <String, MediaMetadata>{
      'media-1': metadata,
    };
    final Widget view = feed
        ? FeedCardView(
            front: card.front,
            back: card.back,
            revealed: false,
            onTap: () {},
            card: card,
            mediaBytes: media,
            mediaMetadata: mediaMetadata,
          )
        : ReviewCardView(
            front: card.front,
            back: card.back,
            revealed: false,
            onTap: () {},
            card: card,
            mediaBytes: media,
            mediaMetadata: mediaMetadata,
          );
    await tester.pumpWidget(
      appWithHome(
        overrides: const <Override>[],
        home: MediaQuery(
          data: MediaQueryData(size: size),
          child: Scaffold(
            body: Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: view,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('телефон: фото в ленте не меньше 85 % высоты фото в классике', (
    WidgetTester tester,
  ) async {
    const Size phone = Size(390, 844);
    await pumpCard(tester, feed: true, size: phone);
    expect(find.byType(CardImageView), findsOneWidget);
    final Size feed = tester.getSize(find.byType(CardImageView));

    await pumpCard(tester, feed: false, size: phone);
    final Size classic = tester.getSize(find.byType(CardImageView));

    // Обе картинки вписаны целиком (AR файла 4:3), без обрезки.
    expect(feed.width / feed.height, closeTo(800 / 600, 0.02));
    expect(classic.width / classic.height, closeTo(800 / 600, 0.02));
    // До TASK 04 в ленте высота фото была ≤ 160 px при ~250 px в классике
    // (около 0,6). Теперь доля высоты одна и та же.
    expect(
      feed.height,
      greaterThanOrEqualTo(classic.height * 0.85),
      reason: 'лента больше не уменьшает фото относительно классики',
    );
    expect(
      feed.height,
      greaterThan(160),
      reason: 'прежний потолок 160 px больше не действует',
    );
  });

  testWidgets('десктоп: изображение рядом с текстом в обоих режимах', (
    WidgetTester tester,
  ) async {
    const Size desktop = Size(1280, 900);
    await pumpCard(tester, feed: true, size: desktop);
    final Size feed = tester.getSize(find.byType(CardImageView));
    await pumpCard(tester, feed: false, size: desktop);
    final Size classic = tester.getSize(find.byType(CardImageView));
    expect(feed.width, greaterThan(0));
    expect(classic.width, greaterThan(0));
    expect(
      feed.width,
      greaterThanOrEqualTo(classic.width * 0.7),
      reason: 'ширина слота изображения сопоставима',
    );
  });

  group('CardImageBudget.side — единые правила (часть 6)', () {
    test('вертикальная раскладка: 42 % высоты, минимум 140/160', () {
      final CardImageBudget budget = CardImageBudget.side(
        availableHeight: 600,
        columnWidth: 342,
        sideBySide: false,
      );
      expect(budget.maxHeight, closeTo(252, 0.001));
      expect(budget.maxWidth, 342);

      final CardImageBudget answer = CardImageBudget.side(
        availableHeight: 600,
        columnWidth: 342,
        sideBySide: false,
        isAnswer: true,
      );
      expect(answer.maxHeight, closeTo(252, 0.001));

      final CardImageBudget short = CardImageBudget.side(
        availableHeight: 200,
        columnWidth: 300,
        sideBySide: false,
        isAnswer: true,
      );
      expect(short.maxHeight, 160, reason: 'минимум ответа');

      final CardImageBudget shortQuestion = CardImageBudget.side(
        availableHeight: 200,
        columnWidth: 300,
        sideBySide: false,
      );
      expect(shortQuestion.maxHeight, 140, reason: 'минимум вопроса');
    });

    test('рядом с текстом: ширина слота 36 % колонки, но не больше 420', () {
      final CardImageBudget budget = CardImageBudget.side(
        availableHeight: 700,
        columnWidth: 1800,
        sideBySide: true,
      );
      expect(budget.maxWidth, 420);
      expect(budget.maxHeight, 700);
    });

    test('неизвестная высота/ширина не даёт NaN и не ломает слот', () {
      final CardImageBudget budget = CardImageBudget.side(
        availableHeight: double.infinity,
        columnWidth: double.infinity,
        sideBySide: false,
      );
      expect(budget.maxHeight.isFinite, isTrue);
      expect(budget.maxWidth.isFinite, isTrue);
    });
  });
}
