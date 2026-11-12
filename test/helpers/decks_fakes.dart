import 'dart:async';
import 'dart:typed_data';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/text/normalization.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';

/// Фейковые реализации domain-контрактов для widget-тестов UI.
///
/// Тесты не поднимают drift/БД, file_picker и сеть: вся работа с данными идёт
/// через эти фейки, подменяющие провайдеры в `ProviderScope(overrides: …)`.

/// Базовый момент времени для детерминированных тестов.
final DateTime fixturesNow = DateTime(2026, 11, 12, 12);

/// Создаёт колоду-фикстуру.
Deck makeDeck({
  required String id,
  required String name,
  DateTime? archivedAt,
  Map<String, Object?> settings = const <String, Object?>{},
}) {
  return Deck(
    id: id,
    name: name,
    settings: settings,
    createdAt: fixturesNow,
    updatedAt: fixturesNow,
    archivedAt: archivedAt,
  );
}

/// Создаёт сводку колоды-фикстуры с явными счётчиками.
DeckSummary makeSummary({
  required String id,
  required String name,
  int totalCards = 0,
  int newCards = 0,
  int inProgressCards = 0,
  int dueCards = 0,
  DateTime? archivedAt,
}) {
  return DeckSummary(
    deck: makeDeck(id: id, name: name, archivedAt: archivedAt),
    totalCards: totalCards,
    newCards: newCards,
    inProgressCards: inProgressCards,
    dueCards: dueCards,
  );
}

/// Создаёт карточку-фикстуру.
Card makeCard({
  required String id,
  required String deckId,
  required String front,
  String back = 'Ответ',
  CardType cardType = CardType.basic,
  CardState state = CardState.newCard,
  List<String> tags = const <String>[],
  DateTime? due,
}) {
  return Card(
    id: id,
    deckId: deckId,
    front: front,
    back: back,
    cardType: cardType,
    state: state,
    tags: tags,
    due: due,
    createdAt: fixturesNow,
    updatedAt: fixturesNow,
  );
}

/// Фейковый репозиторий колод: in-memory данные, потоки, журнал вызовов.
class FakeDeckRepository implements DeckRepository {
  /// Создаёт фейк с колодами [summaries].
  FakeDeckRepository({List<DeckSummary> summaries = const <DeckSummary>[]})
    : _summaries = <DeckSummary>[...summaries];

  final List<DeckSummary> _summaries;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Сколько раз создавали поток сводок (для проверки retry).
  int watchSummariesCalls = 0;

  /// Сколько раз подписывались на колоду.
  int watchDeckCalls = 0;

  /// Поток сводок никогда не эмитит (проверка loading-состояния).
  bool stallSummaries = false;

  /// Поток сводок эмитит ошибку (проверка error-состояния).
  bool failSummaries = false;

  /// Поток колоды эмитит ошибку (проверка ошибки на экране колоды).
  bool failDeck = false;

  /// Id архивных колод по порядку.
  final List<String> archivedIds = <String>[];

  /// Id восстановленных из архива колод по порядку.
  final List<String> unarchivedIds = <String>[];

  /// Id удалённых колод по порядку.
  final List<String> deletedIds = <String>[];

  /// Id переименованных колод по порядку.
  final List<String> renamedIds = <String>[];

  /// Новые имена при переименовании (в порядке вызовов).
  final List<String> renamedNames = <String>[];

  /// Имена созданных колод (в порядке вызовов).
  final List<String> createdNames = <String>[];

  int _createdCounter = 0;

  /// Текущие данные без учёта запроса.
  List<DeckSummary> get allSummaries =>
      List<DeckSummary>.unmodifiable(_summaries);

  List<DeckSummary> _query(DeckQuery query) {
    final String search = query.normalizedSearch;
    return _summaries.where((DeckSummary summary) {
      if (!query.includeArchived && summary.deck.isArchived) return false;
      if (search.isNotEmpty &&
          !normalizeForComparison(summary.deck.name).contains(search)) {
        return false;
      }
      return switch (query.filter) {
        DeckFilter.all => true,
        DeckFilter.withNewCards => summary.newCards > 0,
        DeckFilter.inProgress => summary.inProgressCards > 0,
        DeckFilter.due => summary.dueCards > 0,
      };
    }).toList();
  }

