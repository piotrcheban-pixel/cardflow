import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/cards/media_garbage_collector.dart';
import 'package:cardflow/data/cards/placeholder_media_purger.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/transfer/drift_deck_transfer_service.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_job.dart';

import '../data/db/test_support.dart';

/// Итерация 7.19: хранение изображений по сторонам (`media_json` v2),
/// пурж заглушек, GC, экспорт/импорт и восстановление после перезапуска.
void main() {
  late AppDatabase db;
  late Directory root;
  late MediaStore store;

  final Uint8List png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
  ]);

  CardImageUpload upload(String mime, Uint8List bytes) =>
      CardImageUpload(fileName: 'image', mimeType: mime, bytes: bytes);

  setUp(() async {
    db = AppDatabase.inMemory();
    root = Directory.systemTemp.createTempSync('cardflow_7_19_data_');
    store = MediaStore(root);
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
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  Map<String, Object?> sidesOf(String mediaJson) {
    final Object? decoded = jsonDecode(mediaJson);
    if (decoded is List) return <String, Object?>{'legacy': decoded};
    return (decoded! as Map).cast<String, Object?>();
  }

  group('DriftCardRepository: независимые стороны', () {
    test('createCards пишет обе коллекции и файлы', () async {
      final repository = DriftCardRepository(db, mediaStore: store);
      final List<Card> created = await repository.createCards(
        deckId: 'deck-1',
        draft: CardDraft(
          front: 'Вопрос',
          back: 'Ответ',
          questionUploads: <CardImageUpload>[upload('image/png', png)],
          answerUploads: <CardImageUpload>[
            upload('image/png', png),
            upload('image/png', png),
          ],
        ),
        now: DateTime.utc(2026, 11, 21, 12),
      );

      final Card card = created.single;
      expect(card.questionMediaIds, hasLength(1));
      expect(card.answerMediaIds, hasLength(2));
      expect((await db.select(db.media).get()), hasLength(3));

      final CardRow row = (await db.select(db.cards).get()).single;
      final Map<String, Object?> sides = sidesOf(row.mediaJson);
      expect(sides['version'], 2);
      expect(sides['question'], <Object?>[card.questionMediaIds.single]);
      expect(sides['answer'], card.answerMediaIds);
      for (final String id in card.mediaIds) {
        expect(
          await store.readMedia(
            (await (db.select(
              db.media,
            )..where((table) => table.id.equals(id))).getSingle()).path,
          ),
          isNotNull,
        );
      }
    });

    test(
      'updateCard переносит изображение между сторонами и удаляет',
      () async {
        final repository = DriftCardRepository(db, mediaStore: store);
        final Card card = (await repository.createCards(
          deckId: 'deck-1',
          draft: CardDraft(
            front: 'Вопрос',
            back: 'Ответ',
            questionUploads: <CardImageUpload>[upload('image/png', png)],
            answerUploads: <CardImageUpload>[upload('image/png', png)],
          ),
          now: DateTime.utc(2026, 11, 21, 12),
        )).single;

        final Card updated = await repository.updateCard(
          card: card,
          draft: CardDraft(
            front: card.front,
            back: card.back,
            questionMediaIds: card.answerMediaIds,
            answerMediaIds: card.questionMediaIds,
          ),
          now: DateTime.utc(2026, 11, 21, 13),
        );

        expect(updated.questionMediaIds, card.answerMediaIds);
        expect(updated.answerMediaIds, card.questionMediaIds);
        final CardRow row = (await db.select(db.cards).get()).single;
        expect(sidesOf(row.mediaJson)['question'], card.answerMediaIds);
        expect(sidesOf(row.mediaJson)['answer'], card.questionMediaIds);

        final Card removed = await repository.updateCard(
          card: updated,
          draft: CardDraft(
            front: card.front,
            back: card.back,
            questionMediaIds: updated.questionMediaIds,
          ),
          now: DateTime.utc(2026, 11, 21, 14),
        );
        expect(removed.answerMediaIds, isEmpty);
        expect((await db.select(db.media).get()), hasLength(1));
      },
    );

    test(
      'старая строка media_json (массив) читается как сторона вопроса',
      () async {
        await insertCardRow(
          db,
          id: 'card-old',
          deckId: 'deck-1',
          mediaJson: '["m1","m2"]',
          createdAt: 1,
          updatedAt: 1,
        );
        final CardRepository repository = DriftCardRepository(
          db,
          mediaStore: store,
        );
        final Card card = (await repository.cardById('card-old'))!;
        expect(card.questionMediaIds, <String>['m1', 'm2']);
        expect(card.answerMediaIds, isEmpty);
        expect(card.mediaIds, <String>['m1', 'm2']);
      },
    );
  });

  group('GC и импорт генерации', () {
    test('GC сохраняет медиа обеих сторон и удаляет сирот', () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        mediaJson: '{"version":2,"question":["q1"],"answer":["a1"]}',
        createdAt: 1,
        updatedAt: 1,
      );
      for (final id in <String>['q1', 'a1', 'ghost']) {
        await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(
                id: id,
                cardId: 'card-1',
                path: 'media/$id.png',
                mimeType: 'image/png',
                size: 4,
              ),
            );
      }
      final int deleted = await MediaGarbageCollector(db, store).collect();
      final List<String> left = (await db.select(db.media).get())
          .map((MediaRow row) => row.id)
          .toList();
      expect(left..sort(), <String>['a1', 'q1']);
      expect(deleted, greaterThanOrEqualTo(1));
    });

    test(
      'импорт генерации пишет questionImages и answerImages по сторонам',
      () async {
        final jobs = DriftGenerationJobRepository(db);
        await jobs.save(
          GenerationJob(
            id: 'job-1',
            status: GenerationJobStatus.done,
            createdAt: DateTime.utc(2026, 11, 21, 12),
          ),
        );
        final generationStore = DriftGenerationCardStore(db, mediaStore: store);
        final GeneratedCard card = GeneratedCard(
          front: 'Вопрос',
          back: 'Ответ',
          cardType: CardType.basic,
          questionImages: <GeneratedCardImage>[
            GeneratedCardImage(
              bytes: png,
              mediaType: AttachmentMediaType.png,
              query: 'scheme',
              provider: 'file',
            ),
          ],
          answerImages: <GeneratedCardImage>[
            GeneratedCardImage(
              bytes: png,
              mediaType: AttachmentMediaType.png,
              query: 'formula',
              provider: 'file',
            ),
          ],
        );
        await generationStore.importGeneratedCards(
          deckId: 'deck-1',
          deckName: 'Колода',
          cards: <GeneratedCard>[card],
          jobId: 'job-1',
          now: DateTime.utc(2026, 11, 21, 12),
        );

        final CardRow row = (await db.select(db.cards).get()).single;
        final Map<String, Object?> sides = sidesOf(row.mediaJson);
        expect(sides['question'], hasLength(1));
        expect(sides['answer'], hasLength(1));
        expect(sides['question'], isNot(sides['answer']));
        expect((await db.select(db.media).get()), hasLength(2));
      },
    );
  });

  group('PlaceholderMediaPurger', () {
    test('удаляет заглушки обеих сторон и не трогает настоящие', () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        mediaJson: '{"version":2,"question":["real","ph"],"answer":["ph2"]}',
        createdAt: 1,
        updatedAt: 1,
      );
      final Map<String, bool> flags = <String, bool>{
        'real': false,
        'ph': true,
        'ph2': true,
      };
      for (final MapEntry<String, bool> entry in flags.entries) {
        final String id = entry.key;
        final String path = 'media/$id.png';
        await store.writeMedia(relativePath: path, bytes: png);
        await store.writeMetadata(
          relativePath: path,
          metadata: MediaMetadata(
            provider: entry.value ? 'placeholder' : 'wikimedia',
            isPlaceholder: entry.value,
            query: 'q',
          ),
        );
        await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(
                id: id,
                cardId: 'card-1',
                path: path,
                mimeType: 'image/png',
                size: png.length,
              ),
            );
      }

      final int purged = await PlaceholderMediaPurger(db, store).purge();

      expect(purged, 2);
      expect(
        (await db.select(db.media).get()).map((MediaRow row) => row.id),
        <String>['real'],
      );
      final CardRow row = (await db.select(db.cards).get()).single;
      final Map<String, Object?> sides = sidesOf(row.mediaJson);
      expect(sides['question'], <Object?>['real']);
      expect(sides['answer'], isEmpty);
      expect(File('${root.path}/media/ph.png').existsSync(), isFalse);
      expect(File('${root.path}/media/real.png').existsSync(), isTrue);
    });

    test('старый формат: заглушка убирается из массива', () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        mediaJson: '["ph","real"]',
        createdAt: 1,
        updatedAt: 1,
      );
      for (final String id in <String>['ph', 'real']) {
        final String path = 'media/$id.png';
        await store.writeMedia(relativePath: path, bytes: png);
        await store.writeMetadata(
          relativePath: path,
          metadata: MediaMetadata(
            provider: id == 'ph' ? 'placeholder' : 'file',
            isPlaceholder: id == 'ph',
          ),
        );
        await db
            .into(db.media)
            .insert(
              MediaCompanion.insert(
                id: id,
                cardId: 'card-1',
                path: path,
                mimeType: 'image/png',
                size: png.length,
              ),
            );
      }
      await PlaceholderMediaPurger(db, store).purge();
      final CardRow row = (await db.select(db.cards).get()).single;
      final Map<String, Object?> sides = sidesOf(row.mediaJson);
      // Legacy-массив переписывается в v2: настоящий id остаётся у вопроса.
      expect(sides['question'], <Object?>['real']);
      expect(sides['answer'], isEmpty);
    });
  });

  group('Экспорт/импорт и перезапуск', () {
    test('экспорт → импорт сохраняет стороны', () async {
      final repository = DriftCardRepository(db, mediaStore: store);
      await repository.createCards(
        deckId: 'deck-1',
        draft: CardDraft(
          front: 'Вопрос',
          back: 'Ответ',
          questionUploads: <CardImageUpload>[upload('image/png', png)],
          answerUploads: <CardImageUpload>[
            upload('image/png', png),
            upload('image/png', png),
          ],
        ),
        now: DateTime.utc(2026, 11, 21, 12),
      );
      final service = DriftDeckTransferService(
        appDatabase: db,
        codec: const ZipDeckArchiveCodec(),
        mediaStore: store,
      );

      final Uint8List zip = await service.exportDeckZip('deck-1');

      final AppDatabase target = AppDatabase.inMemory();
      final Directory targetRoot = Directory.systemTemp.createTempSync(
        'cardflow_7_19_import_',
      );
      final MediaStore targetStore = MediaStore(targetRoot);
      final DriftDeckTransferService importService = DriftDeckTransferService(
        appDatabase: target,
        codec: const ZipDeckArchiveCodec(),
        mediaStore: targetStore,
      );
      try {
        final result = await importService.importZip(zip, deckName: 'Копия');
        final Card card = (await DriftCardRepository(
          target,
          mediaStore: targetStore,
        ).cardsByDeck(result.deckId)).single;
        expect(card.questionMediaIds, hasLength(1));
        expect(card.answerMediaIds, hasLength(2));
        final CardRow row = (await target.select(target.cards).get()).single;
        expect(sidesOf(row.mediaJson)['version'], 2);
      } finally {
        await target.close();
        if (targetRoot.existsSync()) targetRoot.deleteSync(recursive: true);
      }
    });

    test('после перезапуска приложения стороны восстанавливаются', () async {
      final Directory dbRoot = Directory.systemTemp.createTempSync(
        'cardflow_7_19_restart_',
      );
      final File dbFile = File('${dbRoot.path}/cardflow.sqlite');
      AppDatabase? first;
      AppDatabase? second;
      try {
        first = AppDatabase(NativeDatabase(dbFile));
        await insertDeckRow(
          first,
          id: 'deck-1',
          name: 'Колода',
          createdAt: 1,
          updatedAt: 1,
        );
        final repository = DriftCardRepository(first, mediaStore: store);
        final Card card = (await repository.createCards(
          deckId: 'deck-1',
          draft: CardDraft(
            front: 'Вопрос',
            back: 'Ответ',
            questionUploads: <CardImageUpload>[upload('image/png', png)],
            answerUploads: <CardImageUpload>[upload('image/png', png)],
          ),
          now: DateTime.utc(2026, 11, 21, 12),
        )).single;
        final List<String> questionIds = card.questionMediaIds;
        final List<String> answerIds = card.answerMediaIds;
        await first.close();

        second = AppDatabase(NativeDatabase(dbFile));
        final Card restored = (await DriftCardRepository(
          second,
          mediaStore: store,
        ).cardById(card.id))!;
        expect(restored.questionMediaIds, questionIds);
        expect(restored.answerMediaIds, answerIds);
        final List<MediaRow> rows = await second.select(second.media).get();
        expect(rows, hasLength(2));
        for (final MediaRow row in rows) {
          expect(await store.readMedia(row.path), png);
        }
      } finally {
        await second?.close();
        await first?.close();
        if (dbRoot.existsSync()) dbRoot.deleteSync(recursive: true);
      }
    });
  });
}
