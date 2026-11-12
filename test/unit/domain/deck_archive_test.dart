import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';

void main() {
  final exportedAt = DateTime.utc(2026, 11, 12, 12);
  final createdAt = DateTime.utc(2026, 11, 11, 10);
  final updatedAt = DateTime.utc(2026, 11, 11, 11);

  ArchiveDeck archiveDeck() => ArchiveDeck(
    id: 'deck-1',
    name: 'Испанский',
    settings: const <String, Object?>{'desiredRetention': 0.9},
    createdAt: createdAt,
    updatedAt: updatedAt,
  );

  group('ArchiveDeck', () {
    test('равенство по всем полям', () {
      expect(archiveDeck(), equals(archiveDeck()));
      expect(archiveDeck().hashCode, archiveDeck().hashCode);
      expect(
        ArchiveDeck(
              id: 'deck-1',
              name: 'Другой',
              settings: const <String, Object?>{'desiredRetention': 0.9},
              createdAt: createdAt,
              updatedAt: updatedAt,
            ) ==
            archiveDeck(),
        isFalse,
      );
    });
  });

  group('ImportPreview', () {
    test('равенство и hashCode', () {
      const preview = ImportPreview(
        deckName: 'Испанский',
        formatVersion: 1,
        cardsCount: 3,
        duplicatesCount: 1,
        mediaCount: 0,
      );
      const samePreview = ImportPreview(
        deckName: 'Испанский',
        formatVersion: 1,
        cardsCount: 3,
        duplicatesCount: 1,
        mediaCount: 0,
      );
      expect(preview, equals(samePreview));
      expect(preview.hashCode, samePreview.hashCode);
      expect(
        preview ==
            const ImportPreview(
              deckName: 'Другой',
              formatVersion: 1,
              cardsCount: 3,
              duplicatesCount: 1,
              mediaCount: 0,
            ),
        isFalse,
      );
    });
  });

  group('ArchiveException', () {
    test('хранит машинный код и детали, toString содержит код', () {
      const exception = ArchiveException(
        ArchiveErrorCode.invalidEntryName,
        details: '../evil',
      );
      expect(exception.code, ArchiveErrorCode.invalidEntryName);
      expect(exception.details, '../evil');
      expect(exception.toString(), contains('invalidEntryName'));
    });
  });

  group('DeckArchive/ArchiveMedia', () {
    test('архив хранит версию, момент экспорта, колоду и карточки', () {
      final archive = DeckArchive(
        formatVersion: deckArchiveFormatVersion,
        exportedAt: exportedAt,
        deck: archiveDeck(),
        cards: const <Card>[],
      );
      expect(archive.formatVersion, 1);
      expect(archive.exportedAt, exportedAt);
      expect(archive.cards, isEmpty);
      expect(archive.media, isEmpty);
    });

    test('ArchiveMedia хранит байты файла', () {
      final media = ArchiveMedia(
        id: 'media-1',
        cardId: 'card-1',
        path: 'media/media-1.png',
        mimeType: 'image/png',
        bytes: Uint8List.fromList(<int>[1, 2, 3]),
      );
      expect(media.bytes, <int>[1, 2, 3]);
      expect(media.mimeType, 'image/png');
    });
  });
}
