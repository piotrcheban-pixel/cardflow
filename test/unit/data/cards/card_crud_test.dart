import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/content_hash.dart';

import '../db/test_support.dart';

/// Красная фаза итерации 2: ручное создание/редактирование/удаление карточек
/// (SPEC A5, A6.3, ADR-009).
void main() {
  late AppDatabase db;
  late DriftCardRepository repository;
  final now = DateTime.utc(2026, 11, 13, 12);

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

  group('createCards', () {
    test('basic: одна строка, поля и content_hash (SPEC A5)', () async {
      final created = await repository.createCards(
        deckId: 'deck-1',
        draft: const CardDraft(
          front: 'Столица Франции?',
          back: 'Париж',
          hint: 'Город на Сене',
          tags: <String>['география', 'европа'],
          sourceExcerpt: 'Париж — столица Франции.',
        ),
        now: now,
      );

      expect(created, hasLength(1));
      final card = created.single;
      expect(card.deckId, 'deck-1');
      expect(card.front, 'Столица Франции?');
      expect(card.back, 'Париж');
      expect(card.hint, 'Город на Сене');
      expect(card.tags, <String>['география', 'европа']);
      expect(card.sourceExcerpt, 'Париж — столица Франции.');
      expect(card.cardType, CardType.basic);
      expect(card.state, CardState.newCard);
      expect(card.due, isNull);
      expect(card.fsrsJson, isNull);
      expect(card.suspended, isFalse);
      expect(card.createdAt, now);
      expect(card.updatedAt, now);
      expect(
        card.contentHash,
        contentHashOf(front: 'Столица Франции?', back: 'Париж'),
      );

      final fromDb = await repository.cardById(card.id);
      expect(fromDb, card);
    });

    test('черновик нормализуется перед записью (trim, теги)', () async {
      final created = await repository.createCards(
        deckId: 'deck-1',
        draft: const CardDraft(
          front: '  Вопрос  ',
          back: ' Ответ\n',
          tags: <String>[' #тег ', ''],
        ),
        now: now,
      );

      expect(created.single.front, 'Вопрос');
      expect(created.single.back, 'Ответ');
      expect(created.single.tags, <String>['тег']);
    });

    test(
      'basic_reversed: две строки с взаимными sibling_id (SPEC A5)',
      () async {
        final created = await repository.createCards(
          deckId: 'deck-1',
          draft: const CardDraft(
            front: 'Термин',
            back: 'Определение',
            cardType: CardType.basicReversed,
          ),
          now: now,
        );

        expect(created, hasLength(2));
        final first = created[0];
        final second = created[1];
        expect(first.cardType, CardType.basicReversed);
        expect(second.cardType, CardType.basicReversed);
        expect(first.front, 'Термин');
        expect(first.back, 'Определение');
        expect(second.front, 'Определение');
        expect(second.back, 'Термин');
        expect(first.siblingId, second.id);
        expect(second.siblingId, first.id);
        expect(first.createdAt, now);
        expect(second.createdAt, now);
        expect(
          first.contentHash,
          contentHashOf(front: 'Термин', back: 'Определение'),
        );
        expect(
          second.contentHash,
          contentHashOf(front: 'Определение', back: 'Термин'),
        );

        final rows = await repository.cardsByDeck('deck-1');
        expect(rows, hasLength(2));
        final byId = <String, Card>{
          for (final Card card in rows) card.id: card,
        };
        expect(byId[first.id]!.siblingId, second.id);
        expect(byId[second.id]!.siblingId, first.id);
      },
    );

    test('созданные basic_reversed-карточки видны в потоке колоды', () async {
      await repository.createCards(
        deckId: 'deck-1',
        draft: const CardDraft(
          front: 'А',
          back: 'Б',
          cardType: CardType.basicReversed,
        ),
        now: now,
      );

      final cards = await repository.watchCards('deck-1').first;
      expect(cards, hasLength(2));
    });
  });

  group('updateCard', () {
    late Card original;

    setUp(() async {
      original = (await repository.createCards(
        deckId: 'deck-1',
        draft: const CardDraft(
          front: 'Старый вопрос',
          back: 'Старый ответ',
          tags: <String>['старый'],
        ),
        now: now,
      )).single;
    });

    test('обновляет содержимое, хеш и updatedAt, сохраняя каркас', () async {
      final later = now.add(const Duration(hours: 1));
      final updated = await repository.updateCard(
        card: original,
        draft: const CardDraft(
          front: 'Новый вопрос',
          back: 'Новый ответ',
          hint: 'Новая подсказка',
          tags: <String>['новый', 'тег'],
          sourceExcerpt: 'Цитата',
        ),
        now: later,
      );

      expect(updated.id, original.id);
      expect(updated.deckId, original.deckId);
      expect(updated.front, 'Новый вопрос');
      expect(updated.back, 'Новый ответ');
      expect(updated.hint, 'Новая подсказка');
      expect(updated.tags, <String>['новый', 'тег']);
      expect(updated.sourceExcerpt, 'Цитата');
      expect(updated.cardType, original.cardType);
      expect(updated.createdAt, original.createdAt);
      expect(updated.updatedAt, later);
      expect(
        updated.contentHash,
        contentHashOf(front: 'Новый вопрос', back: 'Новый ответ'),
      );

      expect(await repository.cardById(original.id), updated);
    });

    test('тип карточки при редактировании не меняется (ADR-009)', () async {
      final updated = await repository.updateCard(
        card: original,
        draft: const CardDraft(
          front: 'Новый вопрос',
          back: 'Новый ответ',
          cardType: CardType.cloze,
        ),
        now: now,
      );
      expect(updated.cardType, CardType.basic);
    });

    test('несуществующая карточка — StateError', () async {
      final ghost = Card(
        id: 'ghost',
        deckId: 'deck-1',
        front: 'а',
        back: 'б',
        cardType: CardType.basic,
        state: CardState.newCard,
        createdAt: now,
        updatedAt: now,
      );

      expect(
        () => repository.updateCard(
          card: ghost,
          draft: const CardDraft(front: 'в', back: 'г'),
          now: now,
        ),
        throwsStateError,
      );
    });
  });

  group('deleteCard', () {
    test('удаляет строку; у парной карточки обнуляется sibling_id', () async {
      final pair = await repository.createCards(
        deckId: 'deck-1',
        draft: const CardDraft(
          front: 'А',
          back: 'Б',
          cardType: CardType.basicReversed,
        ),
        now: now,
      );
      final first = pair[0];
      final second = pair[1];

      await repository.deleteCard(first.id);

      expect(await repository.cardById(first.id), isNull);
      final remaining = await repository.cardById(second.id);
      expect(remaining, isNotNull);
      expect(remaining!.siblingId, isNull);
    });

    test('несуществующая карточка — тихий no-op', () async {
      await repository.deleteCard('нет-такой');
      expect(await repository.cardsByDeck('deck-1'), isEmpty);
    });
  });

  group('cardById', () {
    test('несуществующая — null', () async {
      expect(await repository.cardById('нет-такой'), isNull);
    });
  });

  group('валидация на границе data-слоя (L7 ревью)', () {
    test('createCards: пустой front — ArgumentError, строк нет', () async {
      await expectLater(
        repository.createCards(
          deckId: 'deck-1',
          draft: const CardDraft(front: '', back: 'Ответ'),
          now: now,
        ),
        throwsArgumentError,
      );
      expect(await repository.cardsByDeck('deck-1'), isEmpty);
    });

    test(
      'updateCard: превышение длины — ArgumentError, карточка не меняется',
      () async {
        final original = (await repository.createCards(
          deckId: 'deck-1',
          draft: const CardDraft(front: 'Вопрос', back: 'Ответ'),
          now: now,
        )).single;

        await expectLater(
          repository.updateCard(
            card: original,
            draft: CardDraft(front: 'а' * 501, back: 'Ответ'),
            now: now,
          ),
          throwsArgumentError,
        );
        expect(await repository.cardById(original.id), original);
      },
    );
  });
}