  Deck? _deckOf(String id) {
    for (final DeckSummary summary in _summaries) {
      if (summary.deck.id == id) return summary.deck;
    }
    return null;
  }

  void _replaceSummary(String id, DeckSummary Function(DeckSummary) update) {
    final int index = _summaries.indexWhere(
      (DeckSummary summary) => summary.deck.id == id,
    );
    if (index < 0) return;
    _summaries[index] = update(_summaries[index]);
  }

  void _emit() {
    if (!_changes.isClosed) _changes.add(null);
  }

  @override
  Stream<List<DeckSummary>> watchSummaries({
    DeckQuery query = const DeckQuery(),
  }) async* {
    watchSummariesCalls++;
    if (failSummaries) {
      throw StateError('boom: поток сводок недоступен');
    }
    if (stallSummaries) {
      await Completer<void>().future;
    }
    yield _query(query);
    await for (final void _ in _changes.stream) {
      yield _query(query);
    }
  }

  @override
  Stream<Deck?> watchDeck(String id) async* {
    watchDeckCalls++;
    if (failDeck) {
      throw StateError('boom: поток колоды недоступен');
    }
    yield _deckOf(id);
    await for (final void _ in _changes.stream) {
      yield _deckOf(id);
    }
  }

  @override
  Future<Deck?> deckById(String id) async => _deckOf(id);

  @override
  Future<Deck> createDeck({required String name}) async {
    final String trimmed = name.trim();
    createdNames.add(trimmed);
    final Deck deck = makeDeck(
      id: 'created-${++_createdCounter}',
      name: trimmed,
    );
    _summaries.add(DeckSummary(deck: deck));
    _emit();
    return deck;
  }

  @override
  Future<void> renameDeck({required String id, required String name}) async {
    renamedIds.add(id);
    renamedNames.add(name.trim());
    _replaceSummary(
      id,
      (DeckSummary summary) => DeckSummary(
        deck: summary.deck.copyWith(name: name.trim()),
        totalCards: summary.totalCards,
        newCards: summary.newCards,
        inProgressCards: summary.inProgressCards,
        dueCards: summary.dueCards,
      ),
    );
    _emit();
  }

  @override
  Future<void> archiveDeck(String id) async {
    archivedIds.add(id);
    _replaceSummary(
      id,
      (DeckSummary summary) => DeckSummary(
        deck: summary.deck.copyWith(archivedAt: DateTime(2026, 11, 12, 13)),
        totalCards: summary.totalCards,
        newCards: summary.newCards,
        inProgressCards: summary.inProgressCards,
        dueCards: summary.dueCards,
      ),
    );
    _emit();
  }

  @override
  Future<void> unarchiveDeck(String id) async {
    unarchivedIds.add(id);
    _replaceSummary(
      id,
      (DeckSummary summary) => DeckSummary(
        deck: summary.deck.copyWith(archivedAt: null),
        totalCards: summary.totalCards,
        newCards: summary.newCards,
        inProgressCards: summary.inProgressCards,
        dueCards: summary.dueCards,
      ),
    );
    _emit();
  }

  @override
  Future<void> deleteDeck(String id) async {
    deletedIds.add(id);
    _summaries.removeWhere((DeckSummary summary) => summary.deck.id == id);
    _emit();
  }
}

/// Фейковый репозиторий карточек: in-memory список на колоду.
class FakeCardRepository implements CardRepository {
  /// Создаёт фейк с карточками [cards].
  FakeCardRepository({List<Card> cards = const <Card>[]})
    : _cards = <Card>[...cards];

  final List<Card> _cards;
  final StreamController<void> _changes = StreamController<void>.broadcast();

