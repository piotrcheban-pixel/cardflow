// Тесты DriftDeckRepository: CRUD, архив, поиск/фильтры/порядок, счётчики,
// каскад, очистка медиа при удалении колоды (M5). Семантика — SPEC A6.2 +
// ADR-007 (см. domain/decks/deck_query.dart).
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/decks/drift_deck_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/decks/deck.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';

import '../db/test_support.dart';

/// Управляемые часы: детерминированные timestamps в тестах.
class _FakeClock {
  _FakeClock(this._current);

  DateTime _current;

  DateTime now() => _current;

  void advance(Duration duration) {
    _current = _current.add(duration);
  }

  int get nowMs => _current.millisecondsSinceEpoch;
}

final RegExp _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

void main() {
  late AppDatabase db;
  late _FakeClock clock;
  late DriftDeckRepository repository;

  setUp(() {
    db = AppDatabase.inMemory();
    clock = _FakeClock(DateTime.utc(2026, 1, 1, 12));
    repository = DriftDeckRepository(db, clock: clock.now);
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> summaryNames({
    DeckQuery query = const DeckQuery(),
  }) async {
    final summaries = await repository.watchSummaries(query: query).first;
    return summaries.map((summary) => summary.deck.name).toList();
  }

  group('createDeck', () {
    test(
      'создаёт колоду: UUID v4, trim имени, UTC-таймстемпы, пустые настройки',
      () async {
        final deck = await repository.createDeck(name: '  Испанский  ');

        expect(deck.name, 'Испанский');
        expect(_uuidV4.hasMatch(deck.id), isTrue, reason: 'id=${deck.id}');
        expect(deck.settings, isEmpty);
        expect(deck.createdAt, clock.now().toUtc());
        expect(deck.updatedAt, deck.createdAt);
        expect(deck.archivedAt, isNull);
        expect(deck.createdAt.isUtc, isTrue);

        // Колода реально сохранена и читается обратно без потерь.
        expect(await repository.deckById(deck.id), deck);
      },
    );

    test('пустое или пробельное имя — ArgumentError', () async {
      await expectLater(
        repository.createDeck(name: ''),
        throwsA(isA<ArgumentError>()),
      );
      await expectLater(
        repository.createDeck(name: '   '),
        throwsA(isA<ArgumentError>()),
      );
      expect(await db.select(db.decks).get(), isEmpty);
    });

    test('две колоды получают разные идентификаторы', () async {
      final first = await repository.createDeck(name: 'A');
      final second = await repository.createDeck(name: 'B');
      expect(first.id, isNot(second.id));
    });
  });

  group('renameDeck', () {
    test(
      'меняет имя, trim, обновляет updated_at, не трогает created_at',
      () async {
        final deck = await repository.createDeck(name: 'Старое');
        clock.advance(const Duration(seconds: 5));

        await repository.renameDeck(id: deck.id, name: '  Новое  ');

        final updated = await repository.deckById(deck.id);
        expect(updated, isNotNull);
        expect(updated!.name, 'Новое');
        expect(updated.updatedAt, clock.now().toUtc());
        expect(updated.createdAt, deck.createdAt);
        expect(updated.archivedAt, isNull);
      },
    );

    test('пустое имя — ArgumentError, имя в БД не меняется', () async {
      final deck = await repository.createDeck(name: 'Старое');
      await expectLater(
        repository.renameDeck(id: deck.id, name: '  '),
        throwsA(isA<ArgumentError>()),
      );
      expect((await repository.deckById(deck.id))!.name, 'Старое');
    });
  });

  group('archiveDeck / unarchiveDeck', () {
    test('архивирует: archived_at и updated_at, isArchived', () async {
      final deck = await repository.createDeck(name: 'Колода');
      clock.advance(const Duration(seconds: 1));

      await repository.archiveDeck(deck.id);

      final archived = await repository.deckById(deck.id);
      expect(archived!.isArchived, isTrue);
      expect(archived.archivedAt, clock.now().toUtc());
      expect(archived.updatedAt, clock.now().toUtc());
    });

    test(
      'повторная архивация идемпотентна: archived_at не перезаписывается',
      () async {
        final deck = await repository.createDeck(name: 'Колода');
        clock.advance(const Duration(seconds: 1));
        await repository.archiveDeck(deck.id);
        final firstArchive = (await repository.deckById(deck.id))!;

        clock.advance(const Duration(seconds: 10));
        await repository.archiveDeck(deck.id);

        final secondArchive = (await repository.deckById(deck.id))!;
        expect(secondArchive.archivedAt, firstArchive.archivedAt);
        expect(secondArchive.updatedAt, firstArchive.updatedAt);
      },
    );

    test('восстанавливает из архива идемпотентно', () async {
      final deck = await repository.createDeck(name: 'Колода');
      clock.advance(const Duration(seconds: 1));
      await repository.archiveDeck(deck.id);
      final archivedAt = (await repository.deckById(deck.id))!.archivedAt;

      clock.advance(const Duration(seconds: 1));
      await repository.unarchiveDeck(deck.id);

      final restored = (await repository.deckById(deck.id))!;
      expect(restored.isArchived, isFalse);
      expect(restored.archivedAt, isNull);
      expect(restored.updatedAt, clock.now().toUtc());

      // Повторное восстановление — no-op, updated_at не меняется.
      final updatedAfterRestore = restored.updatedAt;
      clock.advance(const Duration(seconds: 10));
      await repository.unarchiveDeck(deck.id);
      final afterSecond = (await repository.deckById(deck.id))!;
      expect(afterSecond.updatedAt, updatedAfterRestore);
      expect(archivedAt, isNotNull);
    });
  });

  group('deleteDeck', () {
    test('удаляет колоду и каскадно её карточки', () async {
      final deck = await repository.createDeck(name: 'Удаляемая');
      await insertCardRow(db, id: 'card-1', deckId: deck.id);
      await insertCardRow(db, id: 'card-2', deckId: deck.id);

      await repository.deleteDeck(deck.id);

      expect(await repository.deckById(deck.id), isNull);
      expect(await db.select(db.cards).get(), isEmpty);
    });

    test('удаление несуществующей колоды — no-op', () async {
      await repository.deleteDeck('нет-такой');
      expect(await db.select(db.decks).get(), isEmpty);
    });
  });

  group('deleteDeck: media-строки и файлы (M5)', () {
    late Directory mediaRoot;
    late MediaStore store;

    setUp(() async {
      mediaRoot = await Directory.systemTemp.createTemp('cardflow-media-test');
      store = MediaStore(mediaRoot);
    });

    tearDown(() async {
      if (await mediaRoot.exists()) {
        await mediaRoot.delete(recursive: true);
      }
    });

    /// Файл медиа на диске по относительному пути внутри хранилища.
    File mediaFile(String relativePath) =>
        File(p.joinAll(<String>[mediaRoot.path, ...relativePath.split('/')]));

    Future<void> writeMedia(String relativePath) => store.writeMedia(
      relativePath: relativePath,
      bytes: Uint8List.fromList(<int>[1, 2, 3]),
    );

    DriftDeckRepository repositoryWithMedia() =>
        DriftDeckRepository(db, clock: clock.now, mediaStore: store);

    test(
      'удаляет media-строки и файлы карточек колоды, не трогая соседние',
      () async {
        final mediaRepository = repositoryWithMedia();
        final deck = await mediaRepository.createDeck(name: 'С медиа');
        await insertCardRow(db, id: 'card-media-1', deckId: deck.id);
        await insertCardRow(db, id: 'card-media-2', deckId: deck.id);
        await writeMedia('card-media-1/picture.png');
        await writeMedia('card-media-2/voice.mp3');
        await insertMediaRow(
          db,
          id: 'media-1',
          cardId: 'card-media-1',
          path: 'card-media-1/picture.png',
        );
        await insertMediaRow(
          db,
          id: 'media-2',
          cardId: 'card-media-2',
          path: 'card-media-2/voice.mp3',
          mimeType: 'audio/mpeg',
        );

        final neighbour = await mediaRepository.createDeck(name: 'Соседняя');
        await insertCardRow(db, id: 'card-neighbour', deckId: neighbour.id);
        await writeMedia('card-neighbour/keep.png');
        await insertMediaRow(
          db,
          id: 'media-neighbour',
          cardId: 'card-neighbour',
          path: 'card-neighbour/keep.png',
        );

        await mediaRepository.deleteDeck(deck.id);

        final mediaRows = await db.select(db.media).get();
        expect(mediaRows.map((row) => row.id), <String>['media-neighbour']);
        expect((await db.select(db.cards).get()).map((row) => row.id), <String>[
          'card-neighbour',
        ]);
        expect(await mediaRepository.deckById(deck.id), isNull);

        expect(mediaFile('card-media-1/picture.png').existsSync(), isFalse);
        expect(mediaFile('card-media-2/voice.mp3').existsSync(), isFalse);
        expect(mediaFile('card-neighbour/keep.png').existsSync(), isTrue);
      },
    );

    test(
      'без mediaStore: media-строки удаляются, файлы остаются (best-effort)',
      () async {
        // `repository` из setUp создан без mediaStore — файлы удалить нечем.
        final deck = await repository.createDeck(name: 'Без хранилища');
        await insertCardRow(db, id: 'card-1', deckId: deck.id);
        await writeMedia('card-1/file.bin');
        await insertMediaRow(
          db,
          id: 'media-1',
          cardId: 'card-1',
          path: 'card-1/file.bin',
        );

        await repository.deleteDeck(deck.id);

        expect(await db.select(db.media).get(), isEmpty);
        expect(mediaFile('card-1/file.bin').existsSync(), isTrue);
      },
    );

    test(
      'удаление несуществующей колоды идемпотентно, медиа соседей не тронуты',
      () async {
        final mediaRepository = repositoryWithMedia();
        final neighbour = await mediaRepository.createDeck(name: 'Соседняя');
        await insertCardRow(db, id: 'card-neighbour', deckId: neighbour.id);
        await writeMedia('card-neighbour/keep.png');
        await insertMediaRow(
          db,
          id: 'media-neighbour',
          cardId: 'card-neighbour',
          path: 'card-neighbour/keep.png',
        );

        await mediaRepository.deleteDeck('нет-такой');
        await mediaRepository.deleteDeck('нет-такой');

        expect(await mediaRepository.deckById(neighbour.id), isNotNull);
        expect((await db.select(db.media).get()).single.id, 'media-neighbour');
        expect(mediaFile('card-neighbour/keep.png').existsSync(), isTrue);
      },
    );

    test('удаление терпимо к уже отсутствующему файлу медиа', () async {
      final mediaRepository = repositoryWithMedia();
      final deck = await mediaRepository.createDeck(name: 'Битое медиа');
      await insertCardRow(db, id: 'card-1', deckId: deck.id);
      // Файла на диске нет — удаление не должно падать.
      await insertMediaRow(
        db,
        id: 'media-missing',
        cardId: 'card-1',
        path: 'card-1/missing.png',
      );

      await mediaRepository.deleteDeck(deck.id);

      expect(await db.select(db.media).get(), isEmpty);
      expect(await mediaRepository.deckById(deck.id), isNull);
    });
  });

  group('deckById / watchDeck', () {
    test('deckById возвращает null для отсутствующей колоды', () async {
      expect(await repository.deckById('нет-такой'), isNull);
    });

    test('watchDeck: начальное значение и обновление после rename', () async {
      final deck = await repository.createDeck(name: 'Стрим');

      expect(await repository.watchDeck(deck.id).first, deck);

      final emissions = <Deck?>[];
      final subscription = repository.watchDeck(deck.id).listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last, deck);

      await repository.renameDeck(id: deck.id, name: 'Обновлённая');
      await pumpEventQueue();

      expect(emissions.length, greaterThanOrEqualTo(2));
      expect(emissions.last!.name, 'Обновлённая');
    });

    test('watchDeck удалённой колоды эмитит null', () async {
      final deck = await repository.createDeck(name: 'Удаляемая');
      final emissions = <Deck?>[];
      final subscription = repository.watchDeck(deck.id).listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();

      await repository.deleteDeck(deck.id);
      await pumpEventQueue();

      expect(emissions.last, isNull);
    });
  });

  group('watchSummaries: счётчики', () {
    test(
      'total/new/inProgress/due по карточкам (семантика DeckSummary)',
      () async {
        final deck = await repository.createDeck(name: 'Счётчики');
        final nowMs = clock.nowMs;

        // new: две (одна приостановлена) — счётчик состояния, как в контракте.
        await insertCardRow(db, id: 'c-new-1', deckId: deck.id, state: 'new');
        await insertCardRow(
          db,
          id: 'c-new-suspended',
          deckId: deck.id,
          state: 'new',
          suspended: 1,
        );
        // learning/relearning — «в процессе».
        await insertCardRow(
          db,
          id: 'c-learning',
          deckId: deck.id,
          state: 'learning',
          due: nowMs - 1000,
        );
        await insertCardRow(
          db,
          id: 'c-relearning-suspended',
          deckId: deck.id,
          state: 'relearning',
          due: nowMs - 1000,
          suspended: 1,
        );
        // review — не «в процессе»; due считается по due/suspended/buried.
        await insertCardRow(
          db,
          id: 'c-review-future',
          deckId: deck.id,
          state: 'review',
          due: nowMs + 100000,
        );
        await insertCardRow(
          db,
          id: 'c-review-buried-future',
          deckId: deck.id,
          state: 'review',
          due: nowMs - 1000,
          buriedUntil: nowMs + 100000,
        );
        await insertCardRow(
          db,
          id: 'c-review-buried-past',
          deckId: deck.id,
          state: 'review',
          due: nowMs - 1000,
          buriedUntil: nowMs - 500,
        );

        final summary = (await repository.watchSummaries().first).single;
        expect(summary.totalCards, 7);
        expect(summary.newCards, 2);
        expect(summary.inProgressCards, 2);
        // Просрочены: c-learning и c-review-buried-past.
        // c-relearning-suspended — suspended; c-review-buried-future — buried.
        expect(summary.dueCards, 2);
        expect(summary.hasCards, isTrue);
      },
    );

    test('пустая колода: все счётчики нулевые', () async {
      await repository.createDeck(name: 'Пустая');
      final summary = (await repository.watchSummaries().first).single;
      expect(summary.totalCards, 0);
      expect(summary.newCards, 0);
      expect(summary.inProgressCards, 0);
      expect(summary.dueCards, 0);
      expect(summary.hasCards, isFalse);
    });

    test('счётчики обновляются при изменении карточек (watch)', () async {
      final deck = await repository.createDeck(name: 'Живая');
      final emissions = <List<DeckSummary>>[];
      final subscription = repository.watchSummaries().listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last.single.totalCards, 0);

      await insertCardRow(db, id: 'card-1', deckId: deck.id);
      await pumpEventQueue();
      expect(emissions.last.single.totalCards, 1);
      expect(emissions.last.single.newCards, 1);

      await insertCardRow(
        db,
        id: 'card-2',
        deckId: deck.id,
        state: 'review',
        due: clock.nowMs - 1,
      );
      await pumpEventQueue();
      expect(emissions.last.single.totalCards, 2);
      expect(emissions.last.single.dueCards, 1);
    });
  });

  group('watchSummaries: поиск', () {
    setUp(() async {
      await insertDeckRow(
        db,
        id: 'deck-es',
        name: 'Испанский',
        createdAt: 1,
        updatedAt: 100,
      );
      await insertDeckRow(
        db,
        id: 'deck-yo',
        name: 'Испанский ёж',
        createdAt: 1,
        updatedAt: 200,
      );
      await insertDeckRow(
        db,
        id: 'deck-fr',
        name: 'Французский',
        createdAt: 1,
        updatedAt: 50,
      );
    });

    test('без поиска — все активные колоды', () async {
      expect(
        (await repository.watchSummaries().first).map((s) => s.deck.id),
        <String>['deck-yo', 'deck-es', 'deck-fr'],
      );
    });

    test('регистронезависимый поиск', () async {
      final result = await repository
          .watchSummaries(query: const DeckQuery(search: 'ИСПАНСКИЙ'))
          .first;
      expect(result.map((s) => s.deck.id), <String>['deck-yo', 'deck-es']);
    });

    test('ё и е считаются одной буквой', () async {
      final result = await repository
          .watchSummaries(query: const DeckQuery(search: 'еж'))
          .first;
      expect(result.map((s) => s.deck.id), <String>['deck-yo']);
    });

    test('поиск по подстроке и пунктуации', () async {
      final result = await repository
          .watchSummaries(query: const DeckQuery(search: 'пански!'))
          .first;
      expect(result.map((s) => s.deck.id), <String>['deck-yo', 'deck-es']);
    });

    test('нет совпадений — пустой список', () async {
      expect(
        await repository
            .watchSummaries(query: const DeckQuery(search: 'немецкий'))
            .first,
        isEmpty,
      );
    });
  });

  group('watchSummaries: фильтры и архив', () {
    setUp(() async {
      final nowMs = clock.nowMs;
      // deck-new: есть новая карточка.
      await insertDeckRow(
        db,
        id: 'deck-new',
        name: 'С новыми',
        createdAt: 1,
        updatedAt: 100,
      );
      await insertCardRow(db, id: 'c-new', deckId: 'deck-new', state: 'new');
      // deck-progress: карточка в процессе и просрочена.
      await insertDeckRow(
        db,
        id: 'deck-progress',
        name: 'В процессе',
        createdAt: 1,
        updatedAt: 200,
      );
      await insertCardRow(
        db,
        id: 'c-learning',
        deckId: 'deck-progress',
        state: 'learning',
        due: nowMs - 1000,
      );
      // deck-review: карточка в повторении, не просрочена.
      await insertDeckRow(
        db,
        id: 'deck-review',
        name: 'В повторении',
        createdAt: 1,
        updatedAt: 300,
      );
      await insertCardRow(
        db,
        id: 'c-review',
        deckId: 'deck-review',
        state: 'review',
        due: nowMs + 100000,
      );
      // deck-archived: архивная, в ней есть новая карточка.
      await insertDeckRow(
        db,
        id: 'deck-archived',
        name: 'Архивная',
        archivedAt: 50,
        createdAt: 1,
        updatedAt: 50,
      );
      await insertCardRow(
        db,
        id: 'c-archived-new',
        deckId: 'deck-archived',
        state: 'new',
      );
    });

    test('all: только активные, порядок updated_at DESC', () async {
      expect(
        (await repository.watchSummaries().first).map((s) => s.deck.id),
        <String>['deck-review', 'deck-progress', 'deck-new'],
      );
    });

    test(
      'includeArchived показывает архивные последними по updated_at',
      () async {
        expect(
          (await repository
                  .watchSummaries(query: const DeckQuery(includeArchived: true))
                  .first)
              .map((s) => s.deck.id),
          <String>['deck-review', 'deck-progress', 'deck-new', 'deck-archived'],
        );
      },
    );

    test('withNewCards: колоды с newCards > 0', () async {
      expect(
        (await repository
                .watchSummaries(
                  query: const DeckQuery(filter: DeckFilter.withNewCards),
                )
                .first)
            .map((s) => s.deck.id),
        <String>['deck-new'],
      );
      expect(
        (await repository
                .watchSummaries(
                  query: const DeckQuery(
                    filter: DeckFilter.withNewCards,
                    includeArchived: true,
                  ),
                )
                .first)
            .map((s) => s.deck.id),
        <String>['deck-new', 'deck-archived'],
      );
    });

    test('inProgress: колоды с learning/relearning', () async {
      expect(
        (await repository
                .watchSummaries(
                  query: const DeckQuery(filter: DeckFilter.inProgress),
                )
                .first)
            .map((s) => s.deck.id),
        <String>['deck-progress'],
      );
    });

    test('due: колоды с просроченными карточками', () async {
      expect(
        (await repository
                .watchSummaries(query: const DeckQuery(filter: DeckFilter.due))
                .first)
            .map((s) => s.deck.id),
        <String>['deck-progress'],
      );
    });

    test('поиск и фильтр комбинируются', () async {
      expect(
        await repository
            .watchSummaries(
              query: const DeckQuery(search: 'процесс', filter: DeckFilter.due),
            )
            .first,
        hasLength(1),
      );
    });

    test('фильтр all не показывает архивные по умолчанию', () async {
      final result = await repository
          .watchSummaries(query: const DeckQuery(filter: DeckFilter.all))
          .first;
      expect(result.map((s) => s.deck.id), isNot(contains('deck-archived')));
    });
  });

  group('watchSummaries: порядок', () {
    test('updatedAt DESC, при равенстве — имя по возрастанию', () async {
      await insertDeckRow(
        db,
        id: 'deck-beta',
        name: 'Бета',
        createdAt: 1,
        updatedAt: 100,
      );
      await insertDeckRow(
        db,
        id: 'deck-alpha',
        name: 'Альфа',
        createdAt: 1,
        updatedAt: 100,
      );
      await insertDeckRow(
        db,
        id: 'deck-gamma',
        name: 'Гамма',
        createdAt: 1,
        updatedAt: 300,
      );

      expect(await summaryNames(), <String>['Гамма', 'Альфа', 'Бета']);
    });
  });
}
