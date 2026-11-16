/// Импорт сгенерированных карточек в drift-БД (SPEC A8.5 шаги 9–11, ADR-015).
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';

/// Импорт карточек поверх drift-БД.
///
/// Всё пишется одной транзакцией: создание/выбор колоды, дедупликация внутри
/// транзакции, карточки и обновление `generation_jobs.result_deck_id`.
/// `basic_reversed` создаёт две строки с взаимными `sibling_id` (SPEC A5).
class DriftGenerationCardStore implements GenerationCardStore {
  /// Создаёт хранилище поверх БД.
  ///
  /// [mediaStore] нужен для записи найденных иллюстраций (итерация 7.9).
  DriftGenerationCardStore(this.database, {this.mediaStore});

  /// БД приложения.
  final AppDatabase database;

  /// Файловое хранилище иллюстраций карточек.
  final MediaStore? mediaStore;

  static const Uuid _uuid = Uuid();

  @override
  Future<Set<String>> existingContentHashes(String deckId) async {
    final List<CardRow> rows = await (database.select(
      database.cards,
    )..where((table) => table.deckId.equals(deckId))).get();
    return _hashesOf(rows);
  }

  @override
  Future<GenerationImportResult> importGeneratedCards({
    required String? deckId,
    required String deckName,
    required List<GeneratedCard> cards,
    required String jobId,
    required DateTime now,
  }) async {
    if (cards.isEmpty) {
      return GenerationImportResult(
        deckId: deckId ?? '',
        importedCards: 0,
        skippedDuplicates: 0,
      );
    }
    final String trimmedName = deckName.trim();
    if (deckId == null && trimmedName.isEmpty) {
      throw ArgumentError.value(
        deckName,
        'deckName',
        'Имя новой колоды обязательно',
      );
    }
    final DateTime utcNow = now.toUtc();
    final int epochNow = toEpochMs(utcNow);

    final List<String> writtenPaths = <String>[];
    try {
      return await database.transaction<GenerationImportResult>(() async {
        final String resolvedDeckId;
        if (deckId == null) {
          resolvedDeckId = _uuid.v4();
          await database
              .into(database.decks)
              .insert(
                DecksCompanion.insert(
                  id: resolvedDeckId,
                  name: trimmedName,
                  createdAt: epochNow,
                  updatedAt: epochNow,
                ),
              );
        } else {
          final DeckRow? deck = await (database.select(
            database.decks,
          )..where((table) => table.id.equals(deckId))).getSingleOrNull();
          if (deck == null) {
            throw StateError('Колода не найдена: $deckId');
          }
          resolvedDeckId = deckId;
          await (database.update(database.decks)
                ..where((table) => table.id.equals(resolvedDeckId)))
              .write(DecksCompanion(updatedAt: Value<int>(epochNow)));
        }

        final Set<String> existing = await existingContentHashes(
          resolvedDeckId,
        );
        final List<GeneratedCard> accepted = <GeneratedCard>[];
        var skippedDuplicates = 0;
        for (final GeneratedCard card in cards) {
          if (_isDuplicate(card, existing)) {
            skippedDuplicates++;
            continue;
          }
          accepted.add(card);
        }

        for (final GeneratedCard card in accepted) {
          final _PreparedImage? image = await _writeImage(
            card.image,
            writtenPaths,
          );
          final String cardId = await _insertCard(
            card: card,
            deckId: resolvedDeckId,
            epochNow: epochNow,
            mediaId: image?.id,
          );
          if (image != null) await _insertMedia(image, cardId);
        }

        await (database.update(
          database.generationJobs,
        )..where((table) => table.id.equals(jobId))).write(
          GenerationJobsCompanion(resultDeckId: Value<String>(resolvedDeckId)),
        );

        return GenerationImportResult(
          deckId: resolvedDeckId,
          importedCards: accepted.length,
          skippedDuplicates: skippedDuplicates,
        );
      });
    } catch (_) {
      await _deleteFiles(writtenPaths);
      rethrow;
    }
  }

  /// Пишет иллюстрацию в `MediaStore` и готовит строку `media`.
  ///
  /// С 7.14 рядом с файлом пишутся метаданные атрибуции и флаг заглушки
  /// (`<путь>.meta.json`): провайдер, ссылка, автор, лицензия, запрос модели.
  Future<_PreparedImage?> _writeImage(
    GeneratedCardImage? image,
    List<String> writtenPaths,
  ) async {
    if (image == null) return null;
    final MediaStore? store = mediaStore;
    if (store == null) {
      throw StateError('MediaStore не настроен для иллюстрации карточки');
    }
    final String id = _uuid.v4();
    final String path = 'media/$id.${image.fileExtension}';
    await store.writeMedia(relativePath: path, bytes: image.bytes);
    writtenPaths.add(path);
    await store.writeMetadata(
      relativePath: path,
      metadata: MediaMetadata(
        provider: image.provider,
        sourceUrl: image.sourceUrl,
        author: image.author,
        license: image.license,
        isPlaceholder: image.isPlaceholder,
        query: image.query.trim().isEmpty ? null : image.query.trim(),
        fallbackQuery: image.fallbackQuery,
        kind: image.kind,
      ),
    );
    return _PreparedImage(
      id: id,
      path: path,
      mimeType: image.mimeType,
      size: image.bytes.length,
    );
  }

