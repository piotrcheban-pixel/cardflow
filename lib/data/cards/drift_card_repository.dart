// Drift-реализация репозитория карточек (SPEC A5, A6.3, ADR-009/017).
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/cards/card_row_mapper.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/cards/content_hash.dart';

/// Репозиторий карточек поверх drift-БД.
class DriftCardRepository implements CardRepository {
  /// Создаёт репозиторий поверх БД и необязательного файлового хранилища.
  DriftCardRepository(this.database, {this.mediaStore});

  /// БД приложения.
  final AppDatabase database;

  /// Файловое хранилище новых изображений (итерация 5).
  final MediaStore? mediaStore;

  static const Uuid _uuid = Uuid();

  @override
  Stream<List<Card>> watchCards(String deckId) {
    final query = database.select(database.cards)
      ..where((table) => table.deckId.equals(deckId))
      ..orderBy(<OrderingTerm Function($CardsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(cardFromRow).toList(growable: false),
    );
  }

  @override
  Future<List<Card>> cardsByDeck(String deckId) async {
    final query = database.select(database.cards)
      ..where((table) => table.deckId.equals(deckId))
      ..orderBy(<OrderingTerm Function($CardsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    final rows = await query.get();
    return rows.map(cardFromRow).toList(growable: false);
  }

  @override
  Future<Card?> cardById(String id) async {
    final query = database.select(database.cards)
      ..where((table) => table.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : cardFromRow(row);
  }

  @override
  Future<List<Card>> createCards({
    required String deckId,
    required CardDraft draft,
    required DateTime now,
  }) async {
    final CardDraft normalized = draft.normalized();
    _validate(normalized);
    final upload = normalized.imageUpload;
    final prepared = upload == null ? null : _prepareUpload(upload);
    final writtenPaths = <String>[];
    try {
      return await database.transaction<List<Card>>(() async {
        final mediaIds = <String>[...normalized.mediaIds];
        if (prepared != null) {
          await _writeUpload(prepared, writtenPaths);
          mediaIds.add(prepared.id);
        }
        final utcNow = now.toUtc();
        if (normalized.cardType == CardType.basicReversed) {
          final firstId = _uuid.v4();
          final secondId = _uuid.v4();
          final first = _newCard(
            id: firstId,
            deckId: deckId,
            front: normalized.front,
            back: normalized.back,
            draft: normalized,
            mediaIds: mediaIds,
            siblingId: secondId,
            now: utcNow,
          );
          final second = _newCard(
            id: secondId,
            deckId: deckId,
            front: normalized.back,
            back: normalized.front,
            draft: normalized,
            mediaIds: mediaIds,
            siblingId: firstId,
            now: utcNow,
          );
          if (prepared != null) {
            await _insertMedia(prepared, firstId);
          }
          await database.into(database.cards).insert(cardToCompanion(first));
          await database.into(database.cards).insert(cardToCompanion(second));
          return <Card>[first, second];
        }
        final card = _newCard(
          id: _uuid.v4(),
          deckId: deckId,
          front: normalized.front,
          back: normalized.back,
          draft: normalized,
          mediaIds: mediaIds,
          siblingId: null,
          now: utcNow,
        );
        if (prepared != null) await _insertMedia(prepared, card.id);
        await database.into(database.cards).insert(cardToCompanion(card));
        return <Card>[card];
      });
    } catch (_) {
      await _deleteFiles(writtenPaths);
      rethrow;
    }
  }

  @override
  Future<Card> updateCard({
    required Card card,
    required CardDraft draft,
    required DateTime now,
  }) async {
    final normalized = draft.normalized();
    final upload = normalized.imageUpload;
    final prepared = upload == null ? null : _prepareUpload(upload);
    final writtenPaths = <String>[];
    final obsoletePaths = <String>[];
    try {
      final updated = await database.transaction<Card>(() async {
        final existing = await cardById(card.id);
        if (existing == null) {
          throw StateError('Карточка не найдена: ${card.id}');
        }
        _validate(_withType(normalized, existing.cardType));
        final mediaIds = <String>[...normalized.mediaIds];
        if (prepared != null) {
          await _writeUpload(prepared, writtenPaths);
          mediaIds.add(prepared.id);
          await _insertMedia(prepared, existing.id);
        }
        final result = Card(
          id: existing.id,
          deckId: existing.deckId,
          front: normalized.front,
          back: normalized.back,
          hint: normalized.hint,
          cardType: existing.cardType,
          tags: normalized.tags,
          mediaIds: List<String>.unmodifiable(mediaIds),
          latex: normalized.latex,
          occlusionJson: normalized.occlusionJson,
          sourceDocId: existing.sourceDocId,
          sourceExcerpt: normalized.sourceExcerpt,
          state: existing.state,
          fsrsJson: existing.fsrsJson,
          due: existing.due,
          suspended: existing.suspended,
          buriedUntil: existing.buriedUntil,
          flagged: existing.flagged,
          siblingId: existing.siblingId,
          contentHash: contentHashOf(
            front: normalized.front,
            back: normalized.back,
          ),
          createdAt: existing.createdAt,
          updatedAt: now.toUtc(),
        );
        final written =
            await (database.update(database.cards)
                  ..where((table) => table.id.equals(existing.id)))
                .write(cardToCompanion(result));
        if (written != 1) {
          throw StateError('Карточка не обновлена: ${card.id}');
        }
        final removedIds = existing.mediaIds
            .where((id) => !mediaIds.contains(id))
            .toList(growable: false);
        for (final id in removedIds) {
          final rows = await (database.select(
            database.media,
          )..where((table) => table.id.equals(id))).get();
          for (final row in rows) {
            if (row.cardId == existing.id) obsoletePaths.add(row.path);
          }
          await (database.delete(
            database.media,
          )..where((table) => table.id.equals(id))).go();
        }
        return result;
      });
      await _deleteFiles(obsoletePaths);
      return updated;
    } catch (_) {
      await _deleteFiles(writtenPaths);
      rethrow;
    }
  }

  @override
  Future<void> deleteCard(String cardId) async {
    final paths = <String>[];
    await database.transaction<void>(() async {
      final existing = await cardById(cardId);
      if (existing == null) return;
      final siblingId = existing.siblingId;
      if (siblingId != null) {
        await (database.update(database.cards)
              ..where((table) => table.id.equals(siblingId)))
            .write(const CardsCompanion(siblingId: Value<String?>(null)));
      }
      final mediaRows = await (database.select(
        database.media,
      )..where((table) => table.cardId.equals(cardId))).get();
      paths.addAll(mediaRows.map((row) => row.path));
      await (database.delete(
        database.media,
      )..where((table) => table.cardId.equals(cardId))).go();
      await (database.delete(
        database.cards,
      )..where((table) => table.id.equals(cardId))).go();
    });
    await _deleteFiles(paths);
  }

  void _validate(CardDraft draft) {
    if (!draft.isValid) {
      throw ArgumentError.value(
        draft,
        'draft',
        'Некорректный черновик карточки: ${draft.validate().values.join(', ')}',
      );
    }
    final upload = draft.imageUpload;
    if (upload != null &&
        (upload.bytes.length > CardImageGateway.maxImageBytes ||
            (upload.mimeType != 'image/png' &&
                upload.mimeType != 'image/jpeg') ||
            upload.bytes.isEmpty)) {
      throw ArgumentError.value(
        upload,
        'imageUpload',
        'Некорректное изображение',
      );
    }
  }

  CardDraft _withType(CardDraft draft, CardType type) => CardDraft(
    front: draft.front,
    back: draft.back,
    hint: draft.hint,
    tags: draft.tags,
    cardType: type,
    sourceExcerpt: draft.sourceExcerpt,
    mediaIds: draft.mediaIds,
    latex: draft.latex,
    occlusionJson: draft.occlusionJson,
    imageUpload: draft.imageUpload,
  );

  _PreparedUpload _prepareUpload(CardImageUpload upload) {
    final store = mediaStore;
    if (store == null) {
      throw StateError('MediaStore не настроен для изображения карточки');
    }
    final id = _uuid.v4();
    return _PreparedUpload(
      id: id,
      path: 'media/$id.${upload.extension}',
      mimeType: upload.mimeType,
      bytes: upload.bytes,
      store: store,
    );
  }

  Future<void> _writeUpload(
    _PreparedUpload upload,
    List<String> writtenPaths,
  ) async {
    await upload.store.writeMedia(
      relativePath: upload.path,
      bytes: upload.bytes,
    );
    writtenPaths.add(upload.path);
  }

  Future<void> _insertMedia(_PreparedUpload upload, String cardId) {
    return database
        .into(database.media)
        .insert(
          MediaCompanion(
            id: Value(upload.id),
            cardId: Value(cardId),
            path: Value(upload.path),
            mimeType: Value(upload.mimeType),
            size: Value(upload.bytes.length),
          ),
        );
  }

  Future<void> _deleteFiles(Iterable<String> paths) async {
    final store = mediaStore;
    if (store == null) return;
    for (final path in paths) {
      try {
        await store.deleteMedia(path);
      } on Object {
        // Conservative GC при следующем старте удалит файл-сироту; откат уже
        // зафиксированной операции БД из-за недоступного файла не выполняем.
      }
    }
  }

  Card _newCard({
    required String id,
    required String deckId,
    required String front,
    required String back,
    required CardDraft draft,
    required List<String> mediaIds,
    required String? siblingId,
    required DateTime now,
  }) {
    return Card(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      hint: draft.hint,
      cardType: draft.cardType,
      tags: draft.tags,
      mediaIds: List<String>.unmodifiable(mediaIds),
      latex: draft.latex,
      occlusionJson: draft.occlusionJson,
      sourceExcerpt: draft.sourceExcerpt,
      state: CardState.newCard,
      siblingId: siblingId,
      contentHash: contentHashOf(front: front, back: back),
      createdAt: now,
      updatedAt: now,
    );
  }
}

class _PreparedUpload {
  const _PreparedUpload({
    required this.id,
    required this.path,
    required this.mimeType,
    required this.bytes,
    required this.store,
  });

  final String id;
  final String path;
  final String mimeType;
  final Uint8List bytes;
  final MediaStore store;
}
