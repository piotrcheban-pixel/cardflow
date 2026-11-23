import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// Итерация 7.19, группа C (редактор): независимые изображения вопроса и
/// ответа — добавление, перенос, порядок, удаление, сохранение.
void main() {
  final Uint8List png = Uint8List.fromList(
    img.encodePng(img.Image(width: 20, height: 16)),
  );

  Card card() => makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Вопрос',
    back: 'Ответ',
    questionMediaIds: const <String>['q1', 'q2'],
    answerMediaIds: const <String>['a1'],
  );

  Future<
    ({FakeCardRepository cards, FakeCardImageGateway gateway, Finder save})
  >
  pumpEditor(WidgetTester tester) async {
    final FakeCardRepository cards = FakeCardRepository(cards: <Card>[card()]);
    final FakeCardImageGateway gateway = FakeCardImageGateway();
    await tester.pumpWidget(
      appWithRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: cards,
          imageGateway: gateway,
          cardMediaRepository: FakeCardMediaRepository(
            bytesById: <String, Uint8List>{'q1': png, 'q2': png, 'a1': png},
            metadataById: <String, MediaMetadata>{
              'q1': const MediaMetadata(provider: 'file'),
              'q2': const MediaMetadata(provider: 'file'),
              'a1': const MediaMetadata(provider: 'file'),
            },
          ),
        ),
        routes: decksRoutes(),
        initialLocation: '/decks/deck-1/cards/card-1/edit',
      ),
    );
    await tester.pumpAndSettle();
    return (
      cards: cards,
      gateway: gateway,
      save: find.byKey(const ValueKey<String>('card-form-save')),
    );
  }

  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
  }

  /// Аудит v4: действия с изображением (порядок, перенос, замена, удаление)
  /// живут в меню ⋮ — перед тапом по ключу действие нужно открыть.
  Future<void> openImageActions(
    WidgetTester tester,
    String prefix,
    int index,
  ) async {
    final Finder more = find.byKey(
      ValueKey<String>('card-form-more-$prefix-$index'),
    );
    await scrollTo(tester, more);
    await tester.tap(more);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  Future<void> tapSave(WidgetTester tester, Finder save) async {
    await scrollTo(tester, save);
    await tester.tap(save);
    await tester.pumpAndSettle();
  }

  Future<void> tapAndSave(
    WidgetTester tester,
    Finder target,
    Finder save,
  ) async {
    await scrollTo(tester, target);
    await tester.tap(target);
    await tester.pump();
    await tapSave(tester, save);
  }

  testWidgets('редактор показывает обе независимые коллекции', (tester) async {
    await pumpEditor(tester);

    expect(
      find.byKey(const ValueKey<String>('card-form-question-images')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-form-answer-images')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-form-question-image-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-form-answer-image-0')),
      findsOneWidget,
    );
  });

  testWidgets('C22/C23/C24: независимое добавление на обе стороны', (
    tester,
  ) async {
    final editor = await pumpEditor(tester);
    editor.gateway.result = CardImageUpload(
      fileName: 'new.png',
      mimeType: 'image/png',
      bytes: png,
    );

    final addAnswer = find.byKey(
      const ValueKey<String>('card-form-add-answer-image'),
    );
    await scrollTo(tester, addAnswer);
    await tester.tap(addAnswer);
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('card-form-answer-image-1')),
      findsOneWidget,
    );

    await tapSave(tester, editor.save);
    final CardDraft draft = editor.cards.updatedDrafts.last;
    expect(draft.answerUploads, hasLength(1));
    expect(draft.questionUploads, isEmpty);
    expect(draft.answerMediaIds, <String>['a1']);
  });

  testWidgets('C25: перенос изображения на другую сторону', (tester) async {
    final editor = await pumpEditor(tester);

    await openImageActions(tester, 'question', 0);
    await tapAndSave(
      tester,
      find.byKey(const ValueKey<String>('card-form-move-question-0')),
      editor.save,
    );
    final CardDraft draft = editor.cards.updatedDrafts.last;
    expect(draft.questionMediaIds, <String>['q2']);
    expect(draft.answerMediaIds, <String>['a1', 'q1']);
  });

  testWidgets('C26: изменение порядка внутри стороны', (tester) async {
    final editor = await pumpEditor(tester);

    await openImageActions(tester, 'question', 0);
    await tapAndSave(
      tester,
      find.byKey(const ValueKey<String>('card-form-move-down-question-0')),
      editor.save,
    );
    final CardDraft draft = editor.cards.updatedDrafts.last;
    expect(draft.questionMediaIds, <String>['q2', 'q1']);
  });

  testWidgets('C27: удаление изображения стороны ответа', (tester) async {
    final editor = await pumpEditor(tester);

    await openImageActions(tester, 'answer', 0);
    await tapAndSave(
      tester,
      find.byKey(const ValueKey<String>('card-form-remove-answer-0')),
      editor.save,
    );
    final CardDraft draft = editor.cards.updatedDrafts.last;
    expect(draft.answerMediaIds, isEmpty);
    expect(draft.questionMediaIds, <String>['q1', 'q2']);
  });

  testWidgets('C28: сохранение сохраняет обе стороны независимо', (
    tester,
  ) async {
    final editor = await pumpEditor(tester);
    await tapSave(tester, editor.save);
    final CardDraft draft = editor.cards.updatedDrafts.last;
    expect(draft.questionMediaIds, <String>['q1', 'q2']);
    expect(draft.answerMediaIds, <String>['a1']);
  });
}

