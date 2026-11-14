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

  testWidgets('форма содержит рабочий вход выбора occlusion-изображения', (
    tester,
  ) async {
    await pumpForm(tester);

    expect(
      find.byKey(const ValueKey('card-form-pick-image')),
      findsOneWidget,
      reason: 'без выбора изображения редактор масок недоступен пользователю',
    );
  });

  testWidgets('выбор изображения, рисование маски и сохранение occlusion', (
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
      find.byKey(const ValueKey('card-form-pick-image')),
    );
    await tester.tap(find.byKey(const ValueKey('card-form-pick-image')));
    await tester.pumpAndSettle();
    expect(gateway.calls, 1);
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
    expect(draft.imageUpload, same(gateway.result));
    expect(draft.occlusionJson, isNotNull);
    expect(draft.occlusionJson, contains('"masks":[{'));
    expect(draft.occlusionJson, contains('"shape":"rectangle"'));
  });

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
}
