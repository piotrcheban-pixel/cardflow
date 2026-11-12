// Тесты DriftCardRepository: маппинг всех полей Card ↔ строка `cards`
// (SPEC A5), порядок и поток watchCards, снимок cardsByDeck.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/cards/card.dart';

import '../db/test_support.dart';

DateTime _utcFromMs(int milliseconds) =>
    DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);

void main() {
  late AppDatabase db;
  late DriftCardRepository repository;

  setUp(() async {
    db = AppDatabase.inMemory();
    repository = DriftCardRepository(db);
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
  });

  tearDown(() async {
    await db.close();
  });

  group('маппинг всех полей', () {
    test(
      'полная карточка: все поля, включая nullable/bool/JSON/даты',
      () async {
        await insertCardRow(
          db,
          id: 'card-full',
          deckId: 'deck-1',
          front: 'Вопрос',
          back: 'Ответ',
          hint: 'Подсказка',
          cardType: 'basic_reversed',
          tagsJson: '["тег1","тег2"]',
          mediaJson: '["media-1","media-2"]',
          latex: r'$x^2$',
          occlusionJson: '{"masks":[]}',
          sourceDocId: 'doc-1',
          sourceExcerpt: 'Цитата для «Почему?»',
          state: 'learning',
          fsrsJson: '{"stability":1.5}',
          due: 1234567890123,
          suspended: 1,
          buriedUntil: 1234567890222,
          flagged: 1,
          siblingId: 'card-pair',
          contentHash: 'hash-value',
          createdAt: 111,
          updatedAt: 222,
        );

        final cards = await repository.cardsByDeck('deck-1');

        expect(cards, hasLength(1));
        expect(
          cards.single,
          Card(
            id: 'card-full',
            deckId: 'deck-1',
            front: 'Вопрос',
            back: 'Ответ',
            hint: 'Подсказка',
            cardType: CardType.basicReversed,
            tags: const <String>['тег1', 'тег2'],
            mediaIds: const <String>['media-1', 'media-2'],
            latex: r'$x^2$',
            occlusionJson: '{"masks":[]}',
            sourceDocId: 'doc-1',
            sourceExcerpt: 'Цитата для «Почему?»',
            state: CardState.learning,
            fsrsJson: '{"stability":1.5}',
            due: _utcFromMs(1234567890123),
            suspended: true,
            buriedUntil: _utcFromMs(1234567890222),
            flagged: true,
            siblingId: 'card-pair',
            contentHash: 'hash-value',
            createdAt: _utcFromMs(111),
            updatedAt: _utcFromMs(222),
          ),
        );
      },
    );

    test(
      'минимальная карточка: nullable-поля null, bool false, списки пусты',
      () async {
        await insertCardRow(db, id: 'card-min', deckId: 'deck-1');

        final card = (await repository.cardsByDeck('deck-1')).single;

        expect(card.hint, isNull);
        expect(card.tags, isEmpty);
        expect(card.mediaIds, isEmpty);
        expect(card.latex, isNull);
        expect(card.occlusionJson, isNull);
        expect(card.sourceDocId, isNull);
        expect(card.sourceExcerpt, isNull);
        expect(card.fsrsJson, isNull);
        expect(card.due, isNull);
        expect(card.suspended, isFalse);
        expect(card.buriedUntil, isNull);
        expect(card.flagged, isFalse);
        expect(card.siblingId, isNull);
        expect(card.contentHash, isNull);
        expect(card.cardType, CardType.basic);
        expect(card.state, CardState.newCard);
        expect(card.createdAt, _utcFromMs(0));
        expect(card.updatedAt, _utcFromMs(0));
        expect(card.createdAt.isUtc, isTrue);
      },
    );

    test('все типы карточек и состояний разбираются из wire-имён', () async {
      await insertCardRow(
        db,
        id: 'card-cloze',
        deckId: 'deck-1',
        cardType: 'cloze',
        state: 'relearning',
      );
      await insertCardRow(
        db,
        id: 'card-reversed',
        deckId: 'deck-1',
        cardType: 'basic_reversed',
        state: 'review',
      );
      await insertCardRow(
        db,
        id: 'card-basic',
        deckId: 'deck-1',
        cardType: 'basic',
        state: 'learning',
      );

      final cards = {
        for (final card in await repository.cardsByDeck('deck-1'))
          card.id: card,
      };
      expect(cards['card-cloze']!.cardType, CardType.cloze);
      expect(cards['card-cloze']!.state, CardState.relearning);
      expect(cards['card-reversed']!.cardType, CardType.basicReversed);
      expect(cards['card-reversed']!.state, CardState.review);
      expect(cards['card-basic']!.cardType, CardType.basic);
      expect(cards['card-basic']!.state, CardState.learning);
    });
  });

  group('cardsByDeck', () {
    test('возвращает только карточки указанной колоды', () async {
      await insertDeckRow(
        db,
        id: 'deck-2',
        name: 'Другая',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertCardRow(db, id: 'card-1', deckId: 'deck-1');
      await insertCardRow(db, id: 'card-2', deckId: 'deck-2');

      final cards = await repository.cardsByDeck('deck-1');
      expect(cards.map((card) => card.id), <String>['card-1']);
    });

    test('пустая/несуществующая колода — пустой список', () async {
      expect(await repository.cardsByDeck('deck-1'), isEmpty);
      expect(await repository.cardsByDeck('нет-такой'), isEmpty);
    });
  });

  group('watchCards', () {
    test('порядок created_at ASC, при равенстве — id ASC', () async {
      await insertCardRow(
        db,
        id: 'card-c',
        deckId: 'deck-1',
        createdAt: 200,
        updatedAt: 200,
      );
      await insertCardRow(
        db,
        id: 'card-b',
        deckId: 'deck-1',
        createdAt: 100,
        updatedAt: 100,
      );
      await insertCardRow(
        db,
        id: 'card-a',
        deckId: 'deck-1',
        createdAt: 100,
        updatedAt: 100,
      );

      final cards = await repository.watchCards('deck-1').first;
      expect(cards.map((card) => card.id), <String>[
        'card-a',
        'card-b',
        'card-c',
      ]);
    });

    test('эмитит начальное значение и обновляется при вставке', () async {
      final emissions = <List<Card>>[];
      final subscription = repository
          .watchCards('deck-1')
          .listen(emissions.add);
      addTearDown(subscription.cancel);
      await pumpEventQueue();
      expect(emissions.last, isEmpty);

      await insertCardRow(db, id: 'card-1', deckId: 'deck-1');
      await pumpEventQueue();
      expect(emissions.last.map((card) => card.id), <String>['card-1']);

      await insertCardRow(
        db,
        id: 'card-2',
        deckId: 'deck-1',
        createdAt: 5,
        updatedAt: 5,
      );
      await pumpEventQueue();
      expect(emissions.last.map((card) => card.id), <String>[
        'card-1',
        'card-2',
      ]);
    });
  });
}
