import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Красная фаза итерации 4: сквозной сценарий ленты на реальной in-memory
/// drift-БД и production-графе провайдеров (SPEC A5/A7.3, ADR-016).
void main() {
  late AppDatabase db;
  late Directory mediaDirectory;
  late ProviderContainer container;
  final DateTime reviewTime = DateTime.utc(2026, 11, 14, 12);
  final DateTime createdTime = DateTime.utc(2026, 11, 14, 10);

  setUp(() {
    db = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_feed_');
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

  test('лента: оценка → review_logs.mode=feed → undo на реальной БД', () async {
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

    final cardRepository = container.read(cardRepositoryProvider);
    final reviewRepository = container.read(reviewRepositoryProvider);
    final scheduler = container.read(schedulerProvider);

    final first = (await cardRepository.createCards(
      deckId: 'deck-1',
      draft: const CardDraft(front: '¿Cómo estás?', back: 'Как дела?'),
      now: createdTime,
    )).single;
    final second = (await cardRepository.createCards(
      deckId: 'deck-1',
      draft: const CardDraft(front: 'Глагол ser', back: 'быть'),
      now: createdTime.add(const Duration(minutes: 1)),
    )).single;

    final cards = await cardRepository.cardsByDeck('deck-1');
    final engine = FeedSessionEngine(
      cards: cards,
      scheduler: scheduler,
      reviewRepository: reviewRepository,
      clock: () => reviewTime,
    );
    engine.start();
    expect(engine.state.total, 2);
    expect(engine.state.current!.card.id, first.id);

    expect(await engine.rate(Rating.good), isTrue);

    final logRows = await db.select(db.reviewLogs).get();
    expect(logRows, hasLength(1));
    expect(logRows.single.cardId, first.id);
    expect(logRows.single.rating, 3);
    expect(logRows.single.mode, reviewModeFeed);

    final updated = (await cardRepository.cardById(first.id))!;
    expect(updated.fsrsJson, isNotNull);
    expect(updated.due, isNotNull);

    expect(await engine.undo(), isTrue);
    expect(await db.select(db.reviewLogs).get(), isEmpty);
    final restored = (await cardRepository.cardById(first.id))!;
    // Итерация 7.11: у новой карточки уже есть начальное FSRS-состояние
    // (ADR-026), undo обязан восстановить именно его, а не NULL.
    expect(restored.fsrsJson, first.fsrsJson);
    expect(restored.due, first.due);
    expect(restored.state, CardState.newCard);
    expect(engine.state.current!.card.id, first.id);
    expect(engine.state.current!.revealed, isTrue);

    expect(second.id, isNot(first.id));
  });
}
