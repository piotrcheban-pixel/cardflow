import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/review/drift_leech_repository.dart';
import 'package:cardflow/data/session/drift_session_preset_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/review/review.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/session/leech_repository.dart';
import 'package:cardflow/domain/session/session_builder.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_plan.dart';
import 'package:cardflow/domain/session/session_preset.dart';
import 'package:cardflow/ui/review/feed_session_engine.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../unit/data/db/test_support.dart';

/// Интеграция итерации 6 (SPEC A6.7/A7.19/A7.20, ADR-018) на production-графе
/// `app_providers` и реальной drift-БД: счётчики провалов → сборка плана →
/// пресет в `session_presets` → запись оценок движками классики и ленты.
void main() {
  late AppDatabase db;
  late Directory mediaDirectory;
  late ProviderContainer container;
  final DateTime now = DateTime.utc(2026, 11, 14, 12);
  final int nowMs = now.millisecondsSinceEpoch;

  setUp(() async {
    db = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_session_');
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(db),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
      ],
    );
    await insertDeckRow(
      db,
      id: 'deck-1',
      name: 'Испанский',
      createdAt: nowMs,
      updatedAt: nowMs,
    );
    await insertDeckRow(
      db,
      id: 'deck-2',
      name: 'Биология',
      createdAt: nowMs,
      updatedAt: nowMs,
    );
  });

  tearDown(() async {
    container.dispose();
    await db.close();
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

  test('граф провайдеров итерации 6: реальные реализации', () {
    expect(
      container.read(sessionPresetRepositoryProvider),
      isA<DriftSessionPresetRepository>(),
    );
    expect(
      container.read(leechRepositoryProvider),
      isA<DriftLeechRepository>(),
    );
  });

  test('пиявки → фильтр плана → оценки классики в порядке плана', () async {
    await insertCardRow(
      db,
      id: 'leech',
      deckId: 'deck-1',
      front: 'Пиявка',
      state: 'review',
      due: nowMs - 3600000,
      createdAt: nowMs,
      updatedAt: nowMs,
    );
    await insertCardRow(
      db,
      id: 'fresh',
      deckId: 'deck-2',
      front: 'Новая',
      createdAt: nowMs + 1000,
      updatedAt: nowMs + 1000,
    );
    for (int index = 0; index < 8; index++) {
      await db
          .into(db.reviewLogs)
          .insert(
            ReviewLogsCompanion.insert(
              id: 'log-$index',
              cardId: 'leech',
              rating: 1,
              reviewedAt: nowMs - index * 1000,
              mode: 'classic',
            ),
          );
    }

    final Map<String, int> counts = await container
        .read(leechRepositoryProvider)
        .failureCounts(deckIds: <String>['deck-1', 'deck-2']);
    expect(counts, <String, int>{'leech': 8});

    final List<DeckSummary> summaries = await container
        .read(deckRepositoryProvider)
        .watchSummaries(query: const DeckQuery())
        .first;
    expect(summaries, hasLength(2));

    final List<Card> cards = <Card>[
      ...await container.read(cardRepositoryProvider).cardsByDeck('deck-1'),
      ...await container.read(cardRepositoryProvider).cardsByDeck('deck-2'),
    ];
    const SessionConfig config = SessionConfig(
      deckIds: <String>['deck-1', 'deck-2'],
      states: <SessionStateFilter>{SessionStateFilter.leeches},
    );
    final List<Card> leeches = SessionBuilder.select(
      cards: cards,
      config: config,
      failureCounts: counts,
      now: now,
    );
    expect(leeches.map((Card card) => card.id), <String>['leech']);

    final SessionPlan plan = SessionBuilder.plan(
      cards: cards,
      config: config.copyWith(
        states: const <SessionStateFilter>{
          SessionStateFilter.leeches,
          SessionStateFilter.newCards,
        },
      ),
      failureCounts: counts,
      now: now,
    );
    expect(plan.cards.map((Card card) => card.id), <String>['leech', 'fresh']);

    final ReviewSessionEngine engine = ReviewSessionEngine(
      cards: plan.cards,
      scheduler: container.read(schedulerProvider),
      reviewRepository: container.read(reviewRepositoryProvider),
      clock: () => now,
      prebuilt: true,
    );
    engine.start();
    expect(engine.state.total, 2);
    expect(engine.state.current!.card.id, 'leech');
    expect(await engine.rate(Rating.good), isTrue);
    expect(engine.state.current!.card.id, 'fresh');

    final List<ReviewLogRow> logs = await db.select(db.reviewLogs).get();
    expect(logs, hasLength(9), reason: '8 провалов + 1 новая оценка');
    final ReviewLogRow latest = logs.reduce(
      (ReviewLogRow a, ReviewLogRow b) =>
          a.reviewedAt > b.reviewedAt ? a : b,
    );
    expect(latest.cardId, 'leech');
    expect(latest.rating, 3);
    expect(latest.mode, reviewModeClassic);
  });

  test('лента по плану пишет mode=feed', () async {
    await insertCardRow(
      db,
      id: 'unique',
      deckId: 'deck-1',
      front: 'Вопрос',
      createdAt: nowMs,
      updatedAt: nowMs,
    );
    final SessionPlan plan = SessionBuilder.plan(
      cards: await container
          .read(cardRepositoryProvider)
          .cardsByDeck('deck-1'),
      config: const SessionConfig(
        deckIds: <String>['deck-1'],
        mode: SessionMode.feed,
      ),
      failureCounts: const <String, int>{},
      now: now,
    );
    expect(plan.mode, SessionMode.feed);

    final FeedSessionEngine engine = FeedSessionEngine(
      cards: plan.cards,
      scheduler: container.read(schedulerProvider),
      reviewRepository: container.read(reviewRepositoryProvider),
      clock: () => now,
      prebuilt: true,
    );
    engine.start();
    expect(await engine.rate(Rating.hard), isTrue);

    final ReviewLogRow log = await db.select(db.reviewLogs).getSingle();
    expect(log.cardId, 'unique');
    expect(log.mode, reviewModeFeed);
    expect(log.rating, 2);
  });

  test('пресет: сохранение, чтение, бюджет времени и удаление', () async {
    final sessionPresetRepository = container.read(
      sessionPresetRepositoryProvider,
    );
    const SessionConfig config = SessionConfig(
      deckIds: <String>['deck-1', 'deck-2'],
      tags: <String>{'даты'},
      mode: SessionMode.feed,
      limit: SessionLimit.minutes(10),
      shuffle: true,
      interleave: true,
      warmup: true,
    );

    final SessionPreset saved = await sessionPresetRepository.savePreset(
      name: 'Вечер',
      config: config,
      createdAt: now,
    );
    expect(saved.id, isNotEmpty);

    final List<SessionPreset> presets = await sessionPresetRepository.presets();
    expect(presets.single, saved);
    expect(presets.single.config, config);

    final SessionPlan plan = SessionBuilder.plan(
      cards: const <Card>[],
      config: presets.single.config,
      failureCounts: const <String, int>{},
      now: now,
    );
    expect(plan.timeBudget, const Duration(minutes: 10));

    await sessionPresetRepository.deletePreset(saved.id);
    expect(await sessionPresetRepository.presets(), isEmpty);
  });
}
