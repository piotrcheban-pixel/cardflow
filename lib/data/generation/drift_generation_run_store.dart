/// Хранилище прогона генерации v3 на drift (TASK «Срез 8», ARCH §3.5, ADR-051).
///
/// Задача слоя — чтобы сбой не терял принятое: карточка пишется в
/// `card_drafts` **в момент принятия** (`CardSink`), а не после прогона;
/// партии и этап обновляются по ходу; после перезапуска приложения прогон
/// восстанавливается из БД (`loadRun`) и продолжается с невыполненных партий.
///
/// `generation_jobs` остаётся совместимым представлением для UI: строка
/// создаётся вместе с прогоном (если её ещё нет) и обновляется вместе с этапом
/// (`status`), поэтому старый экран «Задания генерации» продолжает работать без
/// нового кода.
library;

import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/generation/dedup_mark.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_json.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_run_snapshot.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/ports.dart';

/// Хранилище прогона генерации v3 поверх drift-БД.
class DriftGenerationRunStore {
  /// Создаёт хранилище поверх БД приложения.
  DriftGenerationRunStore(this.database);

  /// БД приложения.
  final AppDatabase database;

  static const Uuid _uuid = Uuid();

  /// Регистрирует прогон: этап, партии плана, единицы карты и версии промптов.
  ///
  /// Запись идемпотентна по `runId`: повторный `openRun` того же прогона
  /// обновляет этап и версии промптов, но **не сбрасывает** уже сохранённые
  /// партии, черновики и единицы (иначе восстановление потеряло бы принятое).
  Future<void> openRun({
    required String runId,
    required GenerationStage stage,
    required DateTime now,
    List<GenerationBatchLedger> batches = const <GenerationBatchLedger>[],
    List<KnowledgeUnit> units = const <KnowledgeUnit>[],
    String? provider,
    String? model,
    Map<String, String> promptVersions = const <String, String>{},
  }) async {
    try {
      await database.transaction(() async {
        final int epochNow = toEpochMs(now.toUtc());
        await database
            .into(database.generationRuns)
            .insert(
              GenerationRunsCompanion.insert(
                id: runId,
                stage: stage.wireName,
                status: stage.jobStatus.wireName,
                createdAt: epochNow,
                updatedAt: epochNow,
                provider: Value<String?>(provider),
                model: Value<String?>(model),
                promptVersionsJson: Value<String?>(
                  promptVersions.isEmpty ? null : jsonEncode(promptVersions),
                ),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        // Совместимое представление для UI: строка `generation_jobs` без
        // перезаписи полей, которые ведёт сам конвейер (tokens_used и т.п.).
        await database
            .into(database.generationJobs)
            .insert(
              GenerationJobsCompanion.insert(
                id: runId,
                status: stage.jobStatus.wireName,
                createdAt: epochNow,
                provider: Value<String?>(provider),
                model: Value<String?>(model),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        for (final GenerationBatchLedger ledger in batches) {
          await database
              .into(database.generationBatches)
              .insert(
                _batchCompanion(
                  runId: runId,
                  record: GenerationBatchRecord(ledger: ledger),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
        for (var index = 0; index < units.length; index++) {
          await _insertUnit(runId, units[index], index);
        }
      });
    } on Object catch (error) {
      throw _storageError('open generation run', error);
    }
  }

  /// Сохраняет этап стейт-машины (и статус задания для совместимости).
  Future<void> saveStage(
    String runId,
    GenerationStage stage, {
    required DateTime now,
  }) async {
    try {
      await database.transaction(() async {
        final int epochNow = toEpochMs(now.toUtc());
        await (database.update(
          database.generationRuns,
        )..where((table) => table.id.equals(runId))).write(
          GenerationRunsCompanion(
            stage: Value<String>(stage.wireName),
            status: Value<String>(stage.jobStatus.wireName),
            updatedAt: Value<int>(epochNow),
          ),
        );
        await (database.update(
          database.generationJobs,
        )..where((table) => table.id.equals(runId))).write(
          GenerationJobsCompanion(
            status: Value<String>(stage.jobStatus.wireName),
          ),
        );
      });
    } on Object catch (error) {
      throw _storageError('save generation stage', error);
    }
  }

  /// Сохраняет партию прогона: статус и счётчики журнала.
  Future<void> saveBatch(
    String runId,
    GenerationBatchRecord record, {
    required DateTime now,
  }) async {
    try {
      await database.transaction(() async {
        await database
            .into(database.generationBatches)
            .insertOnConflictUpdate(
              _batchCompanion(runId: runId, record: record),
            );
        await (database.update(
          database.generationRuns,
        )..where((table) => table.id.equals(runId))).write(
          GenerationRunsCompanion(
            updatedAt: Value<int>(toEpochMs(now.toUtc())),
          ),
        );
      });
    } on Object catch (error) {
      throw _storageError('save generation batch', error);
    }
  }

  /// Пишет принятую карточку в журнал прогона (черновик).
  ///
  /// Идемпотентно по (`runId`, `contentHash`): повторное принятие той же
  /// карточки не создаёт вторую строку — уникальный индекс
  /// `idx_card_drafts_run_hash` отбрасывает дубль.
  Future<void> saveDraft(
    String runId,
    GeneratedCard card, {
    required int batchIndex,
    required DateTime now,
  }) async {
    try {
      final String contentHash = draftContentHashOf(card);
      await database
          .into(database.cardDrafts)
          .insert(
            CardDraftsCompanion.insert(
              id: _uuid.v4(),
              runId: runId,
              batchIndex: batchIndex,
              contentHash: contentHash,
              unitId: Value<String?>(card.unitId),
              angle: Value<String?>(card.angle),
              cardJson: jsonEncode(encodeGeneratedCardJson(card)),
              createdAt: toEpochMs(now.toUtc()),
            ),
            mode: InsertMode.insertOrIgnore,
          );
    } on Object catch (error) {
      throw _storageError('save card draft', error);
    }
  }

  /// Сохраняет колоду результата (после импорта).
  Future<void> saveDeckId(
    String runId,
    String deckId, {
    required DateTime now,
  }) async {
    try {
      await database.transaction(() async {
        await (database.update(
          database.generationRuns,
        )..where((table) => table.id.equals(runId))).write(
          GenerationRunsCompanion(
            deckId: Value<String>(deckId),
            updatedAt: Value<int>(toEpochMs(now.toUtc())),
          ),
        );
        await (database.update(
          database.generationJobs,
        )..where((table) => table.id.equals(runId))).write(
          GenerationJobsCompanion(resultDeckId: Value<String>(deckId)),
        );
      });
    } on Object catch (error) {
      throw _storageError('save deck id', error);
    }
  }

  /// Пишет пометки этапа Dedup в строки черновиков (TASK «Срез 13», L219).
  ///
  /// Строка ищется по (`run_id`, `content_hash`) — тому же ключу, что у
  /// идемпотентного импорта. Пометки не удаляют черновик и не меняют
  /// `card_json`: после перезапуска прогона пары восстанавливаются из
  /// [GenerationRunSnapshot.dedup].
  Future<void> saveDedupMarks(
    String runId, {
    required List<DedupMark> marks,
    required DateTime now,
  }) async {
    if (marks.isEmpty) return;
    try {
      await database.transaction(() async {
        for (final DedupMark mark in marks) {
          await (database.update(database.cardDrafts)..where(
                ($CardDraftsTable table) =>
                    table.runId.equals(runId) &
                    table.contentHash.equals(mark.contentHash),
              ))
              .write(
                CardDraftsCompanion(
                  isDuplicateOf: Value<String>(mark.duplicateOf),
                  dedupLevel: Value<String>(mark.level.wireName),
                ),
              );
        }
        await (database.update(
          database.generationRuns,
        )..where((table) => table.id.equals(runId))).write(
          GenerationRunsCompanion(
            updatedAt: Value<int>(toEpochMs(now.toUtc())),
          ),
        );
      });
    } on Object catch (error) {
      throw _storageError('save dedup marks', error);
    }
  }

  /// Снимок прогона: этап, партии, черновики и число единиц карты.
  ///
  /// `null` — такого прогона нет; повреждённая запись (неизвестный этап/статус,
  /// битый JSON черновика) — [FormatException]: восстановление не должно
  /// «домысливать» сохранённое состояние.
  Future<GenerationRunSnapshot?> loadRun(String runId) async {
    try {
      final GenerationRunRow? run = await (database.select(
        database.generationRuns,
      )..where((table) => table.id.equals(runId))).getSingleOrNull();
      if (run == null) return null;
      final List<GenerationBatchRow> batchRows =
          await (database.select(database.generationBatches)
                ..where((table) => table.runId.equals(runId))
                ..orderBy(<OrderingTerm Function($GenerationBatchesTable)>[
                  ($GenerationBatchesTable table) =>
                      OrderingTerm.asc(table.batchIndex),
                ]))
              .get();
      final List<CardDraftRow> draftRows =
          await (database.select(database.cardDrafts)
                ..where((table) => table.runId.equals(runId))
                ..orderBy(<OrderingTerm Function($CardDraftsTable)>[
                  ($CardDraftsTable table) => OrderingTerm.asc(table.createdAt),
                  ($CardDraftsTable table) => OrderingTerm.asc(table.id),
                ]))
              .get();
      final List<GenerationUnitRow> unitRows = await (database.select(
        database.generationUnits,
      )..where((table) => table.runId.equals(runId))).get();
      return GenerationRunSnapshot(
        runId: run.id,
        stage: GenerationStage.fromWire(run.stage),
        batches: <GenerationBatchRecord>[
          for (final GenerationBatchRow row in batchRows) _batchRecordOf(row),
        ],
        drafts: <RunCardDraft>[
          for (final CardDraftRow row in draftRows) _draftOf(row),
        ],
        unitCount: unitRows.length,
        deckId: run.deckId,
        createdAt: fromEpochMs(run.createdAt),
        updatedAt: fromEpochMs(run.updatedAt),
      );
    } on FormatException {
      rethrow;
    } on Object catch (error) {
      throw _storageError('load generation run', error);
    }
  }

  /// Единицы карты знаний прогона в порядке плана.
  Future<List<KnowledgeUnit>> unitsOfRun(String runId) async {
    try {
      final List<GenerationUnitRow> rows =
          await (database.select(database.generationUnits)
                ..where((table) => table.runId.equals(runId))
                ..orderBy(<OrderingTerm Function($GenerationUnitsTable)>[
                  ($GenerationUnitsTable table) =>
                      OrderingTerm.asc(table.orderIndex),
                ]))
              .get();
      return <KnowledgeUnit>[
        for (final GenerationUnitRow row in rows) _unitOf(row),
      ];
    } on Object catch (error) {
      throw _storageError('load generation units', error);
    }
  }

  /// Идентификатор последнего незавершённого прогона; `null` — продолжать нечего.
  ///
  /// «Незавершённый» — этап не `ready`/`partial`: упавший, отменённый или
  /// оборванный перезапуском прогон продолжается, а не начинается заново.
  Future<String?> latestResumableRunId() async {
    try {
      final List<GenerationRunRow> rows =
          await (database.select(database.generationRuns)
                ..where(
                  (table) => table.stage.isNotIn(<String>[
                    GenerationStage.ready.wireName,
                    GenerationStage.partial.wireName,
                  ]),
                )
                ..orderBy(<OrderingTerm Function($GenerationRunsTable)>[
                  ($GenerationRunsTable table) =>
                      OrderingTerm.desc(table.updatedAt),
                ])
                ..limit(1))
              .get();
      return rows.isEmpty ? null : rows.single.id;
    } on Object catch (error) {
      throw _storageError('find resumable run', error);
    }
  }

  Future<void> _insertUnit(String runId, KnowledgeUnit unit, int orderIndex) {
    return database
        .into(database.generationUnits)
        .insert(
          GenerationUnitsCompanion.insert(
            runId: runId,
            unitId: unit.id,
            sectionId: unit.sectionId,
            topic: unit.topic,
            kind: unit.kind.wireName,
            statement: unit.statement,
            salience: unit.salience,
            splittable: unit.splittable ? 1 : 0,
            anchorsJson: jsonEncode(<Object?>[
              for (final KnowledgeAnchor anchor in unit.anchors)
                <String, Object?>{
                  'block_id': anchor.blockId,
                  'quote': anchor.quote,
                },
            ]),
            orderIndex: orderIndex,
          ),
          mode: InsertMode.insertOrIgnore,
        );
  }

  GenerationBatchesCompanion _batchCompanion({
    required String runId,
    required GenerationBatchRecord record,
  }) {
    final GenerationBatchLedger ledger = record.ledger;
    return GenerationBatchesCompanion.insert(
      runId: runId,
      batchIndex: ledger.batchIndex,
      status: record.status.wireName,
      requested: ledger.requested,
      generated: Value<int>(ledger.generated),
      invalid: Value<int>(ledger.invalid),
      duplicates: Value<int>(ledger.duplicates),
      attempts: Value<int>(ledger.attempts),
      cause: Value<String?>(ledger.cause?.wireName),
    );
  }

  GenerationBatchRecord _batchRecordOf(GenerationBatchRow row) {
    return GenerationBatchRecord(
      status: GenerationBatchStatus.fromWire(row.status),
      ledger: GenerationBatchLedger(
        batchIndex: row.batchIndex,
        requested: row.requested,
        generated: row.generated,
        invalid: row.invalid,
        duplicates: row.duplicates,
        attempts: row.attempts,
        cause: row.cause == null ? null : ShortfallKind.fromWire(row.cause!),
      ),
    );
  }

  RunCardDraft _draftOf(CardDraftRow row) {
    final Object? decoded = jsonDecode(row.cardJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Черновик карточки — не JSON-объект');
    }
    return RunCardDraft(
      contentHash: row.contentHash,
      batchIndex: row.batchIndex,
      card: decodeGeneratedCardJson(decoded),
      importedCardId: row.importedCardId,
      duplicateOf: row.isDuplicateOf,
      dedupLevel: row.dedupLevel == null
          ? null
          : _dedupLevelOf(row.dedupLevel!, row.contentHash),
    );
  }

  /// Уровень каскада из строки; неизвестный код — [FormatException], чтобы
  /// «дубль с непонятным уровнем» не превращался молча в чистую карточку.
  static DedupLevel _dedupLevelOf(String wire, String contentHash) {
    final DedupLevel? level = DedupLevel.fromWire(wire);
    if (level == null) {
      throw FormatException(
        'Неизвестный уровень дедупа «$wire» у черновика $contentHash',
      );
    }
    return level;
  }

  KnowledgeUnit _unitOf(GenerationUnitRow row) {
    final KnowledgeUnitKind? kind = KnowledgeUnitKind.fromWire(row.kind);
    if (kind == null) {
      throw FormatException('Неизвестный вид единицы: ${row.kind}');
    }
    final Object? decoded = jsonDecode(row.anchorsJson);
    final List<KnowledgeAnchor> anchors = <KnowledgeAnchor>[];
    if (decoded is List<Object?>) {
      for (final Object? raw in decoded) {
        if (raw is Map<String, Object?>) {
          final Object? blockId = raw['block_id'];
          final Object? quote = raw['quote'];
          if (blockId is String &&
              blockId.isNotEmpty &&
              quote is String &&
              quote.isNotEmpty) {
            anchors.add(KnowledgeAnchor(blockId: blockId, quote: quote));
          }
        }
      }
    }
    if (anchors.isEmpty) {
      throw FormatException('У единицы ${row.unitId} нет якорей');
    }
    return KnowledgeUnit(
      id: row.unitId,
      sectionId: row.sectionId,
      topic: row.topic,
      kind: kind,
      statement: row.statement,
      anchors: anchors,
      salience: row.salience,
      splittable: row.splittable != 0,
    );
  }

  /// Сбой локального хранилища — доменный код, а не сырое исключение drift.
  GenerationException _storageError(String action, Object error) {
    return GenerationException(
      GenerationErrorCode.storageUnavailable,
      details: '$action: ${error.runtimeType}: $error',
      failureReason: GenerationFailureReason.storage,
    );
  }
}

/// `CardSink` прогона: принятая карточка сразу становится черновиком в БД.
///
/// Сбой на любом батче не теряет предыдущие: каждая карточка записана своей
/// строкой в момент принятия (`ARCH §3.5`), а не в память до конца прогона.
class GenerationRunCardSink implements CardSink {
  /// Создаёт приёмник принятых карточек прогона [runId].
  GenerationRunCardSink({
    required this.store,
    required this.runId,
    required this.clock,
  });

  /// Хранилище прогона.
  final DriftGenerationRunStore store;

  /// Прогон, в журнал которого пишутся карточки.
  final String runId;

  /// Часы прогона (инжектируются для детерминированных тестов).
  final DateTime Function() clock;

  @override
  Future<void> save(GeneratedCard card, {required int batchIndex}) {
    return store.saveDraft(runId, card, batchIndex: batchIndex, now: clock());
  }
}
