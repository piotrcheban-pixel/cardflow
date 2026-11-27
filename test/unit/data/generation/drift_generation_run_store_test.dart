// Журнал прогона на drift (TASK «Срез 8», ARCH §3.5): принятое пишется в момент
// принятия, сбой на пятом батче не теряет первые четыре, после перезапуска
// приложения прогон восстанавливается и продолжается с первой невыполненной
// партии, а `generation_jobs` остаётся совместимым представлением для UI.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_run_snapshot.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/run_resume.dart';

void main() {
  late AppDatabase db;
  late DriftGenerationRunStore store;

  const String runId = 'run-1';
  final DateTime fixedNow = DateTime.utc(2026, 11, 28, 9);

  setUp(() {
    db = AppDatabase.inMemory();
    store = DriftGenerationRunStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  /// Шесть партий по две карточки: сбой на пятой оставляет четыре целыми.
  List<GenerationBatchLedger> budgets() =>
      GenerationLedger.fromBudgets(const <int>[2, 2, 2, 2, 2, 2]).batches;

  GeneratedCard card(String front) => GeneratedCard(
    front: front,
    back: 'Ответ: $front',
    cardType: CardType.basic,
    unitId: 'ku:run#0',
    quoteRef: 'цитата материала',
  );

  group('открытие прогона и совместимость с generation_jobs', () {
    test('openRun сохраняет этап, партии и единицы карты', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.planned,
        now: fixedNow,
        batches: budgets(),
        units: <KnowledgeUnit>[
          KnowledgeUnit(
            id: 'ku:run#0',
            sectionId: 's1',
            topic: 'тема',
            kind: KnowledgeUnitKind.fact,
            statement: 'Утверждение материала.',
            anchors: const <KnowledgeAnchor>[
              KnowledgeAnchor(blockId: 'b1', quote: 'Утверждение'),
            ],
          ),
        ],
        provider: 'deepseek',
        model: 'deepseek-chat',
        promptVersions: const <String, String>{'generating': 'gen-cards-v3'},
      );

      final GenerationRunSnapshot? snapshot = await store.loadRun(runId);
      expect(snapshot, isNotNull);
      expect(snapshot!.stage, GenerationStage.planned);
      expect(snapshot.batches, hasLength(6));
      expect(snapshot.batches.first.ledger.requested, 2);
      expect(snapshot.batches.first.status, GenerationBatchStatus.pending);
      expect(snapshot.unitCount, 1);
      expect(snapshot.ledger.requested, 12);
      expect(snapshot.ledger.accepted, 0);
      expect(await store.unitsOfRun(runId), hasLength(1));
      expect((await store.unitsOfRun(runId)).single.id, 'ku:run#0');

      // Совместимое представление для UI: строка generation_jobs создана, её
      // поля A5 не удалены и читаются старым кодом.
      final GenerationJobRow? job = await (db.select(
        db.generationJobs,
      )..where((table) => table.id.equals(runId))).getSingleOrNull();
      expect(job, isNotNull);
      expect(job!.status, 'running');
      expect(job.provider, 'deepseek');
      expect(job.createdAt, fixedNow.millisecondsSinceEpoch);
    });

    test('saveStage обновляет этап и статус совместимого задания', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.planned,
        now: fixedNow,
        batches: budgets(),
      );

      await store.saveStage(runId, GenerationStage.generating, now: fixedNow);
      expect((await store.loadRun(runId))!.stage, GenerationStage.generating);

      await store.saveStage(runId, GenerationStage.partial, now: fixedNow);
      expect((await store.loadRun(runId))!.stage, GenerationStage.partial);
      final GenerationJobRow job = await (db.select(
        db.generationJobs,
      )..where((table) => table.id.equals(runId))).getSingle();
      expect(job.status, 'partial');
    });

    test('повторный openRun не сбрасывает принятое', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.generating,
        now: fixedNow,
        batches: budgets(),
      );
      await store.saveDraft(
        runId,
        card('Вопрос 1'),
        batchIndex: 0,
        now: fixedNow,
      );

      await store.openRun(
        runId: runId,
        stage: GenerationStage.generating,
        now: fixedNow,
        batches: budgets(),
      );

      final GenerationRunSnapshot snapshot = (await store.loadRun(runId))!;
      expect(snapshot.drafts, hasLength(1));
      expect(snapshot.batches, hasLength(6));
    });
  });

  group('CardSink: сбой не теряет принятое', () {
    test('упал после четырёх батчей — первые четыре в БД', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.generating,
        now: fixedNow,
        batches: budgets(),
        units: <KnowledgeUnit>[
          KnowledgeUnit(
            id: 'ku:run#0',
            sectionId: 's1',
            topic: 'тема',
            kind: KnowledgeUnitKind.fact,
            statement: 'Утверждение материала.',
            anchors: const <KnowledgeAnchor>[
              KnowledgeAnchor(blockId: 'b1', quote: 'Утверждение'),
            ],
          ),
        ],
      );
      final GenerationRunCardSink sink = GenerationRunCardSink(
        store: store,
        runId: runId,
        clock: () => fixedNow,
      );

      // Четыре партии приняты и закрыты.
      for (var batch = 0; batch < 4; batch++) {
        await store.saveBatch(
          runId,
          GenerationBatchRecord(
            ledger: GenerationBatchLedger.budget(
              batchIndex: batch,
              requested: 2,
            ),
            status: GenerationBatchStatus.running,
          ),
          now: fixedNow,
        );
        for (var cardIndex = 0; cardIndex < 2; cardIndex++) {
          await sink.save(card('Вопрос $batch.$cardIndex'), batchIndex: batch);
        }
        await store.saveBatch(
          runId,
          GenerationBatchRecord(
            ledger: GenerationBatchLedger(
              batchIndex: batch,
              requested: 2,
              generated: 2,
              attempts: 1,
            ),
            status: GenerationBatchStatus.done,
          ),
          now: fixedNow,
        );
      }
      // Пятая партия началась и «упала»: запрос ушёл, одна карточка принята,
      // статус остаётся running — процесс завершился до отметки результата.
      await store.saveBatch(
        runId,
        GenerationBatchRecord(
          ledger: GenerationBatchLedger.budget(batchIndex: 4, requested: 2),
          status: GenerationBatchStatus.running,
        ),
        now: fixedNow,
      );
      await sink.save(card('Вопрос 4.0'), batchIndex: 4);

      // «Перезапуск приложения»: новый экземпляр хранилища поверх той же БД.
      final DriftGenerationRunStore restarted = DriftGenerationRunStore(db);
      final GenerationRunSnapshot snapshot = (await restarted.loadRun(runId))!;

      expect(snapshot.drafts, hasLength(9));
      expect(
        snapshot.drafts.map((RunCardDraft draft) => draft.batchIndex).toSet(),
        <int>{0, 1, 2, 3, 4},
      );
      expect(
        snapshot.batches
            .take(4)
            .every(
              (GenerationBatchRecord record) =>
                  record.status == GenerationBatchStatus.done,
            ),
        isTrue,
      );
      expect(snapshot.batches[4].status, GenerationBatchStatus.running);
      expect(snapshot.ledger.accepted, 8);
      expect(snapshot.ledger.remaining, 4);
      expect(snapshot.isResumable, isTrue);
    });

    test(
      'повторное принятие той же карточки не создаёт второй черновик',
      () async {
        await store.openRun(
          runId: runId,
          stage: GenerationStage.generating,
          now: fixedNow,
          batches: budgets(),
        );
        final GenerationRunCardSink sink = GenerationRunCardSink(
          store: store,
          runId: runId,
          clock: () => fixedNow,
        );

        await sink.save(card('Одна и та же'), batchIndex: 0);
        await sink.save(card('Одна и та же'), batchIndex: 1);

        final GenerationRunSnapshot snapshot = (await store.loadRun(runId))!;
        expect(snapshot.drafts, hasLength(1));
        expect(
          snapshot.drafts.single.contentHash,
          draftContentHashOf(card('Одна и та же')),
        );
      },
    );
  });

  group('восстановление после перезапуска', () {
    Future<void> seedFourDoneBatches() async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.generating,
        now: fixedNow,
        batches: budgets(),
        units: <KnowledgeUnit>[
          KnowledgeUnit(
            id: 'ku:run#0',
            sectionId: 's1',
            topic: 'тема',
            kind: KnowledgeUnitKind.fact,
            statement: 'Утверждение материала.',
            anchors: const <KnowledgeAnchor>[
              KnowledgeAnchor(blockId: 'b1', quote: 'Утверждение'),
            ],
          ),
        ],
      );
      final GenerationRunCardSink sink = GenerationRunCardSink(
        store: store,
        runId: runId,
        clock: () => fixedNow,
      );
      for (var batch = 0; batch < 4; batch++) {
        await sink.save(card('Вопрос $batch.0'), batchIndex: batch);
        await sink.save(card('Вопрос $batch.1'), batchIndex: batch);
        await store.saveBatch(
          runId,
          GenerationBatchRecord(
            ledger: GenerationBatchLedger(
              batchIndex: batch,
              requested: 2,
              generated: 2,
              attempts: 1,
            ),
            status: GenerationBatchStatus.done,
          ),
          now: fixedNow,
        );
      }
      // Прогон «упал» на пятой партии.
      await store.saveStage(runId, GenerationStage.failed, now: fixedNow);
    }

    test(
      'продолжение — с пятой партии, выполненные не перезапрашиваются',
      () async {
        await seedFourDoneBatches();

        final GenerationRunSnapshot snapshot = (await DriftGenerationRunStore(
          db,
        ).loadRun(runId))!;
        expect(snapshot.resumeBatchIndex, 4);
        expect(snapshot.pendingBatchIndexes, <int>[4, 5]);

        final GenerationResumePlan plan = planGenerationResume(snapshot);
        expect(plan.isResumable, isTrue);
        expect(plan.stage, GenerationStage.generating);
        expect(plan.firstBatchIndex, 4);
        expect(plan.batchIndexes, <int>[4, 5]);
        expect(plan.accepted, hasLength(8));
        expect(plan.ledger.accepted, 8);
        expect(plan.ledger.requested, 12);
        // Восстановление не просит заново то, что уже выполнено.
        expect(plan.batchIndexes.contains(0), isFalse);
        expect(plan.batchIndexes.contains(3), isFalse);
      },
    );

    test('журнал партии (счётчики и причина) переживает перезапуск', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.generating,
        now: fixedNow,
        batches: budgets(),
      );
      await store.saveBatch(
        runId,
        const GenerationBatchRecord(
          ledger: GenerationBatchLedger(
            batchIndex: 0,
            requested: 2,
            generated: 3,
            invalid: 1,
            attempts: 2,
            cause: ShortfallKind.validationRejects,
          ),
          status: GenerationBatchStatus.failed,
        ),
        now: fixedNow,
      );

      final GenerationRunSnapshot snapshot = (await DriftGenerationRunStore(db)
          .loadRun(runId))!;
      final GenerationBatchRecord restored = snapshot.batches.first;
      expect(restored.ledger.generated, 3);
      expect(restored.ledger.invalid, 1);
      expect(restored.ledger.attempts, 2);
      expect(restored.ledger.accepted, 2);
      expect(restored.ledger.cause, ShortfallKind.validationRejects);
      expect(restored.status, GenerationBatchStatus.failed);
      expect(restored.needsExecution, isTrue);
    });

    test('завершённый прогон не восстанавливается', () async {
      await seedFourDoneBatches();
      await store.saveStage(runId, GenerationStage.partial, now: fixedNow);

      final GenerationRunSnapshot snapshot = (await store.loadRun(runId))!;
      expect(snapshot.isResumable, isFalse);
      final GenerationResumePlan plan = planGenerationResume(snapshot);
      expect(plan.isResumable, isFalse);
      expect(plan.isEmpty, isTrue);
      expect(await store.latestResumableRunId(), isNull);
    });

    test('latestResumableRunId находит незавершённый прогон', () async {
      await store.openRun(
        runId: 'run-done',
        stage: GenerationStage.ready,
        now: fixedNow,
        batches: budgets(),
      );
      await store.openRun(
        runId: 'run-open',
        stage: GenerationStage.generating,
        now: fixedNow.add(const Duration(minutes: 1)),
        batches: budgets(),
      );

      expect(await store.latestResumableRunId(), 'run-open');
    });

    test('без единиц карты продолжение начинается с Understanding', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.failed,
        now: fixedNow,
        batches: budgets(),
      );

      final GenerationResumePlan plan = planGenerationResume(
        (await store.loadRun(runId))!,
      );
      expect(plan.stage, GenerationStage.understanding);
      expect(plan.needsUnderstanding, isTrue);
      expect(plan.batchIndexes, <int>[0, 1, 2, 3, 4, 5]);
    });

    test(
      'повреждённый этап в БД — FormatException, а не «угадывание»',
      () async {
        await store.openRun(
          runId: runId,
          stage: GenerationStage.generating,
          now: fixedNow,
          batches: budgets(),
        );
        await db.customStatement(
          "UPDATE generation_runs SET stage = 'nonsense' WHERE id = 'run-1'",
        );

        await expectLater(
          store.loadRun(runId),
          throwsA(isA<FormatException>()),
        );
      },
    );

    test('saveDeckId пишет колоду результата в оба представления', () async {
      await store.openRun(
        runId: runId,
        stage: GenerationStage.ready,
        now: fixedNow,
        batches: budgets(),
      );

      await store.saveDeckId(runId, 'deck-9', now: fixedNow);

      expect((await store.loadRun(runId))!.deckId, 'deck-9');
      final GenerationJobRow job = await (db.select(
        db.generationJobs,
      )..where((table) => table.id.equals(runId))).getSingle();
      expect(job.resultDeckId, 'deck-9');
      // Поля A5 не удалены: статус и счётчики остаются читаемыми.
      expect(job.status, 'done');
      expect(job.cardsCount, isNull);
    });
  });
}
