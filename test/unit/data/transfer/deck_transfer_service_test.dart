import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/transfer/drift_deck_transfer_service.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Тесты `DriftDeckTransferService` — экспорт/импорт `.zip` поверх drift-БД
/// (SPEC A6.9, A5; ADR-006, docs/archive-format.md).

const ZipDeckArchiveCodec _codec = ZipDeckArchiveCodec();

final DateTime _deckCreatedAt = DateTime.utc(2026, 11, 1, 8);
final DateTime _deckUpdatedAt = DateTime.utc(2026, 11, 10, 21, 15, 30, 500);
final DateTime _cardCreatedAt = DateTime.utc(2026, 11, 2, 10);
final DateTime _cardUpdatedAt = DateTime.utc(2026, 11, 9, 18, 40, 12, 250);
final DateTime _due = DateTime.utc(2026, 11, 20, 9);
final DateTime _buriedUntil = DateTime.utc(2026, 11, 13, 9);

const Map<String, Object?> _deckSettings = <String, Object?>{
  'retention': 0.9,
  'new_per_day': 20,
  'nested': <String, Object?>{
    'list': <Object?>[1, 'два', true],
  },
};

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

/// Карточка со всеми заполненными полями (кроме sibling).
Card _basicCard({
  String id = 'card-1',
  List<String> mediaIds = const <String>['m-1'],
  String? contentHash,
}) => Card(
  id: id,
  deckId: 'deck-1',
  front: '¿Cómo se dice «говорить»?',
  back: 'hablar',
  hint: 'Глагол движения',
  cardType: CardType.basic,
  tags: const <String>['глагол', 'испанский'],
  mediaIds: mediaIds,
  latex: r'\text{hablar}',
  occlusionJson: '{"masks":[{"x":1}]}',
  sourceDocId: 'doc-1',
  sourceExcerpt: '«Цитата из документа»',
  state: CardState.review,
  fsrsJson: '{"stability":12.5}',
  due: _due,
  suspended: true,
  buriedUntil: _buriedUntil,
  flagged: true,
  contentHash: contentHash,
  createdAt: _cardCreatedAt,
  updatedAt: _cardUpdatedAt,
);

/// Cloze-карточка с большинством пустых полей и пустым медиафайлом.
Card _clozeCard({String id = 'card-2'}) => Card(
  id: id,
  deckId: 'deck-1',
  front: 'Пропуск {{c1::ответ}}',
  back: 'ответ',
  cardType: CardType.cloze,
  tags: const <String>['cloze'],
  mediaIds: const <String>['m-2'],
  state: CardState.newCard,
  createdAt: _cardCreatedAt,
  updatedAt: _cardUpdatedAt,
);

/// Пара `basic_reversed` c взаимными `sibling_id`.
Card _reversedFirst() => Card(
  id: 'card-r1',
  deckId: 'deck-1',
  front: 'Лицевая A',
  back: 'Обратная A',
  cardType: CardType.basicReversed,
  tags: const <String>['пара'],
  state: CardState.learning,
  due: _due,
  siblingId: 'card-r2',
  createdAt: _cardCreatedAt,
  updatedAt: _cardUpdatedAt,
);

Card _reversedSecond() => Card(
  id: 'card-r2',
  deckId: 'deck-1',
  front: 'Лицевая B',
  back: 'Обратная B',
  cardType: CardType.basicReversed,
  state: CardState.learning,
  due: _due,
  siblingId: 'card-r1',
  createdAt: _cardCreatedAt,
  updatedAt: _cardUpdatedAt,
);

List<Card> _sampleCards() => <Card>[
  _basicCard(),
  _clozeCard(),
  _reversedFirst(),
  _reversedSecond(),
];

/// Эффективный `content_hash` карточки (адресное сравнение после импорта).
String _hashOf(Card card) =>
    card.contentHash ?? contentHashOf(front: card.front, back: card.back);

