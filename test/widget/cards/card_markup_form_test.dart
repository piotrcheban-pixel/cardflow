import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/ui/cards/occlusion_mask_editor.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

void main() {
  Future<FakeCardRepository> pumpForm(
    WidgetTester tester, {
    FakeCardImageGateway? imageGateway,
    FakeCardMediaRepository? mediaRepository,
  }) async {
    final cards = FakeCardRepository();
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: cards,
          imageGateway: imageGateway,
          cardMediaRepository: mediaRepository,
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/new',
      ),
    );
    await tester.pumpAndSettle();
    return cards;
  }

  testWidgets('форма предлагает cloze и сохраняет разметку с пустым back', (
    tester,
  ) async {
    final cards = await pumpForm(tester);

    expect(find.text('С пропусками'), findsOneWidget);
    await tester.ensureVisible(find.text('С пропусками'));
    await tester.tap(find.text('С пропусками'));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('card-form-front')),
      'Столица {{c1::Париж}}',
    );
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts.single.cardType, CardType.cloze);
    expect(cards.createdDrafts.single.back, isEmpty);
  });

  testWidgets('форма содержит рабочий вход выбора изображения', (tester) async {
    await pumpForm(tester);

    expect(
      find.byKey(const ValueKey('card-form-add-question-image')),
      findsOneWidget,
      reason: 'изображение можно прикрепить к карточке любого типа',
    );
  });

  // ADR-028 (итерация 7.12, owner-note): картинка у basic — просто иллюстрация,
  // без обязательных масок.
  testWidgets('basic: картинка без масок сохраняется как иллюстрация', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final gateway = FakeCardImageGateway()
      ..result = CardImageUpload(
        fileName: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(png),
      );
    final cards = await pumpForm(tester, imageGateway: gateway);

    await tester.ensureVisible(
      find.byKey(const ValueKey('card-form-add-question-image')),
    );
    await tester.tap(
      find.byKey(const ValueKey('card-form-add-question-image')),
    );
    await tester.pumpAndSettle();

    expect(gateway.calls, 1);
    expect(
      find.byKey(const ValueKey('card-form-question-image-0')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('occlusion-editor-canvas')),
      findsNothing,
      reason: 'маски не включаются принудительно',
    );

    await tester.enterText(
      find.byKey(const ValueKey('card-form-front')),
      'Что это?',
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-form-back')),
      'Московский Кремль',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('card-form-save')));
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts, hasLength(1));
    final draft = cards.createdDrafts.single;
    expect(draft.questionUploads.single, same(gateway.result));
    expect(draft.occlusionJson, isNull);
    expect(draft.cardType, CardType.basic);
  });

  testWidgets('cloze: изображение прикрепляется без масок', (tester) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final gateway = FakeCardImageGateway()
      ..result = CardImageUpload(
        fileName: 'photo.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(png),
      );
    final cards = await pumpForm(tester, imageGateway: gateway);

    await tester.ensureVisible(find.text('С пропусками'));
    await tester.tap(find.text('С пропусками'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(
      find.byKey(const ValueKey('card-form-add-question-image')),
    );
    await tester.tap(
      find.byKey(const ValueKey('card-form-add-question-image')),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('card-form-front')),
      'Столица {{c1::Париж}}',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('card-form-save')));
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts, hasLength(1));
    final draft = cards.createdDrafts.single;
    expect(draft.cardType, CardType.cloze);
    expect(draft.questionUploads.single, same(gateway.result));
    expect(draft.occlusionJson, isNull);
    expect(
      find.byKey(const ValueKey('card-form-occlusion-toggle')),
      findsNothing,
      reason: 'маски доступны только basic',
    );
  });

  testWidgets('выбор изображения, включение масок, рисование и сохранение', (
    tester,
  ) async {
    final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
      '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
    );
    final gateway = FakeCardImageGateway()
      ..result = CardImageUpload(
        fileName: 'scheme.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(png),
      );
    final cards = await pumpForm(tester, imageGateway: gateway);

    await tester.ensureVisible(
      find.byKey(const ValueKey('card-form-add-question-image')),
    );
    await tester.tap(
      find.byKey(const ValueKey('card-form-add-question-image')),
    );
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
    expect(find.byKey(const ValueKey('occlusion-editor-canvas')), findsNothing);

    await tester.ensureVisible(
      find.byKey(const ValueKey('card-form-occlusion-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('card-form-occlusion-toggle')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('occlusion-editor-canvas')),
      findsOneWidget,
    );
    // Жест рисования изолированно проверен occlusion_editor_test; здесь —
    // проводка документа редактора в сохраняемый черновик формы.
    final editor = tester.widget<OcclusionMaskEditor>(
      find.byType(OcclusionMaskEditor),
    );
    editor.onChanged(
      const OcclusionDocument(
        masks: <OcclusionMask>[
          OcclusionMask(
            id: 'mask-1',
            shape: OcclusionShape.rectangle,
            x: 0.1,
            y: 0.1,
            width: 0.3,
            height: 0.2,
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('occlusion-editor-mask-mask-1')),
      findsOneWidget,
    );

    await tester.enterText(
      find.byKey(const ValueKey('card-form-front')),
      'Схема',
    );
    await tester.enterText(
      find.byKey(const ValueKey('card-form-back')),
      'Ответ',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('card-form-save')));
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    expect(cards.createdDrafts, hasLength(1));
    final draft = cards.createdDrafts.single;
    expect(draft.questionUploads.single, same(gateway.result));
    expect(draft.occlusionJson, isNotNull);
    expect(draft.occlusionJson, contains('"masks":[{'));
    expect(draft.occlusionJson, contains('"shape":"rectangle"'));
  });

  testWidgets(
    'недоступный файл изображения не стирает существующую occlusion-разметку',
    (tester) async {
      const raw =
          '{"version":1,"masks":[{"id":"m1","shape":"rectangle",'
          '"x":0.1,"y":0.1,"width":0.2,"height":0.2}]}';
      final card = makeCard(
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Схема',
        mediaIds: const <String>['media-1'],
        occlusionJson: raw,
      );
      final cards = FakeCardRepository(cards: <Card>[card]);
      await tester.pumpWidget(
        appWithRouter(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(),
            cardRepository: cards,
            cardMediaRepository: FakeCardMediaRepository(),
          ),
          routes: decksRoutes(),
          initialLocation: '/decks/deck-1/cards/card-1/edit',
        ),
      );
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey('card-form-front')),
        'Новая схема',
      );
      await tester.tap(find.byKey(const ValueKey('card-form-save')));
      await tester.pumpAndSettle();

      final draft = cards.updatedDrafts.single;
      expect(draft.occlusionJson, raw);
      expect(draft.mediaIds, <String>['media-1']);
    },
  );

  testWidgets(
    'cloze без пропуска показывает отдельную ошибку и не сохраняется',
    (tester) async {
      final cards = await pumpForm(tester);
      await tester.ensureVisible(find.text('С пропусками'));
      await tester.tap(find.text('С пропусками'));
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('card-form-front')),
        'Обычный текст',
      );
      await tester.tap(find.byKey(const ValueKey('card-form-save')));
      await tester.pump();

      expect(find.text('Добавьте хотя бы один пропуск'), findsOneWidget);
      expect(cards.createdDrafts, isEmpty);
    },
  );

  // ADR-028: у старой occlusion-карточки маски можно выключить, картинка
  // останется иллюстрацией.
  testWidgets('редактирование occlusion: выключение масок сохраняет картинку', (
    tester,
  ) async {
    const raw =
        '{"version":1,"masks":[{"id":"m1","shape":"rectangle",'
        '"x":0.1,"y":0.1,"width":0.2,"height":0.2}]}';
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final card = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Схема',
      mediaIds: const <String>['media-1'],
      occlusionJson: raw,
    );
    final cards = FakeCardRepository(cards: <Card>[card]);
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: cards,
          cardMediaRepository: FakeCardMediaRepository(
            bytesById: <String, Uint8List>{'media-1': png},
          ),
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/card-1/edit',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('occlusion-editor-canvas')),
      findsOneWidget,
      reason: 'старая occlusion-карточка открывается с масками',
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('card-form-occlusion-toggle')),
    );
    await tester.tap(find.byKey(const ValueKey('card-form-occlusion-toggle')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('occlusion-editor-canvas')), findsNothing);
    expect(
      find.byKey(const ValueKey('card-form-question-image-0')),
      findsOneWidget,
      reason: 'картинка остаётся на карточке',
    );

    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    final draft = cards.updatedDrafts.single;
    expect(draft.occlusionJson, isNull);
    expect(draft.mediaIds, <String>['media-1']);
  });

  testWidgets('удаление изображения снимает media у карточки', (tester) async {
    final png = Uint8List.fromList(
      base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      ),
    );
    final card = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'С картинкой',
      mediaIds: const <String>['media-1'],
    );
    final cards = FakeCardRepository(cards: <Card>[card]);
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: cards,
          cardMediaRepository: FakeCardMediaRepository(
            bytesById: <String, Uint8List>{'media-1': png},
          ),
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/card-1/edit',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('card-form-question-image-0')),
      findsOneWidget,
    );
    await tester.ensureVisible(
      find.byKey(const ValueKey('card-form-remove-question-0')),
    );
    await tester.tap(find.byKey(const ValueKey('card-form-remove-question-0')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('card-form-question-image-0')),
      findsNothing,
    );
    await tester.tap(find.byKey(const ValueKey('card-form-save')));
    await tester.pumpAndSettle();

    final draft = cards.updatedDrafts.single;
    expect(draft.mediaIds, isEmpty);
    expect(draft.questionUploads, isEmpty);
  });
}
