import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/occlusion.dart';

import '../db/test_support.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late MediaStore store;
  late DriftCardRepository repository;
  final now = DateTime.utc(2026, 11, 14, 12);
  final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
  const occlusion = OcclusionDocument(
    masks: <OcclusionMask>[
      OcclusionMask(
        id: 'm1',
        shape: OcclusionShape.ellipse,
        x: 0.1,
        y: 0.2,
        width: 0.3,
        height: 0.4,
      ),
    ],
  );

  setUp(() async {
    db = AppDatabase.inMemory();
    temp = Directory.systemTemp.createTempSync('cardflow_occlusion_');
    store = MediaStore(temp);
    repository = DriftCardRepository(db, mediaStore: store);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
  });

  tearDown(() async {
    await db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  CardImageUpload upload() => CardImageUpload(
    fileName: 'diagram.png',
    mimeType: 'image/png',
    bytes: bytes,
  );

  test(
    'createCards сохраняет файл, media-строку, latex и occlusion_json',
    () async {
      final card = (await repository.createCards(
        deckId: 'deck-1',
        draft: CardDraft(
          front: 'Анатомия',
          back: 'Подпись',
          latex: r'x^2',
          occlusionJson: occlusion.encode(),
          imageUpload: upload(),
        ),
        now: now,
      )).single;

      expect(
        card.mediaIds,
        hasLength(1),
        reason: 'карточка ссылается на новое медиа',
      );
      expect(card.occlusionJson, occlusion.encode());
      expect(card.latex, r'x^2');
      final mediaRows = await db.select(db.media).get();
      expect(mediaRows, hasLength(1));
      expect(mediaRows.single.id, card.mediaIds.single);
      expect(mediaRows.single.cardId, card.id);
      expect(mediaRows.single.mimeType, 'image/png');
      expect(mediaRows.single.size, bytes.length);
      expect(await store.readMedia(mediaRows.single.path), bytes);
      expect(await repository.cardById(card.id), card);
    },
  );

  test('updateCard сохраняет маски и существующую связь media', () async {
    final original = (await repository.createCards(
      deckId: 'deck-1',
      draft: CardDraft(
        front: 'Вопрос',
        back: 'Ответ',
        occlusionJson: occlusion.encode(),
        imageUpload: upload(),
      ),
      now: now,
    )).single;
    const changed = OcclusionDocument(
      masks: <OcclusionMask>[
        OcclusionMask(
          id: 'm2',
          shape: OcclusionShape.rectangle,
          x: 0,
          y: 0,
          width: 1,
          height: 1,
        ),
      ],
    );

    final updated = await repository.updateCard(
      card: original,
      draft: CardDraft(
        front: 'Новый вопрос',
        back: 'Новый ответ',
        mediaIds: original.mediaIds,
        latex: r'y^3',
        occlusionJson: changed.encode(),
      ),
      now: now.add(const Duration(minutes: 1)),
    );

    expect(updated.mediaIds, original.mediaIds);
    expect(updated.occlusionJson, changed.encode());
    expect(updated.latex, r'y^3');
    expect((await db.select(db.media).get()), hasLength(1));
  });

  test('deleteCard удаляет связанные media-строки и файлы', () async {
    final card = (await repository.createCards(
      deckId: 'deck-1',
      draft: CardDraft(
        front: 'Вопрос',
        back: 'Ответ',
        occlusionJson: occlusion.encode(),
        imageUpload: upload(),
      ),
      now: now,
    )).single;
    final path = (await db.select(db.media).get()).single.path;

    await repository.deleteCard(card.id);

    expect(await db.select(db.media).get(), isEmpty);
    expect(await store.readMedia(path), isNull);
  });

  test('ошибка записи файла откатывает карточку и media-строку', () async {
    final blockingFile = File('${temp.path}/not-a-directory')
      ..writeAsBytesSync(<int>[0]);
    final failingRepository = DriftCardRepository(
      db,
      mediaStore: MediaStore(Directory(blockingFile.path)),
    );

    await expectLater(
      failingRepository.createCards(
        deckId: 'deck-1',
        draft: CardDraft(
          front: 'Вопрос',
          back: 'Ответ',
          occlusionJson: occlusion.encode(),
          imageUpload: upload(),
        ),
        now: now,
      ),
      throwsA(isA<FileSystemException>()),
    );
    expect(await db.select(db.cards).get(), isEmpty);
    expect(await db.select(db.media).get(), isEmpty);
  });
}
