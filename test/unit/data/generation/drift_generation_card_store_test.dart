import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';
import 'package:cardflow/domain/cards/content_hash.dart';
import 'package:cardflow/domain/cards/occlusion.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generated_card_image_side.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_job.dart';

import '../../data/db/test_support.dart';

GeneratedCard cardOf(
  String front, {
  String back = 'Ответ',
  CardType cardType = CardType.basic,
}) {
  return GeneratedCard(front: front, back: back, cardType: cardType);
}

void main() {
  late AppDatabase db;
  late DriftGenerationCardStore store;
  late DriftGenerationJobRepository jobs;
  final now = DateTime.utc(2026, 11, 14, 10);

  setUp(() async {
    db = AppDatabase.inMemory();
    store = DriftGenerationCardStore(db);
    jobs = DriftGenerationJobRepository(db);
    await jobs.save(
      GenerationJob(
        id: 'job-1',
        status: GenerationJobStatus.done,
        createdAt: now,
        promptVersion: 'gen-ru-v2',
      ),
    );
  });

  tearDown(() async {
    await db.close();
  });

  test('existingContentHashes: хеши карточек колоды', () async {
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Вопрос',
      back: 'Ответ',
      contentHash: contentHashOf(front: 'Вопрос', back: 'Ответ'),
    );
    await insertDeckRow(
      db,
      id: 'deck-2',
      name: 'Другая',
      createdAt: 1,
      updatedAt: 1,
    );
    await insertCardRow(
      db,
      id: 'card-2',
      deckId: 'deck-2',
      front: 'Чужой',
      back: 'Ответ',
      contentHash: contentHashOf(front: 'Чужой', back: 'Ответ'),
    );

    final hashes = await store.existingContentHashes('deck-1');
    expect(hashes, contains(contentHashOf(front: 'Вопрос', back: 'Ответ')));
    expect(
      hashes,
      isNot(contains(contentHashOf(front: 'Чужой', back: 'Ответ'))),
    );
  });

  test('импорт в новую колоду: колода, карточки, хеши, job', () async {
    final result = await store.importGeneratedCards(
      deckId: null,
      deckName: '  Новая колода  ',
      cards: <GeneratedCard>[
        cardOf('Вопрос 1', back: 'Ответ 1'),
        cardOf('Вопрос 2', back: 'Ответ 2'),
      ],
      jobId: 'job-1',
      now: now,
    );

    expect(result.deckId, isNotEmpty);
    expect(result.importedCards, 2);
    expect(result.skippedDuplicates, 0);

    final deckRows = await db.select(db.decks).get();
    expect(deckRows, hasLength(1));
    expect(deckRows.single.id, result.deckId);
    expect(deckRows.single.name, 'Новая колода');

    final cardRows = await db.select(db.cards).get();
    expect(cardRows, hasLength(2));
    for (final row in cardRows) {
      expect(row.deckId, result.deckId);
      expect(row.state, 'new');
      expect(row.contentHash, isNotNull);
      // Итерация 7.11: импорт пишет начальное FSRS-состояние новой карточки.
      expect(row.fsrsJson, isNotNull);
      expect(row.due, isNotNull);
      expect(row.due, lessThanOrEqualTo(toEpochMs(now)));
    }
    expect(cardRows.map((row) => row.contentHash).toSet(), <String>{
      contentHashOf(front: 'Вопрос 1', back: 'Ответ 1'),
      contentHashOf(front: 'Вопрос 2', back: 'Ответ 2'),
    });

    final job = (await jobs.jobById('job-1'))!;
    expect(job.resultDeckId, result.deckId);
    // A5: cards_count — «сколько получено моделью», импорт его не перезаписывает.
    expect(job.cardsCount, isNull);
  });

  test('импорт в существующую колоду: дополняет, дубли пропускает', () async {
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Колода',
      createdAt: 1,
      updatedAt: 1,
    );
    await insertCardRow(
      db,
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Вопрос 1',
      back: 'Ответ 1',
      contentHash: contentHashOf(front: 'Вопрос 1', back: 'Ответ 1'),
    );

    final result = await store.importGeneratedCards(
      deckId: 'deck-1',
      deckName: 'Игнорируется',
      cards: <GeneratedCard>[
        cardOf('Вопрос 1', back: 'Ответ 1'),
        cardOf('Вопрос 2', back: 'Ответ 2'),
      ],
      jobId: 'job-1',
      now: now,
    );

    expect(result.deckId, 'deck-1');
    expect(result.importedCards, 1);
    expect(result.skippedDuplicates, 1);
    final cardRows = await db.select(db.cards).get();
    expect(cardRows, hasLength(2));
    expect(cardRows.where((row) => row.front == 'Вопрос 2'), hasLength(1));
    final deckRows = await db.select(db.decks).get();
    expect(deckRows, hasLength(1), reason: 'новая колода не создаётся');
  });

  test('дубли внутри пакета отсеиваются, первый выигрывает', () async {
    final result = await store.importGeneratedCards(
      deckId: null,
      deckName: 'Колода',
      cards: <GeneratedCard>[
        cardOf('Вопрос', back: 'Ответ'),
        cardOf('Вопрос', back: 'Ответ'),
      ],
      jobId: 'job-1',
      now: now,
    );

    expect(result.importedCards, 1);
    expect(result.skippedDuplicates, 1);
    expect(await db.select(db.cards).get(), hasLength(1));
  });

  test('basic_reversed создаёт две строки с взаимными sibling_id', () async {
    await store.importGeneratedCards(
      deckId: null,
      deckName: 'Колода',
      cards: <GeneratedCard>[
        cardOf('Термин', back: 'Определение', cardType: CardType.basicReversed),
      ],
      jobId: 'job-1',
      now: now,
    );

    final rows = await db.select(db.cards).get();
    expect(rows, hasLength(2));
    expect(rows.map((row) => row.front).toSet(), <String>{
      'Термин',
      'Определение',
    });
    final bySibling = <String, String>{};
    for (final row in rows) {
      expect(row.siblingId, isNotNull);
      bySibling[row.id] = row.siblingId!;
    }
    for (final entry in bySibling.entries) {
      expect(bySibling[entry.value], entry.key);
    }
    expect(await jobs.jobById('job-1'), isNotNull);
  });

  test(
    'basic_reversed не создаёт дубль, если обратная сторона уже есть',
    () async {
      await insertDeckRow(
        db,
        id: 'deck-1',
        name: 'Колода',
        createdAt: 1,
        updatedAt: 1,
      );
      await insertCardRow(
        db,
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Определение',
        back: 'Термин',
        contentHash: contentHashOf(front: 'Определение', back: 'Термин'),
      );

      final result = await store.importGeneratedCards(
        deckId: 'deck-1',
        deckName: 'Колода',
        cards: <GeneratedCard>[
          cardOf(
            'Термин',
            back: 'Определение',
            cardType: CardType.basicReversed,
          ),
        ],
        jobId: 'job-1',
        now: now,
      );

      expect(result.importedCards, 0);
      expect(result.skippedDuplicates, 1);
      expect(await db.select(db.cards).get(), hasLength(1));
    },
  );

  test('пустой список карточек — колода не создаётся', () async {
    final result = await store.importGeneratedCards(
      deckId: null,
      deckName: 'Колода',
      cards: const <GeneratedCard>[],
      jobId: 'job-1',
      now: now,
    );
    expect(result.importedCards, 0);
    expect(await db.select(db.decks).get(), isEmpty);
  });

  test(
    'несуществующая целевая колода — StateError, карточки не пишутся',
    () async {
      await expectLater(
        store.importGeneratedCards(
          deckId: 'нет',
          deckName: 'Колода',
          cards: <GeneratedCard>[cardOf('Вопрос')],
          jobId: 'job-1',
          now: now,
        ),
        throwsStateError,
      );
      expect(await db.select(db.cards).get(), isEmpty);
    },
  );

  group('картинки и occlusion при импорте (итерация 7.9)', () {
    late Directory temp;
    late MediaStore media;

    setUp(() {
      temp = Directory.systemTemp.createTempSync('cardflow_gen_media_');
      media = MediaStore(temp);
    });

    tearDown(() {
      if (temp.existsSync()) temp.deleteSync(recursive: true);
    });

    GeneratedCard cardWithImage({
      String front = 'Что на схеме?',
      String query = 'photosynthesis diagram',
      bool isOcclusion = false,
      String? occlusionJson,
    }) {
      return GeneratedCard(
        front: front,
        back: 'Фотосинтез',
        cardType: CardType.basic,
        imageQuery: query,
        imageKind: GeneratedCardImageKind.photo,
        imageSide: GeneratedCardImageSide.question,
        isOcclusion: isOcclusion,
        occlusionJson: occlusionJson,
        questionImages: <GeneratedCardImage>[
          GeneratedCardImage(
            bytes: Uint8List.fromList(<int>[0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3]),
            mediaType: AttachmentMediaType.jpeg,
            query: query,
          ),
        ],
      );
    }

    test('картинка пишется в MediaStore, media_json привязан', () async {
      final storeWithMedia = DriftGenerationCardStore(db, mediaStore: media);
      final card = cardWithImage();

      await storeWithMedia.importGeneratedCards(
        deckId: null,
        deckName: 'Колода',
        cards: <GeneratedCard>[card],
        jobId: 'job-1',
        now: now,
      );

      final List<MediaRow> mediaRows = await db.select(db.media).get();
      expect(mediaRows, hasLength(1));
      final MediaRow row = mediaRows.single;
      expect(row.mimeType, 'image/jpeg');
      expect(row.size, card.image!.bytes.length);

      final Uint8List? stored = await media.readMedia(row.path);
      expect(stored, card.image!.bytes);

      final CardRow cardRow = (await db.select(db.cards).get()).single;
      final CardMediaSides sides = CardMediaSides.decode(cardRow.mediaJson);
      expect(sides.question, <String>[row.id]);
      expect(sides.answer, isEmpty);
      expect(cardRow.occlusionJson, isNull);
      expect(row.cardId, cardRow.id);
    });

    test('occlusion_json сохраняется, карточка остаётся basic', () async {
      final storeWithMedia = DriftGenerationCardStore(db, mediaStore: media);
      final String masks = defaultOcclusionDocumentJson();
      final card = cardWithImage(isOcclusion: true, occlusionJson: masks);

      await storeWithMedia.importGeneratedCards(
        deckId: null,
        deckName: 'Колода',
        cards: <GeneratedCard>[card],
        jobId: 'job-1',
        now: now,
      );

      final CardRow cardRow = (await db.select(db.cards).get()).single;
      expect(cardRow.cardType, 'basic');
      expect(cardRow.occlusionJson, masks);
      final CardMediaSides occluded = CardMediaSides.decode(cardRow.mediaJson);
      expect(occluded.question, hasLength(1));
      expect(occluded.answer, isEmpty);
      expect(await db.select(db.media).get(), hasLength(1));
    });

    test('карточка без картинки не создаёт media', () async {
      final storeWithMedia = DriftGenerationCardStore(db, mediaStore: media);
      await storeWithMedia.importGeneratedCards(
        deckId: null,
        deckName: 'Колода',
        cards: <GeneratedCard>[cardOf('Вопрос')],
        jobId: 'job-1',
        now: now,
      );
      expect(await db.select(db.media).get(), isEmpty);
      final CardMediaSides empty = CardMediaSides.decode(
        (await db.select(db.cards).get()).single.mediaJson,
      );
      expect(empty.isEmpty, isTrue);
    });

    test('картинка без MediaStore — StateError и откат', () async {
      await expectLater(
        store.importGeneratedCards(
          deckId: null,
          deckName: 'Колода',
          cards: <GeneratedCard>[cardWithImage()],
          jobId: 'job-1',
          now: now,
        ),
        throwsStateError,
      );
      expect(await db.select(db.cards).get(), isEmpty);
      expect(await db.select(db.media).get(), isEmpty);
      expect(await db.select(db.decks).get(), isEmpty);
    });
  });
}
