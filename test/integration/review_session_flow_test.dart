import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/review/drift_review_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Красная фаза итерации 2: сквозной сценарий классической сессии на реальной
/// in-memory drift-БД и production-графе провайдеров (урок итерации 1: фикс
/// должен быть подтверждён на боевой проводке, а не только unit-тестами).
void main() {
  late AppDatabase db;
  late Directory mediaDirectory;
  late ProviderContainer container;
  final reviewTime = DateTime.utc(2026, 11, 13, 12);
  final createdTime = DateTime.utc(2026, 11, 13, 10);

  setUp(() {
    db = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_review_');
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

  Future<void> seedDeck() async {
    await db
        .into(db.decks)
        .insert(
          DecksCompanion.insert(
            id: 'deck-1',
            name: 'Испанский',
            createdAt: createdTime.millisecondsSinceEpoch,
            updatedAt: createdTime.millisecondsSinceEpoch,
          ),
        );
  }

  test('граф провайдеров итерации 2: реальные реализации', () {
    expect(container.read(cardRepositoryProvider), isA<DriftCardRepository>());
    expect(
      container.read(reviewRepositoryProvider),
      isA<DriftReviewRepository>(),
    );
    expect(container.read(schedulerProvider), isA<FsrsScheduler>());
  });

  test('создание карточек → очередь → оценка → undo на реальной БД', () async {
    await seedDeck();
    final cardRepository = container.read(cardRepositoryProvider);
    final reviewRepository = container.read(reviewRepositoryProvider);
    final scheduler = container.read(schedulerProvider);

    final first = (await cardRepository.createCards(
      deckId: 'deck-1',
      draft: const CardDraft(
        front: '¿Cómo estás?',
        back: 'Как дела?',
        tags: <String>['приветствие'],
      ),
      now: createdTime,
    )).single;
    final second = (await cardRepository.createCards(
      deckId: 'deck-1',
      draft: const CardDraft(front: 'Глагол ser', back: 'быть'),
      now: createdTime.add(const Duration(minutes: 1)),
    )).single;

    // Вторую карточку делаем просроченной (состояние review, как после
    // прошлых повторений): fsrs_json + due согласованы.
    final seededReview = SchedulingCard(
      cardId: second.id,
      state: CardState.review,
      stability: 10,
      difficulty: 5,
      due: reviewTime.subtract(const Duration(hours: 1)),
      lastReview: reviewTime.subtract(const Duration(days: 10)),
    );
    await (db.update(db.cards)..where((t) => t.id.equals(second.id))).write(
      CardsCompanion(
        state: Value(seededReview.state.wireName),
        fsrsJson: Value(jsonEncode(seededReview.toJson())),
        due: Value(seededReview.due.millisecondsSinceEpoch),
      ),
    );

    final cards = await cardRepository.cardsByDeck('deck-1');
    expect(cards, hasLength(2));
    final queue = ReviewQueue.build(cards, now: reviewTime);
    expect(queue.map((Card card) => card.id), <String>[
      second.id,
      first.id,
    ], reason: 'сначала просроченная, затем новая (ADR-008)');

    final target = queue.first;
    final before = cards.singleWhere((Card card) => card.id == target.id);
    final scheduling = CardSchedulingMapper.toSchedulingCard(
      target,
      now: reviewTime,
    );
    final outcome = scheduler
        .review(scheduling, Rating.good, now: reviewTime)
        .card;
    final undo = await reviewRepository.recordReview(
      cardId: target.id,
      rating: Rating.good,
      reviewedAt: reviewTime,
      outcome: outcome,
      mode: reviewModeClassic,
      elapsed: const Duration(seconds: 4),
    );

    final logRows = await db.select(db.reviewLogs).get();
    expect(logRows, hasLength(1));
    expect(logRows.single.cardId, target.id);
    expect(logRows.single.rating, 3);
    expect(logRows.single.mode, reviewModeClassic);
    expect(logRows.single.elapsedMs, 4000);

    final updated = (await cardRepository.cardById(target.id))!;
    expect(updated.state.wireName, outcome.state.wireName);
    expect(updated.due, outcome.due);
    expect(updated.fsrsJson, isNotNull);

    await reviewRepository.undoReview(undo);
    expect(await db.select(db.reviewLogs).get(), isEmpty);
    final restored = (await cardRepository.cardById(target.id))!;
    expect(restored.state, before.state);
    expect(restored.due, before.due);
    expect(restored.fsrsJson, before.fsrsJson);
  });

  test(
    'H1: оценка → export → import → сессия импортированной колоды работает',
    () async {
      await seedDeck();
      final cardRepository = container.read(cardRepositoryProvider);
      final reviewRepository = container.read(reviewRepositoryProvider);
      final scheduler = container.read(schedulerProvider);
      final transfer = container.read(deckTransferServiceProvider);

      final card = (await cardRepository.createCards(
        deckId: 'deck-1',
        draft: const CardDraft(front: 'Вопрос', back: 'Ответ'),
        now: createdTime,
      )).single;
      final scheduling = CardSchedulingMapper.toSchedulingCard(
        card,
        now: reviewTime,
      );
      await reviewRepository.recordReview(
        cardId: card.id,
        rating: Rating.good,
        reviewedAt: reviewTime,
        outcome: scheduler
            .review(scheduling, Rating.good, now: reviewTime)
            .card,
        mode: reviewModeClassic,
      );

      final bytes = await transfer.exportDeckZip('deck-1');
      final imported = await transfer.importZip(bytes);

      final importedCards = await cardRepository.cardsByDeck(imported.deckId);
      expect(importedCards, hasLength(1));
      final importedCard = importedCards.single;
      expect(importedCard.id, isNot(card.id));
      final importedScheduling = CardSchedulingMapper.toSchedulingCard(
        importedCard,
        now: reviewTime.add(const Duration(days: 1)),
      );
      expect(
        importedScheduling.cardId,
        importedCard.id,
        reason: 'fsrs_json перепривязан к новому id (H1 ревью)',
      );

      // Сессия на импортированной колоде: карточка due (learning через 10 мин)
      // при часах на сутки позже — очередь берёт её, движок стартует и пишет.
      final later = reviewTime.add(const Duration(days: 1));
      final importedCardsLater = await cardRepository.cardsByDeck(
        imported.deckId,
      );
      final queue = ReviewQueue.build(importedCardsLater, now: later);
      expect(queue.map((Card item) => item.id), <String>[importedCard.id]);

      final engine = ReviewSessionEngine(
        cards: importedCardsLater,
        scheduler: scheduler,
        reviewRepository: reviewRepository,
        clock: () => later,
      );
      engine.start();
      expect(engine.state.total, 1);
      expect(await engine.rate(Rating.good), isTrue);
      expect(await db.select(db.reviewLogs).get(), hasLength(2));
    },
  );
}
