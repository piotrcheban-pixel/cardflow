import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/transfer/archive_codec.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';

/// Сервис импорта/экспорта колод `.zip` поверх drift-БД (SPEC A6.9; ADR-006).
///
/// Экспорт читает колоду, карточки и медиа из БД/хранилища и собирает архив
/// кодеком. Импорт **всегда создаёт новую колоду**: id колоды/карточек/медиа
/// генерируются заново (uuid v4), исходные id остаются только в архиве
/// (ADR-006 п.2). Дубликаты по `content_hash` внутри архива пропускаются
/// (первая карточка выигрывает), при `null` хеш вычисляется. Всё пишется в
/// одной транзакции; при ошибке — откат и best-effort удаление записанных
/// медиафайлов.
class DriftDeckTransferService implements DeckTransferService {
  /// Создаёт сервис.
  DriftDeckTransferService({
    required this.appDatabase,
    required this.codec,
    required this.mediaStore,
  });

  /// БД приложения.
  final AppDatabase appDatabase;

  /// Кодек архива.
  final DeckArchiveCodec codec;

  /// Хранилище медиа.
  final MediaStore mediaStore;

  static const Uuid _uuid = Uuid();
  static final RegExp _safeExtension = RegExp(r'^\.[A-Za-z0-9]{1,16}$');

