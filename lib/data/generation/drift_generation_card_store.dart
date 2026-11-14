/// Импорт сгенерированных карточек в drift-БД (SPEC A8.5 шаги 9–11, ADR-015).
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';

/// Импорт карточек поверх drift-БД.
///
/// Всё пишется одной транзакцией: создание/выбор колоды, дедупликация внутри
/// транзакции, карточки и обновление `generation_jobs.result_deck_id`.
/// `basic_reversed` создаёт две строки с взаимными `sibling_id` (SPEC A5).
class DriftGenerationCardStore implements GenerationCardStore {
  /// Создаёт хранилище поверх БД.
  DriftGenerationCardStore(this.database);

  /// БД приложения.
  final AppDatabase database;

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

    return database.transaction<GenerationImportResult>(() async {
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

      final Set<String> existing = await existingContentHashes(resolvedDeckId);
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
        await _insertCard(
          card: card,
          deckId: resolvedDeckId,
          epochNow: epochNow,
        );
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
  }

  /// Вставляет одну логическую карточку (для reversed — две строки).
  Future<void> _insertCard({
    required GeneratedCard card,
    required String deckId,
    required int epochNow,
  }) async {
    final String tagsJson = jsonEncode(card.tags);
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
              siblingId: firstId,
              epochNow: epochNow,
            ),
          );
      return;
    }
    await database
        .into(database.cards)
        .insert(
          _companion(
            id: _uuid.v4(),
            deckId: deckId,
            front: card.front,
            back: card.back,
            card: card,
            tagsJson: tagsJson,
            siblingId: null,
            epochNow: epochNow,
          ),
        );
  }

  /// Строка `cards` для новой сгенерированной карточки (SPEC A5).
  CardsCompanion _companion({
    required String id,
    required String deckId,
    required String front,
    required String back,
    required GeneratedCard card,
    required String tagsJson,
    required String? siblingId,
    required int epochNow,
  }) {
    return CardsCompanion.insert(
      id: id,
      deckId: deckId,
      front: front,
      back: back,
      hint: Value<String?>(card.hint),
      cardType: card.cardType.wireName,
      tagsJson: Value<String>(tagsJson),
      sourceExcerpt: Value<String?>(card.sourceExcerpt),
      state: CardState.newCard.wireName,
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
