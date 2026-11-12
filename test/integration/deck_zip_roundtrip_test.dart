import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Интеграционный тест полного тракта `.zip`: реальные БД drift, кодек,
/// MediaStore и transfer-сервис из продуктового графа провайдеров.
///
/// Проверяет A6.9/A5: экспорт → импорт → экспорт без потерь, дедупликацию
/// по `content_hash` и перенос медиафайлов.
void main() {
  late AppDatabase database;
  late Directory mediaDirectory;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_media_');
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

  DeckTransferService service() => container.read(deckTransferServiceProvider);

  Card buildCard({
    String id = 'card-1',
    String deckId = 'deck-1',
    String front = '¿Cómo se dice «говорить»?',
    String back = 'hablar',
    List<String> mediaIds = const <String>[],
  }) {
    return Card(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      hint: 'глагол',
      cardType: CardType.basic,
      tags: const <String>['глаголы'],
      mediaIds: mediaIds,
      state: CardState.newCard,
      contentHash: contentHashOf(front: front, back: back),
      createdAt: DateTime.utc(2026, 11, 12, 10),
      updatedAt: DateTime.utc(2026, 11, 12, 10),
    );
  }

  DeckArchive buildArchive({
    required List<Card> cards,
    List<ArchiveMedia> media = const <ArchiveMedia>[],
    String deckName = 'Испанский: глаголы',
  }) {
    return DeckArchive(
      formatVersion: deckArchiveFormatVersion,
      exportedAt: DateTime.utc(2026, 11, 12, 12),
      deck: ArchiveDeck(
        id: 'deck-1',
        name: deckName,
        settings: const <String, Object?>{'desiredRetention': 0.9},
        createdAt: DateTime.utc(2026, 11, 12, 10),
        updatedAt: DateTime.utc(2026, 11, 12, 10),
      ),
      cards: cards,
      media: media,
    );
  }

  test(
    'экспорт → импорт → экспорт без потерь (карточки и настройки)',
    () async {
      final codec = container.read(deckArchiveCodecProvider);
      final original = buildArchive(cards: <Card>[buildCard()]);

      final preview = await service().previewImport(codec.encode(original));
      expect(preview.deckName, 'Испанский: глаголы');
      expect(preview.formatVersion, deckArchiveFormatVersion);
      expect(preview.cardsCount, 1);
      expect(preview.duplicatesCount, 0);

      final result = await service().importZip(codec.encode(original));
      expect(result.importedCards, 1);
      expect(result.skippedDuplicates, 0);

      final exportedAgain = codec.decode(
        await service().exportDeckZip(result.deckId),
      );
      expect(exportedAgain.cards, hasLength(1));
      final card = exportedAgain.cards.single;
      expect(card.front, original.cards.single.front);
      expect(card.back, original.cards.single.back);
      expect(card.hint, original.cards.single.hint);
      expect(card.cardType, original.cards.single.cardType);
      expect(card.tags, original.cards.single.tags);
      expect(card.contentHash, original.cards.single.contentHash);
      expect(exportedAgain.deck.name, original.deck.name);
      expect(exportedAgain.deck.settings, original.deck.settings);

      // Данные реально лежат в БД: список карточек через провайдер видит карточку.
      final cards = await container
          .read(cardRepositoryProvider)
          .cardsByDeck(result.deckId);
      expect(cards.map((Card c) => c.front), <String>[
        original.cards.single.front,
      ]);
    },
  );

  test('медиафайлы переносятся без потерь', () async {
    final codec = container.read(deckArchiveCodecProvider);
    final bytes = Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]);
    final card = buildCard(mediaIds: const <String>['media-1']);
    final archive = buildArchive(
      cards: <Card>[card],
      media: <ArchiveMedia>[
        ArchiveMedia(
          id: 'media-1',
          cardId: card.id,
          path: 'media/media-1.png',
          mimeType: 'image/png',
          bytes: bytes,
        ),
      ],
    );

    final preview = await service().previewImport(codec.encode(archive));
    expect(preview.mediaCount, 1);

    final result = await service().importZip(codec.encode(archive));
    expect(result.importedMedia, 1);

    final exported = codec.decode(await service().exportDeckZip(result.deckId));
    expect(exported.media, hasLength(1));
    expect(exported.media.single.mimeType, 'image/png');
    expect(exported.media.single.bytes, bytes);
    expect(exported.cards.single.mediaIds, hasLength(1));
  });

  test('дубликаты по content_hash внутри архива пропускаются', () async {
    final codec = container.read(deckArchiveCodecProvider);
    final duplicate = buildCard(id: 'card-2');
    final archive = buildArchive(cards: <Card>[buildCard(), duplicate]);

    final preview = await service().previewImport(codec.encode(archive));
    expect(preview.cardsCount, 1);
    expect(preview.duplicatesCount, 1);

    final result = await service().importZip(codec.encode(archive));
    expect(result.importedCards, 1);
    expect(result.skippedDuplicates, 1);
  });

  test('экспорт несуществующей колоды → deckNotFound', () async {
    await expectLater(
      service().exportDeckZip('missing-deck'),
      throwsA(
        isA<ArchiveException>().having(
          (ArchiveException e) => e.code,
          'code',
          ArchiveErrorCode.deckNotFound,
        ),
      ),
    );
  });
}
