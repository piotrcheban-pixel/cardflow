import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/card_image_refresher.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_image_refresh_result.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';

import '../../../helpers/generation_fakes.dart';
import '../db/test_support.dart';

/// Повторный поиск картинки: «Найти заново» и фоновый ретрай заглушек (7.14).
void main() {
  late AppDatabase db;
  late Directory temp;
  late MediaStore store;

  final Uint8List jpeg = Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 1, 2]);

  setUp(() async {
    db = AppDatabase.inMemory();
    temp = Directory.systemTemp.createTempSync('cardflow_image_refresh_');
    store = MediaStore(temp);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
    await insertCardRow(db, id: 'card-1', deckId: 'deck-1');
    await _insertMedia(
      db,
      store,
      id: 'media-1',
      path: 'media/media-1.png',
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
      metadata: const MediaMetadata(
        provider: 'placeholder',
        isPlaceholder: true,
        query: 'truss bridge',
        fallbackQuery: 'truss',
        kind: GeneratedCardImageKind.photo,
      ),
    );
  });

  tearDown(() async {
    await db.close();
    if (temp.existsSync()) temp.deleteSync(recursive: true);
  });

  test('найденная картинка заменяет заглушку и метаданные', () async {
    final finder = FakeCardImageFinder(
      byQuery: <String, GeneratedCardImage?>{
        'truss bridge': makeCardImage(
          query: 'truss bridge',
          bytes: jpeg.toList(),
          kind: GeneratedCardImageKind.photo,
        ),
      },
    );
    final refresher = CardImageRefresher(
      database: db,
      mediaStore: store,
      imageFinder: finder,
    );

    final result = await refresher.refreshMedia('media-1');

    expect(result, CardImageRefreshResult.updated);
    expect(finder.calls.single.query, 'truss bridge');
    expect(finder.calls.single.fallbackQuery, 'truss');
    expect(finder.calls.single.kind, GeneratedCardImageKind.photo);
    expect(await store.readMedia('media/media-1.png'), isNull);
    expect(await store.readMedia('media/media-1.jpg'), isNotNull);
    final row = (await db.select(db.media).get()).single;
    expect(row.path, 'media/media-1.jpg');
    expect(row.mimeType, 'image/jpeg');
    expect(row.size, jpeg.length);
    final metadata = await store.readMetadata('media/media-1.jpg');
    expect(metadata!.isPlaceholder, isFalse);
    expect(metadata.provider, 'wikimedia');
    expect(metadata.query, 'truss bridge');
  });

  test('без сохранённого запроса → noQuery и поиск не вызывается', () async {
    await _insertMedia(
      db,
      store,
      id: 'media-2',
      path: 'media/media-2.png',
      bytes: Uint8List.fromList(<int>[4]),
      metadata: const MediaMetadata(provider: 'placeholder'),
    );
    final finder = FakeCardImageFinder();
    final refresher = CardImageRefresher(
      database: db,
      mediaStore: store,
      imageFinder: finder,
    );

    expect(
      await refresher.refreshMedia('media-2'),
      CardImageRefreshResult.noQuery,
    );
    expect(finder.queries, isEmpty);
  });

  test('неизвестный media.id → missing', () async {
    final refresher = CardImageRefresher(
      database: db,
      mediaStore: store,
      imageFinder: FakeCardImageFinder(),
    );
    expect(
      await refresher.refreshMedia('missing'),
      CardImageRefreshResult.missing,
    );
  });

  test('ничего не нашли → notFound, заглушка остаётся', () async {
    final refresher = CardImageRefresher(
      database: db,
      mediaStore: store,
      imageFinder: FakeCardImageFinder(),
    );

    expect(
      await refresher.refreshMedia('media-1'),
      CardImageRefreshResult.notFound,
    );
    expect(await store.readMedia('media/media-1.png'), isNotNull);
    final metadata = await store.readMetadata('media/media-1.png');
    expect(metadata!.isPlaceholder, isTrue);
  });

  test('ошибка поиска не роняет refreshMedia', () async {
    final finder = FakeCardImageFinder()..error = StateError('offline');
    final refresher = CardImageRefresher(
      database: db,
      mediaStore: store,
      imageFinder: finder,
    );
    expect(
      await refresher.refreshMedia('media-1'),
      CardImageRefreshResult.notFound,
    );
  });
}

Future<void> _insertMedia(
  AppDatabase db,
  MediaStore store, {
  required String id,
  required String path,
  required Uint8List bytes,
  required MediaMetadata metadata,
}) async {
  await store.writeMedia(relativePath: path, bytes: bytes);
  await store.writeMetadata(relativePath: path, metadata: metadata);
  await db
      .into(db.media)
      .insert(
        MediaCompanion(
          id: Value<String>(id),
          cardId: const Value<String>('card-1'),
          path: Value<String>(path),
          mimeType: const Value<String>('image/png'),
          size: Value<int>(bytes.length),
        ),
      );
}
