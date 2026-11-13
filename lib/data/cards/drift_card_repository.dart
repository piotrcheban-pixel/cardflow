// Drift-реализация репозитория карточек (SPEC A5, A6.3, ADR-009).
//
// Чтение: список карточек экрана колоды, снимок для экспорта/сессии.
// Запись: ручное создание/редактирование/удаление; `basic_reversed` — две
// строки с взаимными `sibling_id` в одной транзакции.
//
// Маппинг строк — в `card_row_mapper.dart` (общий с `DriftReviewRepository`).
import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/cards/card_row_mapper.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/cards/content_hash.dart';

/// Репозиторий карточек поверх drift-БД.
class DriftCardRepository implements CardRepository {
  /// Создаёт репозиторий поверх БД.
  DriftCardRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

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
    if (!normalized.isValid) {
      throw ArgumentError.value(
        draft,
        'draft',
        'Некорректный черновик карточки: ${normalized.validate().values.join(', ')}',
      );
    }
    final DateTime utcNow = now.toUtc();
    return database.transaction<List<Card>>(() async {
      if (normalized.cardType == CardType.basicReversed) {
        final String firstId = _uuid.v4();
        final String secondId = _uuid.v4();
        final Card first = _newCard(
          id: firstId,
          deckId: deckId,
          front: normalized.front,
          back: normalized.back,
          draft: normalized,
          siblingId: secondId,
          now: utcNow,
        );
        final Card second = _newCard(
          id: secondId,
          deckId: deckId,
          front: normalized.back,
          back: normalized.front,
          draft: normalized,
          siblingId: firstId,
          now: utcNow,
        );
        await database.into(database.cards).insert(cardToCompanion(first));
        await database.into(database.cards).insert(cardToCompanion(second));
        return <Card>[first, second];
      }
      final Card card = _newCard(
        id: _uuid.v4(),
        deckId: deckId,
        front: normalized.front,
        back: normalized.back,
        draft: normalized,
        siblingId: null,
        now: utcNow,
      );
      await database.into(database.cards).insert(cardToCompanion(card));
      return <Card>[card];
    });
  }

  @override
  Future<Card> updateCard({
    required Card card,
    required CardDraft draft,
    required DateTime now,
  }) async {
    final DateTime utcNow = now.toUtc();
    return database.transaction<Card>(() async {
      final Card? existing = await cardById(card.id);
      if (existing == null) {
        throw StateError('Карточка не найдена: ${card.id}');
      }
      final CardDraft normalized = draft.normalized();
      if (!normalized.isValid) {
        throw ArgumentError.value(
          draft,
          'draft',
          'Некорректный черновик карточки: '
              '${normalized.validate().values.join(', ')}',
        );
      }
      final Card updated = Card(
        id: existing.id,
        deckId: existing.deckId,
        front: normalized.front,
        back: normalized.back,
        hint: normalized.hint,
        cardType: existing.cardType,
        tags: normalized.tags,
        mediaIds: existing.mediaIds,
        latex: existing.latex,
        occlusionJson: existing.occlusionJson,
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
        updatedAt: utcNow,
      );
      final int written =
          await (database.update(database.cards)
                ..where((table) => table.id.equals(existing.id)))
              .write(cardToCompanion(updated));
      if (written != 1) {
        throw StateError('Карточка не обновлена: ${card.id}');
      }
      return updated;
    });
  }

  @override
  Future<void> deleteCard(String cardId) {
    return database.transaction<void>(() async {
      final Card? existing = await cardById(cardId);
      if (existing == null) return;
      final String? siblingId = existing.siblingId;
      if (siblingId != null) {
        await (database.update(database.cards)
              ..where((table) => table.id.equals(siblingId)))
            .write(const CardsCompanion(siblingId: Value<String?>(null)));
      }
      await (database.delete(
        database.cards,
      )..where((table) => table.id.equals(cardId))).go();
    });
  }

  Card _newCard({
    required String id,
    required String deckId,
    required String front,
    required String back,
    required CardDraft draft,
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
      sourceExcerpt: draft.sourceExcerpt,
      state: CardState.newCard,
      siblingId: siblingId,
      contentHash: contentHashOf(front: front, back: back),
      createdAt: now,
      updatedAt: now,
    );
  }
}