  @override
  Future<Uint8List> exportDeckZip(String deckId) async {
    final deckQuery = appDatabase.select(appDatabase.decks)
      ..where((table) => table.id.equals(deckId));
    final deckRow = await deckQuery.getSingleOrNull();
    if (deckRow == null) {
      throw ArchiveException(
        ArchiveErrorCode.deckNotFound,
        details: 'export: колода $deckId не найдена',
      );
    }

    final cardsQuery = appDatabase.select(appDatabase.cards)
      ..where((table) => table.deckId.equals(deckId))
      ..orderBy(<OrderingTerm Function($CardsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    final cardRows = await cardsQuery.get();
    final mediaRows = await _mediaRowsForCards(
      cardRows.map((CardRow row) => row.id).toList(),
    );
    final mediaById = <String, MediaRow>{
      for (final row in mediaRows) row.id: row,
    };

    final cards = <Card>[];
    final archiveMedia = <ArchiveMedia>[];
    final referencedMedia = <String>{};
    for (final row in cardRows) {
      final card = _cardFromRow(row);
      cards.add(card);
      for (final mediaId in card.mediaIds) {
        if (!referencedMedia.add(mediaId)) {
          continue;
        }
        final mediaRow = mediaById[mediaId];
        if (mediaRow == null) {
          throw ArchiveException(
            ArchiveErrorCode.mediaMissing,
            details: 'export: нет строки media $mediaId',
          );
        }
        final bytes = await mediaStore.readMedia(mediaRow.path);
        if (bytes == null) {
          throw ArchiveException(
            ArchiveErrorCode.mediaMissing,
            details: 'export: нет файла ${mediaRow.path}',
          );
        }
        archiveMedia.add(
          ArchiveMedia(
            id: mediaRow.id,
            cardId: card.id,
            path: mediaRow.path,
            mimeType: mediaRow.mimeType,
            bytes: bytes,
          ),
        );
      }
    }

    final archive = DeckArchive(
      formatVersion: deckArchiveFormatVersion,
      exportedAt: DateTime.now().toUtc(),
      deck: ArchiveDeck(
        id: deckRow.id,
        name: deckRow.name,
        settings: _decodeSettings(deckRow.settingsJson),
        createdAt: fromEpochMs(deckRow.createdAt),
        updatedAt: fromEpochMs(deckRow.updatedAt),
        archivedAt: deckRow.archivedAt == null
            ? null
            : fromEpochMs(deckRow.archivedAt!),
      ),
      cards: cards,
      media: archiveMedia,
    );
    return codec.encode(archive);
  }

  @override
  Future<ImportPreview> previewImport(Uint8List zipBytes) async {
    final archive = codec.decode(zipBytes);
    final uniqueCards = _uniqueCards(archive.cards);
    var mediaCount = 0;
    for (final card in uniqueCards) {
      mediaCount += card.mediaIds.length;
    }
    return ImportPreview(
      deckName: archive.deck.name,
      formatVersion: archive.formatVersion,
      cardsCount: uniqueCards.length,
      duplicatesCount: archive.cards.length - uniqueCards.length,
      mediaCount: mediaCount,
    );
  }

  @override
  Future<ImportResult> importZip(Uint8List zipBytes, {String? deckName}) async {
    final archive = codec.decode(zipBytes);
    final prepared = _prepareImport(archive, deckName: deckName);
    final writtenMediaPaths = <String>[];
    try {
      await appDatabase.transaction(() async {
        await appDatabase.into(appDatabase.decks).insert(prepared.deck);
        for (final card in prepared.cards) {
          await appDatabase.into(appDatabase.cards).insert(card);
        }
        for (final media in prepared.media) {
          await mediaStore.writeMedia(
            relativePath: media.path,
            bytes: media.bytes,
          );
          writtenMediaPaths.add(media.path);
          await appDatabase.into(appDatabase.media).insert(media.companion);
        }
      });
    } catch (error) {
      await _cleanupWrittenMedia(writtenMediaPaths);
      rethrow;
    }
    return ImportResult(
      deckId: prepared.deckId,
      importedCards: prepared.cards.length,
      skippedDuplicates: prepared.skippedDuplicates,
      importedMedia: prepared.media.length,
    );
  }

  // --- импорт: подготовка ---

  /// Готовит строки для одной транзакции: новые id, дедупликация, медиа.
  _PreparedImport _prepareImport(DeckArchive archive, {String? deckName}) {
    final override = deckName?.trim();
    final resolvedName = override != null && override.isNotEmpty
        ? override
        : archive.deck.name;
    final deckId = _uuid.v4();
    final uniqueCards = _uniqueCards(archive.cards);
    final archiveMediaById = <String, ArchiveMedia>{
      for (final media in archive.media) media.id: media,
    };

    // Новые id карточек: базовая карта для переназначения sibling_id.
    final newCardIds = <String, String>{
      for (final card in uniqueCards) card.id: _uuid.v4(),
    };

    final importedMedia = <_ImportedMedia>[];
    final newMediaIdsByCard = <String, List<String>>{};
    for (final card in uniqueCards) {
      final newCardId = newCardIds[card.id]!;
      final newMediaIds = <String>[];
      for (final oldMediaId in card.mediaIds) {
        final media = archiveMediaById[oldMediaId];
        if (media == null) {
          throw ArchiveException(
            ArchiveErrorCode.mediaMissing,
            details: 'import: нет записи media/$oldMediaId',
          );
        }
        final newMediaId = _uuid.v4();
        newMediaIds.add(newMediaId);
        importedMedia.add(
          _ImportedMedia(
            id: newMediaId,
            cardId: newCardId,
            path: _importMediaPath(newMediaId, media.path),
            mimeType: media.mimeType,
            bytes: media.bytes,
          ),
        );
      }
      newMediaIdsByCard[newCardId] = newMediaIds;
    }

    final cardCompanions = <CardsCompanion>[];
    for (final card in uniqueCards) {
      final newCardId = newCardIds[card.id]!;
      final oldSiblingId = card.siblingId;
      final newSiblingId = oldSiblingId == null
          ? null
          : newCardIds[oldSiblingId];
      cardCompanions.add(
        CardsCompanion.insert(
          id: newCardId,
          deckId: deckId,
          front: card.front,
          back: card.back,
          hint: Value<String?>(card.hint),
          cardType: card.cardType.wireName,
          tagsJson: Value<String>(jsonEncode(card.tags)),
          mediaJson: Value<String>(jsonEncode(newMediaIdsByCard[newCardId]!)),
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
          siblingId: Value<String?>(newSiblingId),
          contentHash: Value<String>(_effectiveContentHash(card)),
          createdAt: toEpochMs(card.createdAt),
          updatedAt: toEpochMs(card.updatedAt),
        ),
      );
    }

    return _PreparedImport(
      deckId: deckId,
      deck: DecksCompanion.insert(
        id: deckId,
        name: resolvedName,
        settingsJson: Value<String>(jsonEncode(archive.deck.settings)),
        archivedAt: Value<int?>(
          archive.deck.archivedAt == null
              ? null
              : toEpochMs(archive.deck.archivedAt!),
        ),
        createdAt: toEpochMs(archive.deck.createdAt),
        updatedAt: toEpochMs(archive.deck.updatedAt),
      ),
      cards: cardCompanions,
      media: importedMedia,
      skippedDuplicates: archive.cards.length - uniqueCards.length,
    );
  }

  /// Уникальные карточки архива: первая карточка на `content_hash` выигрывает.
  List<Card> _uniqueCards(List<Card> cards) {
    final seenHashes = <String>{};
    final unique = <Card>[];
    for (final card in cards) {
      if (seenHashes.add(_effectiveContentHash(card))) {
        unique.add(card);
      }
    }
    return unique;
  }

  /// `content_hash` карточки: **всегда пересчитывается** из `front`/`back`
  /// (M9: значению `content_hash` из архива не доверяем; SPEC A5/A8.5).
  String _effectiveContentHash(Card card) =>
      contentHashOf(front: card.front, back: card.back);

  /// Относительный путь нового медиафайла: `media/<uuid>` + безопасное
  /// расширение исходного пути (MIME всё равно хранится в таблице).
  String _importMediaPath(String newId, String archivePath) {
    final extension = p.extension(archivePath);
    final safeExtension = _safeExtension.hasMatch(extension) ? extension : '';
    return '${DeckArchiveEntries.mediaDir}$newId$safeExtension';
  }

  /// Best-effort удаление медиафайлов после отката транзакции.
  Future<void> _cleanupWrittenMedia(List<String> paths) async {
    for (final path in paths) {
      try {
        await mediaStore.deleteMedia(path);
      } catch (_) {
        // Ошибку очистки не маскируем исходную ошибку импорта.
        continue;
      }
    }
  }

  // --- маппинг строк БД в домен ---

  Future<List<MediaRow>> _mediaRowsForCards(List<String> cardIds) {
    if (cardIds.isEmpty) {
      return Future<List<MediaRow>>.value(const <MediaRow>[]);
    }
    final query = appDatabase.select(appDatabase.media)
      ..where((table) => table.cardId.isIn(cardIds));
    return query.get();
  }

  Card _cardFromRow(CardRow row) => Card(
    id: row.id,
    deckId: row.deckId,
    front: row.front,
    back: row.back,
    hint: row.hint,
    cardType: CardType.fromWire(row.cardType),
    tags: _decodeStringList(row.tagsJson),
    mediaIds: _decodeStringList(row.mediaJson),
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

  Map<String, Object?> _decodeSettings(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw FormatException('settings_json колоды — не JSON-объект: $raw');
    }
    return <String, Object?>{
      for (final entry in decoded.entries) '${entry.key}': entry.value,
    };
  }

  List<String> _decodeStringList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Ожидался JSON-массив строк, получено: $raw');
    }
    return decoded
        .map((Object? value) {
          if (value is! String) {
            throw FormatException('Элемент JSON-массива не строка: $raw');
          }
          return value;
        })
        .toList(growable: false);
  }
}

/// Подготовленные к записи данные импорта (id уже новые).
class _PreparedImport {
  const _PreparedImport({
    required this.deckId,
    required this.deck,
    required this.cards,
    required this.media,
    required this.skippedDuplicates,
  });

  final String deckId;
  final DecksCompanion deck;
  final List<CardsCompanion> cards;
  final List<_ImportedMedia> media;
  final int skippedDuplicates;
}

/// Медиафайл, подготовленный к импорту.
class _ImportedMedia {
  const _ImportedMedia({
    required this.id,
    required this.cardId,
    required this.path,
    required this.mimeType,
    required this.bytes,
  });

  final String id;
  final String cardId;
  final String path;
  final String mimeType;
  final Uint8List bytes;

  MediaCompanion get companion => MediaCompanion.insert(
    id: id,
    cardId: cardId,
    path: path,
    mimeType: mimeType,
    size: bytes.length,
  );
}
