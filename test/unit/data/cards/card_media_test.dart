import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_media_repository.dart';
import 'package:cardflow/data/cards/media_garbage_collector.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';

import '../db/test_support.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late MediaStore store;

  setUp(() async {
    db = AppDatabase.inMemory();
    temp = Directory.systemTemp.createTempSync('cardflow_media_read_');
    store = MediaStore(temp);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      mediaJson: '["media-1"]',
    );
    await store.writeMedia(
      relativePath: 'media/media-1.png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    await db
        .into(db.media)
        .insert(
          const MediaCompanion(
            id: Value('media-1'),
            cardId: Value('card-1'),
            path: Value('media/media-1.png'),
            mimeType: Value('image/png'),
            size: Value(3),
          ),
        );
  });

  tearDown(() async {
    await db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('репозиторий читает только существующие байты по media.id', () async {
    final repository = DriftCardMediaRepository(db, store);

    final result = await repository.readMedia(<String>[
      'media-1',
      'missing',
      'media-1',
    ]);

    expect(result.keys, <String>['media-1']);
    expect(result['media-1'], Uint8List.fromList(<int>[1, 2, 3]));
  });

  test(
    'MediaStore.listMedia возвращает относительные пути без временных файлов',
    () async {
      File('${temp.path}/media/.cardflow-tmp-1').writeAsBytesSync(<int>[9]);
      File('${temp.path}/outside.txt').writeAsBytesSync(<int>[8]);

      expect(await store.listMedia(), <String>['media/media-1.png']);
    },
  );

  test('метаданные медиа: запись/чтение и побочный файл', () async {
    await store.writeMetadata(
      relativePath: 'media/media-1.png',
      metadata: const MediaMetadata(
        provider: 'wikimedia',
        sourceUrl: 'https://upload.wikimedia.org/a.jpg',
        author: 'Иван Петров',
        license: 'CC BY-SA 4.0',
        isPlaceholder: true,
        query: 'truss bridge',
        fallbackQuery: 'truss',
        kind: GeneratedCardImageKind.diagram,
      ),
    );

    final metadata = await store.readMetadata('media/media-1.png');
    expect(metadata, isNotNull);
    expect(metadata!.provider, 'wikimedia');
    expect(metadata.sourceUrl, contains('wikimedia'));
    expect(metadata.author, 'Иван Петров');
    expect(metadata.license, 'CC BY-SA 4.0');
    expect(metadata.isPlaceholder, isTrue);
    expect(metadata.query, 'truss bridge');
    expect(metadata.fallbackQuery, 'truss');
    expect(metadata.kind, GeneratedCardImageKind.diagram);
    expect(metadata.attributionLine, 'Иван Петров · CC BY-SA 4.0');
    expect(
      File('${temp.path}/media/media-1.png.meta.json').existsSync(),
      isTrue,
    );
    expect(await store.listMedia(), <String>['media/media-1.png']);
    expect(await store.listMetadata(), <String>['media/media-1.png.meta.json']);
  });

  test('метаданные: битый JSON и версия новее → null', () async {
    final file = File('${temp.path}/media/media-1.png.meta.json');
    file.writeAsStringSync('{битый json');
    expect(await store.readMetadata('media/media-1.png'), isNull);
    file.writeAsStringSync('{"version": 99, "provider": "x"}');
    expect(await store.readMetadata('media/media-1.png'), isNull);
    file.deleteSync();
    expect(await store.readMetadata('media/media-1.png'), isNull);
  });

  test('удаление медиа удаляет и метаданные', () async {
    await store.writeMetadata(
      relativePath: 'media/media-1.png',
      metadata: const MediaMetadata(provider: 'file'),
    );
    await store.deleteMedia('media/media-1.png');
    expect(await store.readMedia('media/media-1.png'), isNull);
    expect(
      File('${temp.path}/media/media-1.png.meta.json').existsSync(),
      isFalse,
    );
  });

  test(
    'GC удаляет сирот, но сохраняет связанные медиа и файлы вне media/',
    () async {
      File('${temp.path}/outside.txt').writeAsBytesSync(<int>[8]);
      await store.writeMedia(
        relativePath: 'media/orphan.png',
        bytes: Uint8List.fromList(<int>[4]),
      );
      await db
          .into(db.media)
          .insert(
            const MediaCompanion(
              id: Value('orphan-row'),
              cardId: Value('deleted-card'),
              path: Value('media/orphan-row.png'),
              mimeType: Value('image/png'),
              size: Value(1),
            ),
          );
      await store.writeMedia(
        relativePath: 'media/orphan-row.png',
        bytes: Uint8List.fromList(<int>[5]),
      );

      final deleted = await MediaGarbageCollector(db, store).collect();

      expect(deleted, 3, reason: 'два файла-сироты и одна строка без карточки');
      expect(await store.readMedia('media/media-1.png'), isNotNull);
      expect(await store.readMedia('media/orphan.png'), isNull);
      expect(await store.readMedia('media/orphan-row.png'), isNull);
      expect((await db.select(db.media).get()).map((row) => row.id), <String>[
        'media-1',
      ]);
      expect(File('${temp.path}/outside.txt').existsSync(), isTrue);
    },
  );

  test('GC сохраняет метаданные живого медиа и удаляет сиротские', () async {
    await store.writeMetadata(
      relativePath: 'media/media-1.png',
      metadata: const MediaMetadata(provider: 'wikimedia'),
    );
    await store.writeMetadata(
      relativePath: 'media/ghost.png',
      metadata: const MediaMetadata(provider: 'openverse'),
    );
    await store.writeMedia(
      relativePath: 'media/orphan.png',
      bytes: Uint8List.fromList(<int>[4]),
    );
    await store.writeMetadata(
      relativePath: 'media/orphan.png',
      metadata: const MediaMetadata(provider: 'pexels'),
    );

    final deleted = await MediaGarbageCollector(db, store).collect();

    expect(
      deleted,
      2,
      reason: 'файл-сирота (с метаданными) и осиротевшие метаданные ghost',
    );
    expect(await store.readMetadata('media/media-1.png'), isNotNull);
    expect(
      File('${temp.path}/media/orphan.png.meta.json').existsSync(),
      isFalse,
    );
    expect(
      File('${temp.path}/media/ghost.png.meta.json').existsSync(),
      isFalse,
    );
  });
}
