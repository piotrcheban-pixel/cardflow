import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/review/drift_daily_usage_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_draft.dart';
import 'package:cardflow/domain/review/daily_limits.dart';
import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/domain/scheduling/scheduling_card.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/ui/review/review_session_engine.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// L45 закрыт: дневные лимиты A6.6 считаются за локальный календарный день по
/// истории `review_logs` (ADR-019 §8).
///
/// Сквозной сценарий на **реальной drift-БД** и production-графе провайдеров
/// (ретроспективы итераций 1–2: фикс слоя обязан работать на боевой проводке,
/// а не только в unit-тестах). Проверяется именно разрыв L45 — вторая сессия
/// того же дня не получает свежий лимит.
void main() {
  late AppDatabase db;
  late Directory mediaDirectory;
  late ProviderContainer container;

  /// Полдень локального дня — чтобы «сегодня» не зависело от часа прогона.
  final DateTime now = DateTime(2026, 11, 14, 12);
  final DateTime created = now.subtract(const Duration(days: 30));

  setUp(() {
    db = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_daily_');
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
            createdAt: created.millisecondsSinceEpoch,
            updatedAt: created.millisecondsSinceEpoch,
          ),
        );
  }

  /// Просроченная карточка в состоянии `review` (`fsrs_json` + `due` согласованы).
  Future<void> seedDueCard({required String id, required int hoursAgo}) async {
    final DateTime due = now.subtract(Duration(hours: hoursAgo)).toUtc();
    final SchedulingCard scheduling = SchedulingCard(
      cardId: id,
      state: CardState.review,
      stability: 60,
      difficulty: 5,
      due: due,
      lastReview: due.subtract(const Duration(days: 10)),
    );
    await db
        .into(db.cards)
        .insert(
          CardsCompanion.insert(
            id: id,
            deckId: 'deck-1',
            front: 'Вопрос $id',
            back: 'Ответ $id',
            cardType: 'basic',
            state: CardState.review.wireName,
            createdAt: created.millisecondsSinceEpoch,
            updatedAt: created.millisecondsSinceEpoch,
            fsrsJson: Value<String>(jsonEncode(scheduling.toJson())),
            due: Value<int>(due.millisecondsSinceEpoch),
          ),
        );
  }

  Future<void> seedNewCards(int count) async {
    for (int index = 0; index < count; index++) {
      await container
          .read(cardRepositoryProvider)
          .createCards(
            deckId: 'deck-1',
            draft: CardDraft(front: 'Новая $index', back: 'Ответ $index'),
            now: created.add(Duration(minutes: index)),
          );
    }
  }

  /// Остаток дневных лимитов так, как его считает экран сессии (ADR-019 §8).
  Future<RemainingReviewLimits> limitsAt(
    DateTime at, {
    required AppSettings settings,
  }) async {
    final DailyReviewUsage usage = await container
        .read(dailyUsageRepositoryProvider)
        .usageOnDay(at);
    return RemainingReviewLimits.of(
      newLimit: settings.dailyNewLimit,
      reviewLimit: settings.dailyReviewLimit,
      usage: usage,
    );
  }

  Future<ReviewSessionEngine> startSession(
    DateTime at, {
    required AppSettings settings,
  }) async {
    final List<Card> cards = await container
        .read(cardRepositoryProvider)
        .cardsByDeck('deck-1');
    final RemainingReviewLimits limits = await limitsAt(at, settings: settings);
    final ReviewSessionEngine engine = ReviewSessionEngine(
      cards: cards,
      scheduler: container.read(schedulerProvider),
      reviewRepository: container.read(reviewRepositoryProvider),
      clock: () => at,
      newLimit: limits.newCards,
      reviewLimit: limits.reviews,
    );
    engine.start();
    return engine;
  }

  test('граф провайдеров: расход дня читается из drift', () {
    expect(
      container.read(dailyUsageRepositoryProvider),
      isA<DriftDailyUsageRepository>(),
    );
  });

  test(
    'L45: вторая сессия того же дня не получает новых сверх лимита',
    () async {
      await seedDeck();
      await seedNewCards(5);
      final AppSettings settings = AppSettings.defaults.copyWith(
        dailyNewLimit: 2,
        dailyReviewLimit: 0,
      );

      final RemainingReviewLimits first = await limitsAt(
        now,
        settings: settings,
      );
      expect(first.newCards, 2, reason: 'в начале дня доступно 2 новых');

      final ReviewSessionEngine session1 = await startSession(
        now,
        settings: settings,
      );
      expect(
        session1.state.total,
        2,
        reason: 'первая сессия дня берёт 2 новых',
      );
      expect(await session1.rate(Rating.good), isTrue);
      expect(await session1.rate(Rating.good), isTrue);
      expect(await db.select(db.reviewLogs).get(), hasLength(2));

      // Повторное открытие сессии в тот же день — остаток дня уже израсходован.
      final RemainingReviewLimits second = await limitsAt(
        now,
        settings: settings,
      );
      expect(
        second.newCards,
        0,
        reason: 'L45: расход дня (2 из 2) должен уменьшать остаток',
      );

      final ReviewSessionEngine session2 = await startSession(
        now,
        settings: settings,
      );
      expect(
        session2.state.total,
        0,
        reason: 'L45: до этого две сессии подряд давали по 20 новых каждая',
      );
    },
  );

  test('новый календарный день — полный лимит снова', () async {
    await seedDeck();
    await seedNewCards(5);
    final AppSettings settings = AppSettings.defaults.copyWith(
      dailyNewLimit: 2,
      dailyReviewLimit: 0,
    );

    final ReviewSessionEngine session1 = await startSession(
      now,
      settings: settings,
    );
    expect(session1.state.total, 2);
    await session1.rate(Rating.good);
    await session1.rate(Rating.good);

    final DateTime tomorrow = now.add(const Duration(days: 1));
    final RemainingReviewLimits limits = await limitsAt(
      tomorrow,
      settings: settings,
    );
    expect(
      limits.newCards,
      2,
      reason: 'вчерашние оценки не расходуют новый день',
    );

    final ReviewSessionEngine session2 = await startSession(
      tomorrow,
      settings: settings,
    );
    final List<Card> newInQueue = session2.state.items
        .map((ReviewSessionItem item) => item.card)
        .where((Card card) => card.state == CardState.newCard)
        .toList(growable: false);
    expect(
      newInQueue,
      hasLength(2),
      reason: 'новых в очереди — ровно лимит дня',
    );
  });

  test('дневной лимит повторных накапливается между сессиями', () async {
    await seedDeck();
    await seedDueCard(id: 'due-1', hoursAgo: 3);
    await seedDueCard(id: 'due-2', hoursAgo: 2);
    await seedDueCard(id: 'due-3', hoursAgo: 1);
    final AppSettings settings = AppSettings.defaults.copyWith(
      dailyNewLimit: 0,
      dailyReviewLimit: 1,
    );

    final ReviewSessionEngine session1 = await startSession(
      now,
      settings: settings,
    );
    expect(session1.state.total, 1, reason: 'лимит повторных — 1 за сессию');
    expect(await session1.rate(Rating.good), isTrue);

    final RemainingReviewLimits limits = await limitsAt(
      now,
      settings: settings,
    );
    expect(limits.reviews, 0, reason: 'повторные дня израсходованы');

    final ReviewSessionEngine session2 = await startSession(
      now,
      settings: settings,
    );
    expect(
      session2.state.total,
      0,
      reason: 'остальные due ждут следующих суток',
    );
  });

  test('undo возвращает расход дня (журнал — источник истины)', () async {
    await seedDeck();
    await seedNewCards(3);
    final AppSettings settings = AppSettings.defaults.copyWith(
      dailyNewLimit: 1,
      dailyReviewLimit: 0,
    );

    final ReviewSessionEngine session = await startSession(
      now,
      settings: settings,
    );
    expect(session.state.total, 1);
    expect(await session.rate(Rating.good), isTrue);
    expect(
      (await limitsAt(now, settings: settings)).newCards,
      0,
      reason: 'новая карточка израсходовала лимит дня',
    );

    expect(await session.undo(), isTrue);
    expect(
      (await limitsAt(now, settings: settings)).newCards,
      1,
      reason: 'откат удалил лог — расход дня вернулся',
    );
  });

  test('0 в настройках — без лимита: очередь не зависит от журнала', () async {
    await seedDeck();
    await seedNewCards(4);
    final AppSettings settings = AppSettings.defaults.copyWith(
      dailyNewLimit: 0,
      dailyReviewLimit: 0,
    );

    final RemainingReviewLimits limits = await limitsAt(
      now,
      settings: settings,
    );
    expect(limits.newCards, isNull, reason: '0 — лимита нет, а не «исчерпан»');
    expect(limits.reviews, isNull);

    final ReviewSessionEngine session = await startSession(
      now,
      settings: settings,
    );
    expect(session.state.total, 4);
    await session.rate(Rating.good);

    final ReviewSessionEngine again = await startSession(
      now,
      settings: settings,
    );
    expect(
      again.state.total,
      3,
      reason: 'без лимита очередь не обрезается, но оценённая карточка ушла',
    );
  });
}