  /// Строка `media` для иллюстрации карточки.
  Future<void> _insertMedia(_PreparedImage image, String cardId) {
    return database
        .into(database.media)
        .insert(
          MediaCompanion(
            id: Value<String>(image.id),
            cardId: Value<String>(cardId),
            path: Value<String>(image.path),
            mimeType: Value<String>(image.mimeType),
            size: Value<int>(image.size),
          ),
        );
  }

  /// Удаляет записанные файлы после отката транзакции.
  Future<void> _deleteFiles(Iterable<String> paths) async {
    final MediaStore? store = mediaStore;
    if (store == null) return;
    for (final String path in paths) {
      try {
        await store.deleteMedia(path);
      } on Object {
        // Файл-сирота будет удалён консервативным GC при следующем старте.
      }
    }
  }

  /// Вставляет одну логическую карточку (для reversed — две строки).
  ///
  /// Возвращает id карточки-владельца media (для reversed — первую строку).
  Future<String> _insertCard({
    required GeneratedCard card,
    required String deckId,
    required int epochNow,
    required String? mediaId,
  }) async {
    final String tagsJson = jsonEncode(card.tags);
    final List<String> mediaIds = <String>[?mediaId];
    if (card.cardType == CardType.basicReversed) {
      final String firstId = _uuid.v4();
      final String secondId = _uuid.v4();
      await database
          .into(database.cards)
          .insert(
            _companion(
              id: firstId,
              deckId: deckId,
              front: card.front,
              back: card.back,
              card: card,
              tagsJson: tagsJson,
              mediaIds: mediaIds,
              siblingId: secondId,
              epochNow: epochNow,
            ),
          );
      await database
          .into(database.cards)
          .insert(
            _companion(
              id: secondId,
              deckId: deckId,
              front: card.back,
              back: card.front,
              card: card,
              tagsJson: tagsJson,
              mediaIds: mediaIds,
              siblingId: firstId,
              epochNow: epochNow,
            ),
          );
      return firstId;
    }
    final String cardId = _uuid.v4();
    await database
        .into(database.cards)
        .insert(
          _companion(
            id: cardId,
            deckId: deckId,
            front: card.front,
            back: card.back,
            card: card,
            tagsJson: tagsJson,
            mediaIds: mediaIds,
            siblingId: null,
            epochNow: epochNow,
          ),
        );
    return cardId;
  }

  /// Строка `cards` для новой сгенерированной карточки (SPEC A5).
  ///
  /// Итерация 7.11: `due` и `fsrs_json` заполняются начальным состоянием
  /// планировщика (`state = new`, шаг 0) сразу при импорте. Иначе новая
  /// карточка попадала в БД с `due = NULL`, и любой запрос «due <= now»
  /// (включая счётчики и будущие выборки) её не видел.
  CardsCompanion _companion({
    required String id,
    required String deckId,
    required String front,
    required String back,
    required GeneratedCard card,
    required String tagsJson,
    required List<String> mediaIds,
    required String? siblingId,
    required int epochNow,
  }) {
    final scheduling = CardSchedulingMapper.initialScheduling(
      cardId: id,
      now: fromEpochMs(epochNow),
    );
    return CardsCompanion.insert(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      hint: Value<String?>(card.hint),
      cardType: card.cardType.wireName,
      tagsJson: Value<String>(tagsJson),
      mediaJson: Value<String>(jsonEncode(mediaIds)),
      occlusionJson: Value<String?>(card.occlusionJson),
      sourceExcerpt: Value<String?>(card.sourceExcerpt),
      state: CardState.newCard.wireName,
      fsrsJson: Value<String?>(jsonEncode(scheduling.toJson())),
      due: Value<int?>(toEpochMs(scheduling.due)),
      siblingId: Value<String?>(siblingId),
      contentHash: Value<String>(contentHashOf(front: front, back: back)),
      createdAt: epochNow,
      updatedAt: epochNow,
    );
  }

  /// Проверяет дубликат и добавляет хеши карточки в [existing].
  ///
  /// Для `basic_reversed` учитываются обе стороны: парная карточка могла быть
  /// импортирована ранее отдельно.
  bool _isDuplicate(GeneratedCard card, Set<String> existing) {
    final String hash = contentHashOf(front: card.front, back: card.back);
    if (card.cardType == CardType.basicReversed) {
      final String reversed = contentHashOf(front: card.back, back: card.front);
      if (existing.contains(hash) || existing.contains(reversed)) return true;
      existing
        ..add(hash)
        ..add(reversed);
      return false;
    }
    if (existing.contains(hash)) return true;
    existing.add(hash);
    return false;
  }

  /// Хеши строк карточек; `content_hash = null` пересчитывается (M9).
  Set<String> _hashesOf(List<CardRow> rows) {
    final Set<String> hashes = <String>{};
    for (final CardRow row in rows) {
      final String? stored = row.contentHash;
      hashes.add(stored ?? contentHashOf(front: row.front, back: row.back));
    }
    return hashes;
  }
}

/// Подготовленная строка `media` для иллюстрации сгенерированной карточки.
class _PreparedImage {
  const _PreparedImage({
    required this.id,
    required this.path,
    required this.mimeType,
    required this.size,
  });

  final String id;
  final String path;
  final String mimeType;
  final int size;
}
