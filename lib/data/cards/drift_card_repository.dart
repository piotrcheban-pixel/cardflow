// Drift-реализация репозитория карточек (SPEC A5, A6.3).
//
// В итерации 1 репозиторий только читает: список карточек экрана колоды и
// снимок для экспорта. Запись карточек появится в итерациях 2/5.
//
// Маппинг: `tags_json`/`media_json` — JSON-массивы строк; `suspended`/`flagged` —
// INTEGER 0/1 ↔ bool; `due`/`buried_until`/`created_at`/`updated_at` — epoch ms
// UTC ↔ DateTime; `fsrs_json`/`occlusion_json` — сырые строки (разбор — итерации 2/5).
import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_repository.dart';

/// Репозиторий карточек поверх drift-БД.
class DriftCardRepository implements CardRepository {
  /// Создаёт репозиторий поверх БД.
  DriftCardRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Stream<List<Card>> watchCards(String deckId) {
    final query = database.select(database.cards)
      ..where((table) => table.deckId.equals(deckId))
      ..orderBy(<OrderingTerm Function($CardsTable)>[
        (table) => OrderingTerm.asc(table.createdAt),
        (table) => OrderingTerm.asc(table.id),
      ]);
    return query.watch().map(
      (rows) => rows.map(_cardFromRow).toList(growable: false),
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
    return rows.map(_cardFromRow).toList(growable: false);
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

  /// JSON-массив строк (SPEC A5: `tags_json`/`media_json`).
  List<String> _decodeStringList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw FormatException('Ожидался JSON-массив строк, получено: $raw');
    }
    return decoded
        .map((value) {
          if (value is! String) {
            throw FormatException('Элемент JSON-массива не строка: $raw');
          }
          return value;
        })
        .toList(growable: false);
  }
}
