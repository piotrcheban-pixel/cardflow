import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/media_integrity_checker.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/image_bytes.dart';

import '../data/db/test_support.dart';

/// Итерация 7.19: целостность медиа (пустые/повреждённые байты, MIME,
/// дубликаты, отсутствующие файлы) и запрет маскировки ошибок.
void main() {
  final Uint8List png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    1,
    2,
    3,
    4,
  ]);
  final Uint8List jpeg = Uint8List.fromList(<int>[
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    1,
    2,
    3,
    4,
  ]);

  group('ImageBytes: сигнатуры и MIME', () {
    test('распознаёт PNG и JPEG по сигнатуре', () {
      expect(sniffImageFormat(png), ImageFormat.png);
      expect(sniffImageFormat(jpeg), ImageFormat.jpeg);
      expect(sniffImageFormat(<int>[1, 2, 3]), ImageFormat.unknown);
      expect(sniffImageFormat(const <int>[]), ImageFormat.unknown);
    });

    test('пустые байты отклоняются (A7)', () {
      expect(isSupportedImageBytes(const <int>[]), isFalse);
      expect(isSupportedImageBytes(<int>[0x89, 0x50]), isFalse);
      expect(isSupportedImageBytes(png), isTrue);
    });

    test('MIME из ответа сверяется с сигнатурой (A8)', () {
      expect(imageBytesMatchMediaType(png, AttachmentMediaType.png), isTrue);
      expect(imageBytesMatchMediaType(png, AttachmentMediaType.jpeg), isFalse);
      expect(imageBytesMatchMediaType(jpeg, AttachmentMediaType.jpeg), isTrue);
    });
  });

  group('Импорт генерации: повреждённые изображения не сохраняются', () {
    late AppDatabase db;
    late Directory root;
    late MediaStore store;

    setUp(() async {
      db = AppDatabase.inMemory();
      root = Directory.systemTemp.createTempSync('cardflow_7_19_integrity_');
      store = MediaStore(root);
      await insertDeckRow(
        db,
        id: 'deck-1',
        name: 'Колода',
        createdAt: 1,
        updatedAt: 1,
      );
      await DriftGenerationJobRepository(db).save(
        GenerationJob(
          id: 'job-1',
          status: GenerationJobStatus.done,
          createdAt: DateTime.utc(2026, 11, 21),
        ),
      );
    });

    tearDown(() async {
      await db.close();
      if (root.existsSync()) root.deleteSync(recursive: true);
    });

    Future<GenerationImportResult> importImage(Uint8List bytes) {
      return DriftGenerationCardStore(
        db,
        mediaStore: store,
      ).importGeneratedCards(
        deckId: 'deck-1',
        deckName: 'Колода',
        cards: <GeneratedCard>[
          GeneratedCard(
            front: 'Вопрос',
            back: 'Ответ',
            cardType: CardType.basic,
            questionImages: <GeneratedCardImage>[
              GeneratedCardImage(
                bytes: bytes,
                mediaType: AttachmentMediaType.png,
                query: 'scheme',
                provider: 'file',
              ),
            ],
          ),
        ],
        jobId: 'job-1',
        now: DateTime.utc(2026, 11, 21, 12),
      );
    }

    test('пустые байты не создают медиа (A7)', () async {
      await importImage(Uint8List(0));
      expect(await db.select(db.media).get(), isEmpty);
      final CardRow row = (await db.select(db.cards).get()).single;
      expect(row.mediaJson, anyOf('[]', contains('"question":[]')));
    });

    test('байты с неверной сигнатурой не создают медиа (A8)', () async {
      await importImage(Uint8List.fromList(<int>[1, 2, 3, 4, 5]));
      expect(await db.select(db.media).get(), isEmpty);
    });
  });

  group('MediaIntegrityChecker', () {
    late AppDatabase db;
    late Directory root;
    late MediaStore store;

    setUp(() async {
      db = AppDatabase.inMemory();
      root = Directory.systemTemp.createTempSync('cardflow_7_19_check_');
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

    Future<void> insertMedia({
      required String id,
      required String cardId,
      required String path,
      String mime = 'image/png',
      Uint8List? bytes,
      MediaMetadata? metadata,
    }) async {
      if (bytes != null) {
        await store.writeMedia(relativePath: path, bytes: bytes);
      }
      if (metadata != null) {
        await store.writeMetadata(relativePath: path, metadata: metadata);
      }
      await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              id: id,
              cardId: cardId,
              path: path,
              mimeType: mime,
              size: bytes?.length ?? 0,
            ),
          );
    }

    test('чистая база: все записи ok, отчёт без бинарных данных', () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        mediaJson: '{"version":2,"question":["q1"],"answer":["a1"]}',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertMedia(
        id: 'q1',
        cardId: 'card-1',
        path: 'media/q1.png',
        bytes: png,
        metadata: const MediaMetadata(provider: 'file'),
      );
      await insertMedia(
        id: 'a1',
        cardId: 'card-1',
        path: 'media/a1.png',
        bytes: jpeg,
        mime: 'image/jpeg',
        metadata: const MediaMetadata(provider: 'wikimedia'),
      );

      final MediaIntegrityReport report = await MediaIntegrityChecker(
        db,
        store,
      ).check();

      expect(report.isClean, isTrue);
      expect(report.entries, hasLength(2));
      expect(
        report.entries.map((MediaIntegrityEntry entry) => entry.side).toSet(),
        <CardMediaSide>{CardMediaSide.question, CardMediaSide.answer},
      );
      expect(report.entries.first.digest, isNotNull);
      expect(report.toString(), isNot(contains('89 50 4E 47')));
    });

    test('находит отсутствующий файл, пустой файл и неверный MIME', () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        mediaJson: '{"version":2,"question":["missing","empty"],"answer":["mismatch"]}',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertMedia(
        id: 'missing',
        cardId: 'card-1',
        path: 'media/missing.png',
      );
      await insertMedia(
        id: 'empty',
        cardId: 'card-1',
        path: 'media/empty.png',
        bytes: Uint8List(0),
      );
      await insertMedia(
        id: 'mismatch',
        cardId: 'card-1',
        path: 'media/mismatch.jpg',
        mime: 'image/png',
        bytes: jpeg,
      );

      final MediaIntegrityReport report = await MediaIntegrityChecker(
        db,
        store,
      ).check();

      expect(report.isClean, isFalse);
      expect(report.statusOf('missing'), MediaIntegrityStatus.missingFile);
      expect(report.statusOf('empty'), MediaIntegrityStatus.emptyFile);
      expect(report.statusOf('mismatch'), MediaIntegrityStatus.mimeMismatch);
    });

    test('находит заглушку, дубликаты байтов и чужого владельца', () async {
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        mediaJson: '{"version":2,"question":["ph"],"answer":["foreign"]}',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertCardRow(
        db,
        id: 'card-2',
        deckId: 'deck-1',
        mediaJson: '{"version":2,"question":["same"],"answer":[]}',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertMedia(
        id: 'ph',
        cardId: 'card-1',
        path: 'media/ph.png',
        bytes: png,
        metadata: const MediaMetadata(
          provider: 'placeholder',
          isPlaceholder: true,
        ),
      );
      await insertMedia(
        id: 'foreign',
        cardId: 'card-2',
        path: 'media/foreign.png',
        bytes: png,
      );
      await insertMedia(
        id: 'same',
        cardId: 'card-2',
        path: 'media/same.png',
        bytes: png,
      );

      final MediaIntegrityReport report = await MediaIntegrityChecker(
        db,
        store,
      ).check();

      expect(report.statusOf('ph'), MediaIntegrityStatus.placeholder);
      expect(report.statusOf('foreign'), MediaIntegrityStatus.foreignOwner);
      expect(report.statusOf('same'), MediaIntegrityStatus.duplicateBytes);
      expect(report.problems, isNotEmpty);
    });
  });
}
