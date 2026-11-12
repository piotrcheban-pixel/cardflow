// Drift-реализация репозитория колод (SPEC A5, A6.2; семантика — ADR-007).
//
// Источник правды для списка колод — SQL-выборка с агрегатами по `cards`
// (счётчики total/new/inProgress/due). Стрим пересчитывается drift'ом при
// изменении любой из таблиц `decks`/`cards` (`readsFrom`).
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/text/normalization.dart';

/// Репозиторий колод поверх drift-БД.
class DriftDeckRepository implements DeckRepository {
  /// Создаёт репозиторий поверх БД.
  ///
  /// [clock] — источник текущего времени (для детерминированных тестов);
  /// по умолчанию — `DateTime.now`.
  ///
  /// [mediaStore] — хранилище медиафайлов: при удалении колоды (SPEC A5, M5)
  /// после коммита best-effort удаляются файлы медиа. Если `null`, строки
  /// `media` из БД всё равно удаляются, а файлы на диске остаются (известное
  /// поведение без доступа к хранилищу).
  DriftDeckRepository(
    this.database, {
    DateTime Function()? clock,
    this.mediaStore,
  }) : _clock = clock ?? DateTime.now;

  /// БД приложения.
  final AppDatabase database;

  final DateTime Function() _clock;

  /// Хранилище медиафайлов; `null` — файлы при удалении колоды не трогаются
  /// (строки `media` из БД удаляются всегда).
  final MediaStore? mediaStore;

  static const Uuid _uuid = Uuid();

  /// Сводки по колодам со счётчиками карточек (SPEC A5, A6.2/A6.3).
  ///
  /// `?` — два параметра `due <= now` (один и тот же момент).
  static const String _summariesSql = '''
SELECT
  d.id            AS deck_id,
  d.name          AS deck_name,
  d.settings_json AS deck_settings_json,
  d.archived_at   AS deck_archived_at,
  d.created_at    AS deck_created_at,
  d.updated_at    AS deck_updated_at,
  COUNT(c.id)     AS total_cards,
  COALESCE(SUM(CASE WHEN c.state = 'new' THEN 1 ELSE 0 END), 0)
                  AS new_cards,
  COALESCE(SUM(CASE WHEN c.state IN ('learning', 'relearning') THEN 1 ELSE 0 END), 0)
                  AS in_progress_cards,
  COALESCE(SUM(
    CASE WHEN c.due IS NOT NULL
      AND c.due <= ?
      AND c.suspended = 0
      AND (c.buried_until IS NULL OR c.buried_until <= ?)
    THEN 1 ELSE 0 END), 0)
                  AS due_cards
FROM decks d
LEFT JOIN cards c ON c.deck_id = d.id
GROUP BY d.id
''';

  @override
  Stream<List<DeckSummary>> watchSummaries({
    DeckQuery query = const DeckQuery(),
  }) {
    final nowMs = toEpochMs(_nowUtc());
    return database
        .customSelect(
          _summariesSql,
          variables: <Variable<Object>>[
            Variable.withInt(nowMs),
            Variable.withInt(nowMs),
          ],
          readsFrom: <ResultSetImplementation>{database.decks, database.cards},
        )
        .watch()
        .map((rows) {
          final summaries = rows.map(_summaryFromQueryRow).toList();
          return _applyQuery(summaries, query);
        });
  }

  @override
  Stream<Deck?> watchDeck(String id) {
    final query = database.select(database.decks)
      ..where((table) => table.id.equals(id));
    return query.watchSingleOrNull().map(
      (row) => row == null ? null : _deckFromRow(row),
    );
  }

  @override
  Future<Deck?> deckById(String id) async {
    final query = database.select(database.decks)
      ..where((table) => table.id.equals(id));
    final row = await query.getSingleOrNull();
    return row == null ? null : _deckFromRow(row);
  }

  @override
  Future<Deck> createDeck({required String name}) async {
    final trimmed = _validateName(name);
    final now = _nowUtc();
    final deck = Deck(
      id: _uuid.v4(),
      name: trimmed,
      settings: const <String, Object?>{},
      createdAt: now,
      updatedAt: now,
    );
    await database
        .into(database.decks)
        .insert(
          DecksCompanion.insert(
            id: deck.id,
            name: deck.name,
            createdAt: toEpochMs(now),
            updatedAt: toEpochMs(now),
          ),
        );
    return deck;
  }

  @override
  Future<void> renameDeck({required String id, required String name}) async {
    final trimmed = _validateName(name);
    final nowMs = toEpochMs(_nowUtc());
    await _updateDeck(
      where: (table) => table.id.equals(id),
      companion: DecksCompanion(
        name: Value<String>(trimmed),
        updatedAt: Value<int>(nowMs),
      ),
    );
  }

  @override
  Future<void> archiveDeck(String id) async {
    final nowMs = toEpochMs(_nowUtc());
    // Условие `archived_at IS NULL` делает операцию идемпотентной: повторная
    // архивация не перезаписывает момент архивации.
    await _updateDeck(
      where: (table) => table.id.equals(id) & table.archivedAt.isNull(),
      companion: DecksCompanion(
        archivedAt: Value<int?>(nowMs),
        updatedAt: Value<int>(nowMs),
      ),
    );
  }

  @override
  Future<void> unarchiveDeck(String id) async {
    final nowMs = toEpochMs(_nowUtc());
    await _updateDeck(
      where: (table) => table.id.equals(id) & table.archivedAt.isNotNull(),
      companion: DecksCompanion(
        archivedAt: Value<int?>(null),
        updatedAt: Value<int>(nowMs),
      ),
    );
  }