/// Сравнивает контент карточек, игнорируя id/deck_id/sibling/content_hash и
/// конкретные id медиа (они обязаны меняться при импорте).
void _expectSameCardContent(Card actual, Card expected) {
  expect(actual.front, expected.front);
  expect(actual.back, expected.back);
  expect(actual.hint, expected.hint);
  expect(actual.cardType, expected.cardType);
  expect(actual.tags, expected.tags);
  expect(actual.latex, expected.latex);
  expect(actual.occlusionJson, expected.occlusionJson);
  expect(actual.sourceDocId, expected.sourceDocId);
  expect(actual.sourceExcerpt, expected.sourceExcerpt);
  expect(actual.state, expected.state);
  expect(actual.fsrsJson, expected.fsrsJson);
  expect(actual.due, expected.due);
  expect(actual.suspended, expected.suspended);
  expect(actual.buriedUntil, expected.buriedUntil);
  expect(actual.flagged, expected.flagged);
  expect(actual.createdAt, expected.createdAt);
  expect(actual.updatedAt, expected.updatedAt);
  expect(actual.mediaIds, hasLength(expected.mediaIds.length));
}

/// Соответствие ожидаемых байтов медиа (MIME + base64 содержимого).
List<String> _mediaSignatures(List<ArchiveMedia> media) =>
    media
        .map((ArchiveMedia m) => '${m.mimeType}:${base64Encode(m.bytes)}')
        .toList()
      ..sort();

/// Собирает тестовый архив вручную.
DeckArchive _archive({
  required List<Card> cards,
  List<ArchiveMedia> media = const <ArchiveMedia>[],
  ArchiveDeck? deck,
}) => DeckArchive(
  formatVersion: deckArchiveFormatVersion,
  exportedAt: DateTime.utc(2026, 11, 12, 10, 30, 5),
  deck:
      deck ??
      ArchiveDeck(
        id: 'deck-old',
        name: 'Колода из архива',
        settings: _deckSettings,
        createdAt: _deckCreatedAt,
        updatedAt: _deckUpdatedAt,
      ),
  cards: cards,
  media: media,
);

/// Матчер `ArchiveException` с конкретным машинным кодом.
Matcher _throwsArchiveError(ArchiveErrorCode code) => throwsA(
  isA<ArchiveException>().having(
    (ArchiveException error) => error.code,
    'code',
    code,
  ),
);

/// Фейковое хранилище медиа, падающее на N-й записи (проверка отката).
class _FailingMediaStore extends MediaStore {
  _FailingMediaStore(super.rootDirectory);

  /// Номер записи (с 1), на которой нужно бросить ошибку.
  int failOnAttempt = 2;

  int writeAttempts = 0;
  final List<String> writtenPaths = <String>[];

  @override
  Future<void> writeMedia({
    required String relativePath,
    required Uint8List bytes,
  }) async {
    writeAttempts++;
    if (writeAttempts == failOnAttempt) {
      throw const FileSystemException('Диск переполнен (тест)');
    }
    await super.writeMedia(relativePath: relativePath, bytes: bytes);
    writtenPaths.add(relativePath);
  }
}

