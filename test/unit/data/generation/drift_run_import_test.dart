// Идемпотентный импорт прогона в колоду (TASK «Срез 8», п. 3): импорт одной
// транзакцией, ключ идемпотентности — (`run_id`, `content_hash`); повторный
// импорт того же прогона не создаёт дублей, а второй рубеж — дедупликация по
// хешу колоды.
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/dedup_mark.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_run_snapshot.dart';

void main() {
  late AppDatabase db;
  late DriftGenerationRunStore runs;
  late DriftGenerationCardStore cards;

  final DateTime fixedNow = DateTime.utc(2026, 11, 28, 10);

  setUp(() {
    db = AppDatabase.inMemory();
    runs = DriftGenerationRunStore(db);
    cards = DriftGenerationCardStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  GeneratedCard card(String front) => GeneratedCard(
    front: front,
    back: 'Ответ: $front',
    cardType: CardType.basic,
    unitId: 'ku:run#0',
  );

  Future<void> seedRun({String runId = 'run-1', int count = 3}) async {
    await runs.openRun(
      runId: runId,
      stage: GenerationStage.partial,
      now: fixedNow,
      batches: GenerationLedger.fromBudgets(<int>[count]).batches,
    );
    final GenerationRunCardSink sink = GenerationRunCardSink(
      store: runs,
      runId: runId,
      clock: () => fixedNow,
    );
    for (var index = 0; index < count; index++) {
      await sink.save(card('Вопрос $index'), batchIndex: 0);
    }
  }

  Future<int> deckCardCount(String deckId) async {
    final List<CardRow> rows = await (db.select(
      db.cards,
    )..where((table) => table.deckId.equals(deckId))).get();
    return rows.length;
  }

  group('импорт прогона', () {
    test('первый импорт создаёт колоду и карточки одной транзакцией', () async {
      await seedRun();

      final GenerationImportResult result = await cards.importRunCards(
        runId: 'run-1',
        deckId: null,
        deckName: 'Сгенерированное',
        now: fixedNow,
      );

      expect(result.importedCards, 3);
      expect(result.skippedDuplicates, 0);
      expect(result.deckId, isNotEmpty);
      expect(await deckCardCount(result.deckId), 3);

      final GenerationRunRow run = await (db.select(
        db.generationRuns,
      )..where((table) => table.id.equals('run-1'))).getSingle();
      expect(run.deckId, result.deckId);
      final GenerationJobRow job = await (db.select(
        db.generationJobs,
      )..where((table) => table.id.equals('run-1'))).getSingle();
      expect(job.resultDeckId, result.deckId);

      // Черновики помечены импортированными: повтор их не тронет.
      final List<CardDraftRow> drafts = await db.select(db.cardDrafts).get();
      expect(
        drafts.every((CardDraftRow row) => row.importedCardId != null),
        isTrue,
      );
      expect(
        drafts.every(
          (CardDraftRow row) =>
              row.importedAt == fixedNow.millisecondsSinceEpoch,
        ),
        isTrue,
      );
    });

    test(
      'двойной импорт: карточек в колоде столько же, сколько в первый раз',
      () async {
        await seedRun();

        final GenerationImportResult first = await cards.importRunCards(
          runId: 'run-1',
          deckId: null,
          deckName: 'Сгенерированное',
          now: fixedNow,
        );
        final int afterFirst = await deckCardCount(first.deckId);

        final GenerationImportResult second = await cards.importRunCards(
          runId: 'run-1',
          deckId: first.deckId,
          deckName: 'Сгенерированное',
          now: fixedNow.add(const Duration(minutes: 5)),
        );

        expect(second.deckId, first.deckId);
        expect(second.importedCards, 0);
        expect(await deckCardCount(first.deckId), afterFirst);
        expect(await deckCardCount(first.deckId), 3);
      },
    );

    test('второй прогон с тем же содержимым не дублирует колоду', () async {
      await seedRun(runId: 'run-1');
      final GenerationImportResult first = await cards.importRunCards(
        runId: 'run-1',
        deckId: null,
        deckName: 'Сгенерированное',
        now: fixedNow,
      );
      await seedRun(runId: 'run-2');

      // Ключ идемпотентности — пара (run_id, content_hash): черновик второго
      // прогона свой, но в колоду он не попадает (второй рубеж — хеш колоды).
      final GenerationImportResult second = await cards.importRunCards(
        runId: 'run-2',
        deckId: first.deckId,
        deckName: 'Сгенерированное',
        now: fixedNow,
      );

      expect(second.importedCards, 0);
      expect(second.skippedDuplicates, 3);
      expect(await deckCardCount(first.deckId), 3);
    });

    test('сбой импорта не оставляет полуимпортированных карточек', () async {
      await seedRun();

      await expectLater(
        cards.importRunCards(
          runId: 'run-1',
          deckId: 'нет-такой-колоды',
          deckName: 'Сгенерированное',
          now: fixedNow,
        ),
        throwsA(isA<StateError>()),
      );

      expect(await db.select(db.cards).get(), isEmpty);
      final List<CardDraftRow> drafts = await db.select(db.cardDrafts).get();
      expect(
        drafts.every((CardDraftRow row) => row.importedCardId == null),
        isTrue,
        reason: 'отметка импорта не должна пережить откат транзакции',
      );
    });

    test('импорт несуществующего прогона — StateError', () async {
      await expectLater(
        cards.importRunCards(
          runId: 'нет-прогона',
          deckId: null,
          deckName: 'Колода',
          now: fixedNow,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('повторный импорт не теряет пометки дедупа (срез 13)', () async {
      await seedRun(count: 2);
      final List<CardDraftRow> drafts = await db.select(db.cardDrafts).get();
      final String hash = drafts.first.contentHash;
      await runs.saveDedupMarks(
        'run-1',
        marks: <DedupMark>[
          DedupMark(
            contentHash: hash,
            duplicateOf: DedupMark.deckKey('deck-1'),
            level: DedupLevel.normalized,
          ),
        ],
        now: fixedNow,
      );

      final GenerationImportResult imported = await cards.importRunCards(
        runId: 'run-1',
        deckId: null,
        deckName: 'Сгенерированное',
        now: fixedNow,
      );
      expect(
        imported.importedCards,
        2,
        reason: 'дубль помечен, но импортирован',
      );

      final GenerationRunSnapshot snapshot = (await runs.loadRun('run-1'))!;
      final RunCardDraft draft = snapshot.drafts.firstWhere(
        (RunCardDraft item) => item.contentHash == hash,
      );
      expect(draft.isImported, isTrue);
      expect(draft.duplicateOf, DedupMark.deckKey('deck-1'));
      expect(draft.dedupLevel, DedupLevel.normalized);
    });
  });
}