  @override
  Future<void> deleteDeck(String id) async {
    // M5: `media` не связан с `cards` внешним ключом (SPEC A5), поэтому строки
    // медиа удаляем явно — до удаления колоды (карточки удалит каскад FK).
    // В одной транзакции собираем пути файлов, чтобы после коммита удалить их
    // best-effort через MediaStore.
    final mediaPaths = await database.transaction<List<String>>(() async {
      final cards = await (database.select(
        database.cards,
      )..where((table) => table.deckId.equals(id))).get();
      final cardIds = cards.map((card) => card.id).toList(growable: false);
      final List<String> paths;
      if (cardIds.isEmpty) {
        paths = const <String>[];
      } else {
        final mediaRows = await (database.select(
          database.media,
        )..where((table) => table.cardId.isIn(cardIds))).get();
        paths = mediaRows.map((row) => row.path).toList(growable: false);
        await (database.delete(
          database.media,
        )..where((table) => table.cardId.isIn(cardIds))).go();
      }
      // Карточки удаляются каскадом средствами SQLite (`ON DELETE CASCADE`,
      // FK включены в `AppDatabase.beforeOpen`).
      await (database.delete(
        database.decks,
      )..where((table) => table.id.equals(id))).go();
      return paths;
    });

    final store = mediaStore;
    if (store == null || mediaPaths.isEmpty) {
      return;
    }
    // Файлы удаляются только после успешного коммита БД: ошибка файловой
    // системы не должна откатывать удаление колоды.
    await Future.wait<void>(<Future<void>>[
      for (final path in mediaPaths) _deleteMediaFile(store, path),
    ]);
  }

  /// Best-effort удаление файла медиа: ошибки не ломают [deleteDeck].
  ///
  /// Строки `media` к этому моменту уже удалены коммитом; файл мог быть удалён
  /// ранее, путь — устаревшим/небезопасным, либо файловая система недоступна.
  Future<void> _deleteMediaFile(MediaStore store, String path) async {
    try {
      await store.deleteMedia(path);
    } catch (_) {
      // Намеренно проглатываем: очистка «висящих» файлов не критична.
      return;
    }
  }

  /// Текущий момент в UTC с точностью до миллисекунд (как в БД SPEC A5).
  DateTime _nowUtc() => fromEpochMs(toEpochMs(_clock()));

  Future<void> _updateDeck({
    required Expression<bool> Function($DecksTable table) where,
    required DecksCompanion companion,
  }) {
    final statement = database.update(database.decks)
      ..where((table) => where(table));
    return statement.write(companion);
  }

  String _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        name,
        'name',
        'Имя колоды не может быть пустым',
      );
    }
    return trimmed;
  }

  Deck _deckFromRow(DeckRow row) => Deck(
    id: row.id,
    name: row.name,
    settings: _decodeSettings(row.settingsJson),
    createdAt: fromEpochMs(row.createdAt),
    updatedAt: fromEpochMs(row.updatedAt),
    archivedAt: row.archivedAt == null ? null : fromEpochMs(row.archivedAt!),
  );

  DeckSummary _summaryFromQueryRow(QueryRow row) {
    final archivedAt = row.readNullable<int>('deck_archived_at');
    final deck = Deck(
      id: row.read<String>('deck_id'),
      name: row.read<String>('deck_name'),
      settings: _decodeSettings(row.read<String>('deck_settings_json')),
      createdAt: fromEpochMs(row.read<int>('deck_created_at')),
      updatedAt: fromEpochMs(row.read<int>('deck_updated_at')),
      archivedAt: archivedAt == null ? null : fromEpochMs(archivedAt),
    );
    return DeckSummary(
      deck: deck,
      totalCards: row.read<int>('total_cards'),
      newCards: row.read<int>('new_cards'),
      inProgressCards: row.read<int>('in_progress_cards'),
      dueCards: row.read<int>('due_cards'),
    );
  }

  Map<String, Object?> _decodeSettings(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, Object?>) return decoded;
    throw FormatException('settings_json колоды — не JSON-объект: $raw');
  }

  /// Поиск/фильтр/порядок списка колод (ADR-007).
  ///
  /// Поиск идёт по нормализованному имени (`normalizeForComparison`): регистр,
  /// `ё`/`е` и пунктуация не влияют; сравнение — подстрока. Архивные колоды
  /// скрыты, если `query.includeArchived == false`. Порядок: `updated_at` DESC,
  /// при равенстве — имя по возрастанию.
  List<DeckSummary> _applyQuery(List<DeckSummary> summaries, DeckQuery query) {
    final normalizedSearch = query.normalizedSearch;
    final filtered = summaries.where((summary) {
      final deck = summary.deck;
      if (!query.includeArchived && deck.isArchived) {
        return false;
      }
      if (normalizedSearch.isNotEmpty &&
          !normalizeForComparison(deck.name).contains(normalizedSearch)) {
        return false;
      }
      return switch (query.filter) {
        DeckFilter.all => true,
        DeckFilter.withNewCards => summary.newCards > 0,
        DeckFilter.inProgress => summary.inProgressCards > 0,
        DeckFilter.due => summary.dueCards > 0,
      };
    }).toList();

    filtered.sort((first, second) {
      final byUpdatedAt = second.deck.updatedAt.compareTo(first.deck.updatedAt);
      if (byUpdatedAt != 0) return byUpdatedAt;
      return first.deck.name.compareTo(second.deck.name);
    });
    return filtered;
  }
}