void main() {
  late AppDatabase db;
  late Directory tempRoot;
  late MediaStore mediaStore;
  late DriftDeckTransferService service;

  /// Вставляет колоду в БД.
  Future<void> insertDeck({
    String id = 'deck-1',
    String name = 'Испанский: базовые глаголы',
    Map<String, Object?> settings = _deckSettings,
    DateTime? archivedAt,
  }) async {
    await db
        .into(db.decks)
        .insert(
          DecksCompanion.insert(
            id: id,
            name: name,
            settingsJson: Value<String>(jsonEncode(settings)),
            archivedAt: Value<int?>(
              archivedAt == null ? null : toEpochMs(archivedAt),
            ),
            createdAt: toEpochMs(_deckCreatedAt),
            updatedAt: toEpochMs(_deckUpdatedAt),
          ),
        );
  }

  /// Вставляет карточку так же, как это делает data-слой.
  Future<void> insertCard(Card card) async {
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            id: card.id,
            deckId: card.deckId,
            front: card.front,
            back: card.back,
            hint: Value<String?>(card.hint),
            cardType: card.cardType.wireName,
            tagsJson: Value<String>(jsonEncode(card.tags)),
            mediaJson: Value<String>(jsonEncode(card.mediaIds)),
            latex: Value<String?>(card.latex),
            occlusionJson: Value<String?>(card.occlusionJson),
            sourceDocId: Value<String?>(card.sourceDocId),
            sourceExcerpt: Value<String?>(card.sourceExcerpt),
            state: card.state.wireName,
            fsrsJson: Value<String?>(card.fsrsJson),
            due: Value<int?>(card.due == null ? null : toEpochMs(card.due!)),
            suspended: Value<int>(card.suspended ? 1 : 0),
            buriedUntil: Value<int?>(
              card.buriedUntil == null ? null : toEpochMs(card.buriedUntil!),
            ),
            flagged: Value<int>(card.flagged ? 1 : 0),
            siblingId: Value<String?>(card.siblingId),
            contentHash: Value<String?>(card.contentHash),
            createdAt: toEpochMs(card.createdAt),
            updatedAt: toEpochMs(card.updatedAt),
          ),
        );
  }

  /// Записывает медиафайл и строку `media`.
  Future<String> insertMediaFile({
    required String id,
    required String cardId,
    required List<int> bytes,
    String mimeType = 'image/png',
  }) async {
    final path = 'media/$id${mimeType == 'image/png' ? '.png' : '.bin'}';
    await mediaStore.writeMedia(
      relativePath: path,
      bytes: Uint8List.fromList(bytes),
    );
    await db
        .into(db.media)
        .insert(
          MediaCompanion.insert(
            id: id,
            cardId: cardId,
            path: path,
            mimeType: mimeType,
            size: bytes.length,
          ),
        );
    return path;
  }

  /// Полная тестовая колода: 4 карточки, 2 медиафайла.
  Future<void> seedSampleDeck({DateTime? archivedAt}) async {
    await insertDeck(archivedAt: archivedAt);
    for (final card in _sampleCards()) {
      await insertCard(card);
    }
    await insertMediaFile(
      id: 'm-1',
      cardId: 'card-1',
      bytes: const <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 255],
    );
    await insertMediaFile(
      id: 'm-2',
      cardId: 'card-2',
      bytes: const <int>[],
      mimeType: 'application/octet-stream',
    );
  }

  /// Карточка из строки БД (локальный маппинг, чтобы не зависеть от репозитория).
  Card cardFromRow(CardRow row) => Card(
    id: row.id,
    deckId: row.deckId,
    front: row.front,
    back: row.back,
    hint: row.hint,
    cardType: CardType.fromWire(row.cardType),
    tags: (jsonDecode(row.tagsJson) as List<dynamic>).cast<String>(),
    mediaIds: (jsonDecode(row.mediaJson) as List<dynamic>).cast<String>(),
    latex: row.latex,
    occlusionJson: row.occlusionJson,
    sourceDocId: row.sourceDocId,
    sourceExcerpt: row.sourceExcerpt,
    state: CardState.fromWire(row.state),
    fsrsJson: row.fsrsJson,
    due: row.due == null ? null : fromEpochMs(row.due!),
    suspended: row.suspended != 0,
    buriedUntil: row.buriedUntil == null ? null : fromEpochMs(row.buriedUntil!),
    flagged: row.flagged != 0,
    siblingId: row.siblingId,
    contentHash: row.contentHash,
    createdAt: fromEpochMs(row.createdAt),
    updatedAt: fromEpochMs(row.updatedAt),
  );

  Future<List<CardRow>> cardRowsOf(String deckId) async {
    final query = db.select(db.cards)
      ..where((table) => table.deckId.equals(deckId));
    return query.get();
  }

  setUp(() {
    db = AppDatabase.inMemory();
    tempRoot = Directory.systemTemp.createTempSync('cardflow_transfer_test_');
    mediaStore = MediaStore(Directory(p.join(tempRoot.path, 'media')));
    service = DriftDeckTransferService(
      appDatabase: db,
      codec: _codec,
      mediaStore: mediaStore,
    );
  });

  tearDown(() async {
    await db.close();
    if (tempRoot.existsSync()) {
      tempRoot.deleteSync(recursive: true);
    }
  });

  group('DriftDeckTransferService: exportDeckZip', () {
    test('экспортирует колоду, карточки и медиа без потерь', () async {
      await seedSampleDeck();

      final archive = _codec.decode(await service.exportDeckZip('deck-1'));

      expect(archive.formatVersion, deckArchiveFormatVersion);
      expect(archive.deck.id, 'deck-1');
      expect(archive.deck.name, 'Испанский: базовые глаголы');
      expect(archive.deck.settings, _deckSettings);
      expect(archive.deck.createdAt, _deckCreatedAt);
      expect(archive.deck.updatedAt, _deckUpdatedAt);
      expect(archive.deck.archivedAt, isNull);
      expect(archive.cards, hasLength(4));
      expect(archive.media, hasLength(2));

      final cardsById = <String, Card>{
        for (final card in archive.cards) card.id: card,
      };
      for (final expected in _sampleCards()) {
        final actual = cardsById[expected.id];
        expect(actual, isNotNull, reason: 'нет карточки ${expected.id}');
        if (actual == null) {
          continue;
        }
        _expectSameCardContent(actual, expected);
        expect(actual.siblingId, expected.siblingId);
        expect(actual.mediaIds, expected.mediaIds);
      }

      expect(
        _mediaSignatures(archive.media),
        _mediaSignatures(_archiveMedia()),
      );
    });

    test('экспорт архивной колоды сохраняет archived_at', () async {
      final archivedAt = DateTime.utc(2026, 11, 11, 23, 59, 59);
      await seedSampleDeck(archivedAt: archivedAt);

      final archive = _codec.decode(await service.exportDeckZip('deck-1'));

      expect(archive.deck.archivedAt, archivedAt);
    });

    test('отсутствующая колода → deckNotFound', () async {
      expect(
        () => service.exportDeckZip('нет-такой'),
        _throwsArchiveError(ArchiveErrorCode.deckNotFound),
      );
    });

    test('отсутствующий файл медиа → mediaMissing', () async {
      await insertDeck();
      await insertCard(_basicCard(mediaIds: const <String>['m-1']));
      // Строка media есть, файла в MediaStore нет.
      await db
          .into(db.media)
          .insert(
            MediaCompanion.insert(
              id: 'm-1',
              cardId: 'card-1',
              path: 'media/m-1.png',
              mimeType: 'image/png',
              size: 3,
            ),
          );

      expect(
        () => service.exportDeckZip('deck-1'),
        _throwsArchiveError(ArchiveErrorCode.mediaMissing),
      );
    });

    test('пустая колода (0 карточек) экспортируется', () async {
      await insertDeck();

      final archive = _codec.decode(await service.exportDeckZip('deck-1'));

      expect(archive.cards, isEmpty);
      expect(archive.media, isEmpty);
      expect(archive.deck.name, 'Испанский: базовые глаголы');
    });
  });

  group('DriftDeckTransferService: previewImport', () {
    test('показывает имя, версию, карточки и медиа; БД не меняет', () async {
      await seedSampleDeck();
      final bytes = await service.exportDeckZip('deck-1');

      final preview = await service.previewImport(bytes);

      expect(preview.deckName, 'Испанский: базовые глаголы');
      expect(preview.formatVersion, deckArchiveFormatVersion);
      expect(preview.cardsCount, 4);
      expect(preview.duplicatesCount, 0);
      expect(preview.mediaCount, 2);

      // БД не изменилась: в ней ровно исходные строки.
      expect(await db.select(db.decks).get(), hasLength(1));
      expect(await db.select(db.cards).get(), hasLength(4));
      expect(await db.select(db.media).get(), hasLength(2));
    });

    test('считает дубликаты по content_hash внутри архива', () async {
      final first = _basicCard(mediaIds: const <String>[]);
      final hash = contentHashOf(front: first.front, back: first.back);
      final duplicate = _basicCard(
        id: 'card-dup',
        mediaIds: const <String>[],
        contentHash: hash,
      );
      final another = Card(
        id: 'card-other',
        deckId: 'deck-1',
        front: 'Другой вопрос',
        back: 'Другой ответ',
        cardType: CardType.basic,
        state: CardState.newCard,
        createdAt: _cardCreatedAt,
        updatedAt: _cardUpdatedAt,
      );
      final bytes = _codec.encode(
        _archive(cards: <Card>[first, duplicate, another]),
      );

      final preview = await service.previewImport(bytes);

      expect(preview.cardsCount, 2);
      expect(preview.duplicatesCount, 1);
      expect(await db.select(db.decks).get(), isEmpty);
    });

    test('дубликаты по вычисленному content_hash (null в архиве)', () async {
      final first = _basicCard(mediaIds: const <String>[]);
      final duplicate = _basicCard(id: 'card-dup', mediaIds: const <String>[]);
      final bytes = _codec.encode(_archive(cards: <Card>[first, duplicate]));

      final preview = await service.previewImport(bytes);

      expect(preview.cardsCount, 1);
      expect(preview.duplicatesCount, 1);
    });

    test('mediaCount учитывает только импортируемые карточки', () async {
      final first = _basicCard(mediaIds: const <String>['m-1']);
      final duplicate = _basicCard(
        id: 'card-dup',
        mediaIds: const <String>['m-2'],
      );
      final media = <ArchiveMedia>[
        ArchiveMedia(
          id: 'm-1',
          cardId: 'card-1',
          path: 'media/m-1.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList(<int>[1]),
        ),
        ArchiveMedia(
          id: 'm-2',
          cardId: 'card-dup',
          path: 'media/m-2.png',
          mimeType: 'image/png',
          bytes: Uint8List.fromList(<int>[2]),
        ),
      ];
      final bytes = _codec.encode(
        _archive(cards: <Card>[first, duplicate], media: media),
      );

      final preview = await service.previewImport(bytes);

      expect(preview.cardsCount, 1);
      expect(preview.duplicatesCount, 1);
      expect(preview.mediaCount, 1);
    });

    test('битый архив → corruptZip', () async {
      expect(
        () => service.previewImport(Uint8List.fromList(<int>[1, 2, 3])),
        _throwsArchiveError(ArchiveErrorCode.corruptZip),
      );
    });
  });

  group('DriftDeckTransferService: importZip', () {
    test('export → import → export без потери контента', () async {
      await seedSampleDeck();
      final before = _codec.decode(await service.exportDeckZip('deck-1'));

      final result = await service.importZip(
        await service.exportDeckZip('deck-1'),
      );

      expect(result.importedCards, 4);
      expect(result.skippedDuplicates, 0);
      expect(result.importedMedia, 2);
      expect(result.deckId, isNot('deck-1'));
      expect(result.deckId, matches(_uuidV4));

      // Колода: контент и timestamps сохранены, id новый.
      final deckRow = await (db.select(
        db.decks,
      )..where((table) => table.id.equals(result.deckId))).getSingle();
      expect(deckRow.name, before.deck.name);
      expect(jsonDecode(deckRow.settingsJson), before.deck.settings);
      expect(fromEpochMs(deckRow.createdAt), before.deck.createdAt);
      expect(fromEpochMs(deckRow.updatedAt), before.deck.updatedAt);
      expect(deckRow.archivedAt, isNull);

      // Карточки: весь контент сохранён, id новые, deck_id новый.
      final importedCards = (await cardRowsOf(result.deckId))
          .map(cardFromRow)
          .toList();
      expect(importedCards, hasLength(4));
      final importedByHash = <String, Card>{
        for (final card in importedCards) _hashOf(card): card,
      };
      for (final expected in before.cards) {
        final actual = importedByHash[_hashOf(expected)];
        expect(
          actual,
          isNotNull,
          reason: 'потеряна карточка ${expected.front}',
        );
        if (actual == null) {
          continue;
        }
        expect(actual.id, isNot(expected.id));
        expect(actual.id, matches(_uuidV4));
        expect(actual.deckId, result.deckId);
        _expectSameCardContent(actual, expected);
      }

      // basic_reversed: sibling_id переназначен на новые id взаимно.
      final reversedFirst = importedCards.firstWhere(
        (Card card) => card.front == 'Лицевая A',
      );
      final reversedSecond = importedCards.firstWhere(
        (Card card) => card.front == 'Лицевая B',
      );
      expect(reversedFirst.siblingId, reversedSecond.id);
      expect(reversedSecond.siblingId, reversedFirst.id);

      // Медиа: новые id/пути, байты и MIME без потерь.
      final importedCardIds = importedCards.map((Card card) => card.id).toSet();
      final mediaRows = (await db.select(db.media).get())
          .where((MediaRow row) => importedCardIds.contains(row.cardId))
          .toList();
      expect(mediaRows, hasLength(2));
      final mediaBytes = <String>[];
      for (final row in mediaRows) {
        expect(row.id, matches(_uuidV4));
        expect(row.id, isNot(anyOf('m-1', 'm-2')));
        final bytes = await mediaStore.readMedia(row.path);
        expect(bytes, isNotNull);
        if (bytes == null) {
          continue;
        }
        expect(row.size, bytes.length);
        mediaBytes.add('${row.mimeType}:${base64Encode(bytes)}');
      }
      expect(mediaBytes..sort(), _mediaSignatures(before.media));
      // Ссылки карточек на медиа ведут на строки таблицы media.
      final mediaIds = mediaRows.map((MediaRow row) => row.id).toSet();
      for (final card in importedCards) {
        for (final mediaId in card.mediaIds) {
          expect(mediaIds, contains(mediaId));
        }
      }
      expect(
        mediaRows.every((MediaRow row) => importedCardIds.contains(row.cardId)),
        isTrue,
        reason: 'медиа-строки должны принадлежать импортированным карточкам',
      );

      // Повторный экспорт: контент идентичен первому архиву.
      final after = _codec.decode(await service.exportDeckZip(result.deckId));
      expect(after.deck.name, before.deck.name);
      expect(after.deck.settings, before.deck.settings);
      expect(after.deck.createdAt, before.deck.createdAt);
      expect(after.deck.updatedAt, before.deck.updatedAt);
      expect(after.deck.archivedAt, before.deck.archivedAt);
      expect(after.cards, hasLength(before.cards.length));
      final afterByHash = <String, Card>{
        for (final card in after.cards) _hashOf(card): card,
      };
      for (final expected in before.cards) {
        final actual = afterByHash[_hashOf(expected)];
        expect(actual, isNotNull);
        if (actual == null) {
          continue;
        }
        _expectSameCardContent(actual, expected);
      }
      expect(_mediaSignatures(after.media), _mediaSignatures(before.media));
    });

    test('создаёт новые id для колоды/карточек/медиа', () async {
      final card = _basicCard(mediaIds: const <String>['m-1']);
      final media = ArchiveMedia(
        id: 'm-1',
        cardId: 'card-1',
        path: 'media/m-1.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      final bytes = _codec.encode(
        _archive(cards: <Card>[card], media: <ArchiveMedia>[media]),
      );

      final result = await service.importZip(bytes);

      expect(result.deckId, isNot('deck-old'));
      expect(result.deckId, matches(_uuidV4));
      final imported = (await cardRowsOf(result.deckId))
          .map(cardFromRow)
          .single;
      expect(imported.id, isNot('card-1'));
      expect(imported.id, matches(_uuidV4));
      expect(imported.mediaIds.single, isNot('m-1'));
      expect(imported.mediaIds.single, matches(_uuidV4));
      final mediaRows = await db.select(db.media).get();
      expect(mediaRows.single.id, imported.mediaIds.single);
      expect(mediaRows.single.cardId, imported.id);
    });

    test('импорт пустой колоды создаёт колоду без карточек', () async {
      final bytes = _codec.encode(_archive(cards: const <Card>[]));

      final result = await service.importZip(bytes);

      expect(result.importedCards, 0);
      expect(result.skippedDuplicates, 0);
      expect(result.importedMedia, 0);
      final deckRows = await db.select(db.decks).get();
      expect(deckRows, hasLength(1));
      expect(deckRows.single.id, result.deckId);
      expect(deckRows.single.name, 'Колода из архива');
      expect(await db.select(db.cards).get(), isEmpty);
    });

    test('дубликаты по content_hash пропускаются', () async {
      final first = _basicCard(mediaIds: const <String>[]);
      final hash = contentHashOf(front: first.front, back: first.back);
      final duplicate = _basicCard(
        id: 'card-dup',
        mediaIds: const <String>[],
        contentHash: hash,
      );
      final bytes = _codec.encode(_archive(cards: <Card>[first, duplicate]));

      final result = await service.importZip(bytes);

      expect(result.importedCards, 1);
      expect(result.skippedDuplicates, 1);
      final cards = await cardRowsOf(result.deckId);
      expect(cards, hasLength(1));
      expect(cards.single.contentHash, hash);
    });

    test('content_hash null вычисляется при импорте', () async {
      final card = _basicCard(mediaIds: const <String>[]);
      final bytes = _codec.encode(_archive(cards: <Card>[card]));

      final result = await service.importZip(bytes);

      final imported = (await cardRowsOf(result.deckId)).single;
      expect(
        imported.contentHash,
        contentHashOf(front: card.front, back: card.back),
      );
    });

    test('подменённый content_hash из архива пересчитывается (M9)', () async {
      final card = _basicCard(
        mediaIds: const <String>[],
        contentHash: 'подменённый-хеш',
      );
      final bytes = _codec.encode(_archive(cards: <Card>[card]));

      final result = await service.importZip(bytes);

      final imported = (await cardRowsOf(result.deckId)).single;
      final expected = contentHashOf(front: card.front, back: card.back);
      expect(imported.contentHash, expected);
      expect(imported.contentHash, isNot('подменённый-хеш'));
    });

    test('дубликаты определяются по пересчитанному хешу (M9)', () async {
      final first = _basicCard(
        mediaIds: const <String>[],
        contentHash: 'подменённый-1',
      );
      final second = _basicCard(
        id: 'card-2',
        mediaIds: const <String>[],
        contentHash: 'подменённый-2',
      );
      final bytes = _codec.encode(_archive(cards: <Card>[first, second]));

      final preview = await service.previewImport(bytes);
      expect(preview.cardsCount, 1);
      expect(preview.duplicatesCount, 1);

      final result = await service.importZip(bytes);
      expect(result.importedCards, 1);
      expect(result.skippedDuplicates, 1);
      final cards = await cardRowsOf(result.deckId);
      expect(cards, hasLength(1));
      expect(
        cards.single.contentHash,
        contentHashOf(front: first.front, back: first.back),
      );
    });

    test('deckName переопределяет имя колоды из архива', () async {
      final bytes = _codec.encode(_archive(cards: const <Card>[]));

      final result = await service.importZip(bytes, deckName: '  Моё имя  ');

      final deckRow = await (db.select(
        db.decks,
      )..where((table) => table.id.equals(result.deckId))).getSingle();
      expect(deckRow.name, 'Моё имя');
    });

    test('deckName из пробелов = нет override (M10)', () async {
      final bytes = _codec.encode(_archive(cards: const <Card>[]));

      final result = await service.importZip(bytes, deckName: '   ');

      final deckRow = await (db.select(
        db.decks,
      )..where((table) => table.id.equals(result.deckId))).getSingle();
      expect(deckRow.name, 'Колода из архива');
    });

    test('импорт архивной колоды сохраняет archived_at', () async {
      final archivedAt = DateTime.utc(2026, 11, 11, 23, 59, 59);
      final bytes = _codec.encode(
        _archive(
          cards: const <Card>[],
          deck: ArchiveDeck(
            id: 'deck-old',
            name: 'Архивная',
            settings: const <String, Object?>{},
            createdAt: _deckCreatedAt,
            updatedAt: _deckUpdatedAt,
            archivedAt: archivedAt,
          ),
        ),
      );

      final result = await service.importZip(bytes);

      final deckRow = await (db.select(
        db.decks,
      )..where((table) => table.id.equals(result.deckId))).getSingle();
      expect(deckRow.archivedAt, toEpochMs(archivedAt));
    });

    test('медиа записываются в MediaStore и таблицу media', () async {
      final card = _basicCard(mediaIds: const <String>['m-1']);
      final bytes = Uint8List.fromList(<int>[137, 80, 78, 71, 0, 255]);
      final archive = _archive(
        cards: <Card>[card],
        media: <ArchiveMedia>[
          ArchiveMedia(
            id: 'm-1',
            cardId: 'card-1',
            path: 'media/m-1.png',
            mimeType: 'image/png',
            bytes: bytes,
          ),
        ],
      );

      final result = await service.importZip(_codec.encode(archive));

      final mediaRow = (await db.select(db.media).get()).single;
      expect(mediaRow.mimeType, 'image/png');
      expect(mediaRow.size, bytes.length);
      expect(mediaRow.path, startsWith('media/'));
      expect(mediaRow.path, endsWith('.png'));
      expect(await mediaStore.readMedia(mediaRow.path), bytes);
      expect(mediaRow.cardId, (await cardRowsOf(result.deckId)).single.id);
    });

    test('ошибка записи медиа → откат транзакции и удаление файлов', () async {
      final failingStore = _FailingMediaStore(
        Directory(p.join(tempRoot.path, 'failing-media')),
      );
      final failingService = DriftDeckTransferService(
        appDatabase: db,
        codec: _codec,
        mediaStore: failingStore,
      );
      final first = _basicCard(mediaIds: const <String>['m-1']);
      final second = Card(
        id: 'card-2',
        deckId: 'deck-1',
        front: 'Вторая',
        back: 'Карточка',
        cardType: CardType.basic,
        state: CardState.newCard,
        mediaIds: const <String>['m-2'],
        createdAt: _cardCreatedAt,
        updatedAt: _cardUpdatedAt,
      );
      final archive = _archive(
        cards: <Card>[first, second],
        media: <ArchiveMedia>[
          ArchiveMedia(
            id: 'm-1',
            cardId: 'card-1',
            path: 'media/m-1.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[1]),
          ),
          ArchiveMedia(
            id: 'm-2',
            cardId: 'card-2',
            path: 'media/m-2.png',
            mimeType: 'image/png',
            bytes: Uint8List.fromList(<int>[2]),
          ),
        ],
      );

      await expectLater(
        failingService.importZip(_codec.encode(archive)),
        throwsA(isA<FileSystemException>()),
      );

      // Транзакция откатилась: нет ни колоды, ни карточек, ни строк медиа.
      expect(await db.select(db.decks).get(), isEmpty);
      expect(await db.select(db.cards).get(), isEmpty);
      expect(await db.select(db.media).get(), isEmpty);
      // Best-effort: записанный до сбоя файл удалён.
      expect(failingStore.writtenPaths, hasLength(1));
      expect(
        await failingStore.readMedia(failingStore.writtenPaths.single),
        isNull,
      );
    });

    test('битый архив → ArchiveException, БД не меняется', () async {
      await seedSampleDeck();

      await expectLater(
        service.importZip(Uint8List.fromList(<int>[1, 2, 3])),
        _throwsArchiveError(ArchiveErrorCode.corruptZip),
      );

      expect(await db.select(db.decks).get(), hasLength(1));
      expect(await db.select(db.cards).get(), hasLength(4));
    });
  });
}

/// Ожидаемые медиа тестовой колоды (для сигнатур байтов).
List<ArchiveMedia> _archiveMedia() => <ArchiveMedia>[
  ArchiveMedia(
    id: 'm-1',
    cardId: 'card-1',
    path: 'media/m-1.png',
    mimeType: 'image/png',
    bytes: Uint8List.fromList(const <int>[
      137,
      80,
      78,
      71,
      13,
      10,
      26,
      10,
      0,
      1,
      2,
      255,
    ]),
  ),
  ArchiveMedia(
    id: 'm-2',
    cardId: 'card-2',
    path: 'media/m-2.bin',
    mimeType: 'application/octet-stream',
    bytes: Uint8List(0),
  ),
];
