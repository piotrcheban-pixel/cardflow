import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_media_repository.dart';
import 'package:cardflow/data/cards/media_garbage_collector.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';

import '../db/test_support.dart';

void main() {
  late AppDatabase db;
  late Directory temp;
  late MediaStore store;

  setUp(() async {
    db = AppDatabase.inMemory();
    temp = Directory.systemTemp.createTempSync('cardflow_media_read_');
    store = MediaStore(temp);
    await insertDeckRow(db, id: 'deck-1', name: 'Колода', createdAt: 1, updatedAt: 1);
    await insertCardRow(db, id: 'card-1', deckId: 'deck-1', mediaJson: '["media-1"]');
    await store.writeMedia(
      relativePath: 'media/media-1.png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );
    await db.into(db.media).insert(
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

    final result = await repository.readMedia(<String>['media-1', 'missing', 'media-1']);

    expect(result.keys, <String>['media-1']);
    expect(result['media-1'], Uint8List.fromList(<int>[1, 2, 3]));
  });

  test('MediaStore.listMedia возвращает относительные пути без временных файлов', () async {
    File('${temp.path}/media/.cardflow-tmp-1').writeAsBytesSync(<int>[9]);
    File('${temp.path}/outside.txt').writeAsBytesSync(<int>[8]);

    expect(await store.listMedia(), <String>['media/media-1.png']);
  });

  test('GC удаляет сирот, но сохраняет связанные медиа и файлы вне media/', () async {
    await store.writeMedia(
      relativePath: 'media/orphan.png',
      bytes: Uint8List.fromList(<int>[4]),
    );
    await db.into(db.media).insert(
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
    expect((await db.select(db.media).get()).map((row) => row.id), <String>['media-1']);
    expect(File('${temp.path}/outside.txt').existsSync(), isTrue);
  });
}
