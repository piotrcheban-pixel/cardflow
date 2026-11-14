import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/occlusion.dart';

void main() {
  const validOcclusion = OcclusionDocument(
    masks: <OcclusionMask>[
      OcclusionMask(
        id: 'm1',
        shape: OcclusionShape.rectangle,
        x: 0.1,
        y: 0.1,
        width: 0.2,
        height: 0.2,
      ),
    ],
  );

  test('cloze без корректного пропуска отклоняется', () {
    const draft = CardDraft(
      front: 'Здесь нет разметки',
      back: '',
      cardType: CardType.cloze,
    );

    expect(draft.validate(), <CardDraftField, CardValidationError>{
      CardDraftField.front: CardValidationError.clozeMissing,
    });
  });

  test('нормализация сохраняет медиа, latex, occlusion и upload', () {
    final upload = CardImageUpload(
      fileName: 'image.png',
      mimeType: 'image/png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    final draft = CardDraft(
      front: '  Вопрос ',
      back: ' Ответ ',
      mediaIds: const <String>['old-media'],
      latex: r'x^2',
      occlusionJson: validOcclusion.encode(),
      imageUpload: upload,
    ).normalized();

    expect(draft.mediaIds, <String>['old-media']);
    expect(draft.latex, r'x^2');
    expect(draft.occlusionJson, validOcclusion.encode());
    expect(draft.imageUpload, same(upload));
  });

  test('occlusion требует изображение, хотя бы одну маску и валидный JSON', () {
    const withoutImage = CardDraft(front: 'В', back: 'О', occlusionJson: '{}');
    expect(
      withoutImage.validate()[CardDraftField.occlusion],
      CardValidationError.occlusionImageMissing,
    );

    const withoutMasks = CardDraft(
      front: 'В',
      back: 'О',
      mediaIds: <String>['media-1'],
      occlusionJson: '{"version":1,"masks":[]}',
    );
    expect(
      withoutMasks.validate()[CardDraftField.occlusion],
      CardValidationError.occlusionMasksMissing,
    );

    const broken = CardDraft(
      front: 'В',
      back: 'О',
      mediaIds: <String>['media-1'],
      occlusionJson: '{broken',
    );
    expect(
      broken.validate()[CardDraftField.occlusion],
      CardValidationError.occlusionInvalid,
    );
  });

  test('валидная occlusion с существующим media.id проходит', () {
    final draft = CardDraft(
      front: 'Вопрос',
      back: 'Ответ',
      mediaIds: const <String>['media-1'],
      occlusionJson: validOcclusion.encode(),
    );
    expect(draft.validate(), isEmpty);
  });
}