  List<Card> _byDeck(String deckId) =>
      _cards.where((Card card) => card.deckId == deckId).toList();

  @override
  Stream<List<Card>> watchCards(String deckId) async* {
    yield _byDeck(deckId);
    await for (final void _ in _changes.stream) {
      yield _byDeck(deckId);
    }
  }

  @override
  Future<List<Card>> cardsByDeck(String deckId) async => _byDeck(deckId);
}

/// Фейковый сервис импорта/экспорта: настраиваемые результаты и ошибки.
class FakeDeckTransferService implements DeckTransferService {
  /// Байты, которые вернёт экспорт.
  Uint8List exportBytes = Uint8List.fromList(<int>[1, 2, 3, 4, 250]);

  /// Ошибка экспорта (бросается, если задана).
  Object? exportError;

  /// Предпросмотр импорта по умолчанию.
  ImportPreview preview = const ImportPreview(
    deckName: 'Импортированная колода',
    formatVersion: 1,
    cardsCount: 5,
    duplicatesCount: 2,
    mediaCount: 1,
  );

  /// Ошибка предпросмотра импорта.
  Object? previewError;

  /// Результат импорта.
  ImportResult importResult = const ImportResult(
    deckId: 'imported-deck',
    importedCards: 3,
    skippedDuplicates: 2,
    importedMedia: 1,
  );

  /// Ошибка импорта.
  Object? importError;

  /// Id колод, для которых вызван экспорт.
  final List<String> exportedDeckIds = <String>[];

  /// Сколько раз вызывался предпросмотр импорта.
  int previewCalls = 0;

  /// Сколько раз вызывался импорт.
  int importCalls = 0;

  /// Имя, переданное в `importZip(deckName:)` при последнем импорте.
  String? lastImportDeckName;

  @override
  Future<Uint8List> exportDeckZip(String deckId) async {
    exportedDeckIds.add(deckId);
    if (exportError != null) throw exportError!;
    return exportBytes;
  }

  @override
  Future<ImportPreview> previewImport(Uint8List zipBytes) async {
    previewCalls++;
    if (previewError != null) throw previewError!;
    return preview;
  }

  @override
  Future<ImportResult> importZip(Uint8List zipBytes, {String? deckName}) async {
    importCalls++;
    lastImportDeckName = deckName;
    if (importError != null) throw importError!;
    return importResult;
  }
}

/// Фейковый файловый шлюз: настраиваемые пути/байты/ошибки и журнал вызовов.
class FakeFileGateway implements FileGateway {
  /// Путь, который вернёт пикер импорта; `null` — пользователь отменил выбор.
  String? importPath = '/tmp/deck.zip';

  /// Байты, которые вернёт `readFile`.
  Uint8List importBytes = Uint8List.fromList(<int>[10, 20, 30]);

  /// Ошибка чтения файла.
  Object? readError;

  /// Результат сохранения: `false` — пользователь отменил диалог сохранения.
  bool saveResult = true;

  /// Ошибка сохранения файла.
  Object? saveError;

  /// Сколько раз открывали пикер импорта.
  int pickImportCalls = 0;

  /// Сколько раз вызывалось сохранение ZIP.
  int saveCalls = 0;

  /// Последнее предложенное имя файла для сохранения.
  String? lastSuggestedFileName;

  /// Байты последнего сохранения (null, если сохранение отменено/не было).
  Uint8List? lastSavedBytes;

  @override
  Future<String?> pickZipToImport() async {
    pickImportCalls++;
    return importPath;
  }

  @override
  Future<bool> saveZipFile({
    required String suggestedFileName,
    required Uint8List bytes,
  }) async {
    saveCalls++;
    lastSuggestedFileName = suggestedFileName;
    if (saveError != null) throw saveError!;
    if (!saveResult) return false;
    lastSavedBytes = bytes;
    return true;
  }

  @override
  Future<Uint8List> readFile(String path) async {
    if (readError != null) throw readError!;
    return importBytes;
  }
}
