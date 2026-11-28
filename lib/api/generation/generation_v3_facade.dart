/// Сквозной путь генерации v3 (TASK «Срез 10», п. 6–7; срез 11 — гейт,
/// HTTP-карта и проводка; срез 13 — Dedup в цепи; ARCH §2, ADR-050).
///
/// Фасад **собирает этапы из портов** и не содержит собственной политики:
/// ни бюджетов, ни калибровок, ни recovery-логики. Он делает ровно пять
/// вещей:
/// 1) понимание материала — [UnderstandingStage] (или единственная единица
///    `kind=topic` для prompt-only);
/// 2) план заказа — `planAllocation` (этап Allocation);
/// 3) генерация — [CardsBatchEngine] (партии, повторы — внутри движка);
/// 4) проверка, добор и журнал — гейт [CardGate] (тот же, что у добора),
///    [ReplenishStage], [CardSink]/импорт;
/// 5) **Dedup** — существующий `SemanticMatcher` (каскад ADR-050 §3.4) по
///    принятым прогона и целевой колоде: дубль помечается парой и остаётся.
///
/// Итог — [GenerationReport]: «заказано/принято», причины недобора с числами,
/// покрытие единиц, расход по этапам (включая Understanding) и предохранители
/// операции. Легаси-конвейер (`generation_pipeline.dart`) не меняется: флаг
/// `generationPipelineV3` остаётся выключенным по умолчанию (протокол §9),
/// проводка — `GenerationV3Path` (срез 11, часть 3).
library;

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/api/generation/validation/card_validator.dart';
import 'package:cardflow/api/generation/validation/card_validator_gate.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/card_gate.dart';
import 'package:cardflow/domain/generation/dedup_mark.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_run_snapshot.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';

/// Этап Understanding: материал → карта знаний и статусы фрагментов.
///
/// Тип результата — [UnderstandingResult] (срез 11): фасаду нужен не только
/// `map`, но и фактический `usage` этапа и коды помеченных фрагментов, иначе
/// расход Understanding и причина «карты нет» не доезжают до отчёта (п. 5/10).
typedef UnderstandingStage = Future<UnderstandingResult> Function(
  Document document,
);

/// Импорт черновиков прогона в колоду (реализация — `importRunCards`, срез 8).
typedef RunImporter = Future<int> Function(String runId);

/// Итог сквозного прогона v3.
class GenerationV3Run {
  /// Создаёт итог.
  const GenerationV3Run({
    required this.runId,
    required this.map,
    required this.plan,
    required this.report,
    required this.acceptedCards,
    required this.blockedCards,
    required this.imported,
    this.dedup,
  });

  /// id прогона в журнале запуска.
  final String runId;

  /// Карта знаний, по которой строился план.
  final KnowledgeMap map;

  /// План Allocation (заказ, единицы, партии).
  final AllocationPlan plan;

  /// Отчёт: заказ/принято, причины с числами, покрытие, предохранители.
  final GenerationReport report;

  /// Карточки, допущенные к импорту (принятые и помеченные).
  final List<GeneratedCard> acceptedCards;

  /// Заблокированные жёсткими дефектами (в колоду не идут, но сохранены).
  final List<GeneratedCard> blockedCards;

  /// Сколько карточек записано в колоду (0 — импорт не подключён).
  final int imported;

  /// Отчёт этапа Dedup (срез 13): пары каскада и уровни. `null` — прогон без
  /// этапа (старые тесты/конструирование итога вручную).
  final DedupReport? dedup;
}

/// Тонкая сборка этапов v3 из портов (без бюджетов/калибровок/recovery).
class GenerationV3Facade {
  /// Создаёт фасад; все этапы приходят портами.
  GenerationV3Facade({
    required this.engine,
    required this.replenish,
    required this.profile,
    this.understanding,
    this.validator = const CardValidator(),
    this.sink,
    this.importer,
    this.promptVersions = const <String, String>{},
    this.outputTokensPerCard = kDefaultOutputTokensPerCard,
    this.matcher = const SemanticMatcher(),
    this.deckCards,
    this.dedupMarks,
  });

  /// Этап Generation (партии карточек поверх `LlmPort`).
  final CardsBatchEngine engine;

  /// Этап Replenish (добор долга по единицам).
  final ReplenishStage replenish;

  /// Профиль модели: окно, предел вывода, схема (этап Allocation).
  final ModelProfile profile;

  /// Этап Understanding; `null` — только prompt-only (тема одной единицей).
  final UnderstandingStage? understanding;

  /// Этап Validation (та же реализация, что за [CardValidatorGate]).
  final CardValidator validator;

  /// Запись принятого по ходу (этап Persistence); `null` — прогон без журнала.
  final CardSink? sink;

  /// Импорт черновиков в колоду; `null` — без импорта.
  final RunImporter? importer;

  /// Версии промптов по этапам (у домена промптов нет).
  final Map<String, String> promptVersions;

  /// Оценка вывода одной карточки при упаковке партий.
  final int outputTokensPerCard;

  /// Матчер каскада Dedup (S6, ADR-050 §3.4). Новых правил фасад не пишет.
  final SemanticMatcher matcher;

  /// Карточки целевой колоды для сверки «уже в колоде»; `null` — только
  /// внутрипрогонная сверка.
  final DeckCardsLoader? deckCards;

  /// Запись пометок дедупа в журнал прогона (L219); `null` — без персиста.
  final DedupMarkSink? dedupMarks;

  /// Запускает прогон: материал или тема → карточки в колоде + отчёт.
  ///
  /// [requestedCards] `null` — авто-режим пользователя: заказ равен числу
  /// единиц карты (по одной карточке на утверждение), минимум одна. Явный
  /// заказ не режется и не «дотягивается»: его выполнимость показывает отчёт.
  Future<GenerationV3Run> run({
    required String runId,
    required int? requestedCards,
    Document? document,
    String? theme,
    String? targetDeckId,
    CancellationSignal? cancellation,
    DateTime? startedAt,
  }) async {
    final _Understood understood = await _understand(document, theme);
    final int requested =
        requestedCards ??
        (understood.units.isEmpty ? 1 : understood.units.length);
    final KnowledgeMap map = KnowledgeMap(
      documentId: document?.fileName ?? 'prompt',
      units: understood.units,
    );
    final AllocationPlan plan = planAllocation(
      map: map,
      requestedCards: requested,
      profile: profile,
      outputTokensPerCard: outputTokensPerCard,
    );

    final _GateRun gated = await _generate(
      plan: plan,
      map: map,
      document: document,
      cancellation: cancellation,
      startedAt: startedAt,
    );

    final ReplenishOutcome outcome = gated.outcome;
    final List<GeneratedCard> accepted = outcome.acceptedCards;
    // Первый проход пишет принятое в **свой** [CardSink] по ходу (инвариант
    // ARCH §3.5). Если у движка приёмника нет (тесты пути без журнала),
    // фасад пишет всё принятое сам; иначе — только карточки добора.
    final int alreadyWritten = engine.sink == null
        ? 0
        : (gated.generation?.acceptedCards.length ?? 0);
    await _persist(accepted.skip(alreadyWritten).toList(), _batchOfUnit(plan));
    // Этап Dedup (TASK «Срез 13», часть 1): между валидацией и итоговым
    // журналом/импортом. Дубль **не удаляется** — помечается парой каскада;
    // строки черновиков уже записаны по ходу, пометки их дополняют (L219).
    final _DedupOutcome deduped = await _dedup(
      runId: runId,
      cards: accepted,
      targetDeckId: targetDeckId,
    );

    final GenerationReport report = GenerationReport.fromReplenish(
      plan: plan,
      outcome: outcome,
      initialUsage: gated.generation?.usage ?? const TokenUsage(),
      understandingUsage: understood.usage,
      promptVersions: promptVersions,
      understandingFailures: understood.failures,
      batchDurations: gated.generation?.batchDurations ?? const <Duration>[],
      duplicatesByLevel: deduped.report.byLevel,
      acceptedCards: deduped.cards,
      duplicateMarked: deduped.markedCards,
      understandingRequests: understood.requests,
    );
    final int imported = importer == null ? 0 : await importer!(runId);
    return GenerationV3Run(
      runId: runId,
      map: map,
      plan: plan,
      report: report,
      acceptedCards: List<GeneratedCard>.unmodifiable(deduped.cards),
      blockedCards: List<GeneratedCard>.unmodifiable(gated.blocked),
      imported: imported,
      dedup: deduped.report,
    );
  }

  /// Понимание материала или единственная единица темы (prompt-only).
  Future<_Understood> _understand(Document? document, String? theme) async {
    if (document != null) {
      final UnderstandingStage? stage = understanding;
      if (stage == null) {
        throw ArgumentError('Без этапа Understanding материал не понять');
      }
      final UnderstandingResult result = await stage(document);
      final List<String> failures = <String>[
        for (final KnowledgeMapFragmentOutcome fragment in result.failures)
          if (fragment.failureReason != null) fragment.failureReason!.code,
      ];
      if (result.map.units.isEmpty &&
          failures.isEmpty &&
          (document.sections.isEmpty || document.contentLength == 0)) {
        // Скан без текстового слоя: Understanding не звал модель, и «ноль
        // единиц» — не недобор модели, а свойство материала (п. 10 среза 11).
        failures.add(kNoTextLayerCode);
      }
      return _Understood(
        units: result.map.units,
        usage: result.fromCache
            ? const TokenUsage(
                promptTokens: 0,
                completionTokens: 0,
                totalTokens: 0,
              )
            : result.usage,
        failures: failures,
        // Из кэша карты запросов не было — `UnderstandingResult.requests` = 0.
        requests: result.requests,
      );
    }
    final String topic = theme?.trim() ?? '';
    if (topic.isEmpty) {
      throw ArgumentError('Нужен материал или тема: иначе нечего генерировать');
    }
    return _Understood(
      units: <KnowledgeUnit>[
        KnowledgeUnit(
          id: 'ku:prompt#0',
          sectionId: 'prompt',
          topic: topic,
          kind: KnowledgeUnitKind.topic,
          statement: topic,
          salience: 1,
        ),
      ],
    );
  }

  /// Генерация, гейт и добор: один гейт на оба прохода (п. 4 среза 11).
  Future<_GateRun> _generate({
    required AllocationPlan plan,
    required KnowledgeMap map,
    required Document? document,
    required CancellationSignal? cancellation,
    required DateTime? startedAt,
  }) async {
    if (plan.cards.isEmpty) {
      // Плана по единицам нет (скан без текстового слоя, пустая карта): модель
      // не зовём, но отчёт обязан объяснить нулевой результат, а не упасть.
      return _GateRun(
        generation: null,
        outcome: ReplenishOutcome(
          stage: GenerationStage.partial,
          reason: ReplenishStopReason.exhaustedMaterial,
          requested: plan.requested,
          unfilledSlots: plan.requested,
        ),
        blocked: const <GeneratedCard>[],
      );
    }

    final CardValidatorGate gate = CardValidatorGate(
      validator: validator,
      document: document,
      knownUnitIds: <String>{
        for (final UnitBudget budget in plan.units) budget.unit.id,
      },
      unanchoredUnitIds: map.unanchoredUnitIds,
    );
    final CardsBatchRun generation = await engine.run(
      plan,
      gate: gate,
      cancellation: cancellation,
    );
    final ReplenishOutcome outcome = await replenish.run(
      plan: plan,
      ledger: generation.ledger,
      acceptedCards: generation.acceptedCards,
      // Карточки первого прохода уже израсходовали попытку своего слота: вторая
      // блокировка закрывает слот как validation_rejects (п. 3 среза 11).
      initialBlockedCards: generation.blockedCards,
      gate: gate,
      initialUsage: generation.usage,
      startedAt: startedAt,
      cancellation: cancellation,
    );
    return _GateRun(
      generation: generation,
      outcome: outcome,
      blocked: <GeneratedCard>[
        ...generation.blockedCards,
        ...outcome.blockedCards,
      ],
    );
  }

  /// Номер партии плана для каждой единицы (единица живёт в одной партии).
  static Map<String, int> _batchOfUnit(AllocationPlan plan) {
    final Map<String, int> index = <String, int>{};
    for (final AllocationBatch batch in plan.batches) {
      for (final AllocatedCard card in batch.cards) {
        index.putIfAbsent(card.unitId, () => batch.index);
      }
    }
    return index;
  }

  Future<void> _persist(
    List<GeneratedCard> cards,
    Map<String, int> batchOfUnit,
  ) async {
    final CardSink? target = sink;
    if (target == null) return;
    for (final GeneratedCard card in cards) {
      await target.save(card, batchIndex: batchOfUnit[card.unitId] ?? 0);
    }
  }

  /// Этап Dedup: каскад `SemanticMatcher` по принятым и целевой колоде.
  ///
  /// Дубль **не удаляется**: карточка помечается `possibleDuplicate` (пометка
  /// гейта для отчёта и `issues` для предпросмотра), пара попадает в
  /// [DedupReport], счётчики — в отчёт по уровням. Пометки пишутся в журнал
  /// прогона, поэтому перезапуск их не теряет (L219).
  Future<_DedupOutcome> _dedup({
    required String runId,
    required List<GeneratedCard> cards,
    required String? targetDeckId,
  }) async {
    final List<DedupCard> incoming = <DedupCard>[
      for (var index = 0; index < cards.length; index++)
        DedupCard(
          id: _runCardId(index),
          front: cards[index].front,
          back: cards[index].back,
        ),
    ];
    List<DedupCard> existing = const <DedupCard>[];
    if (targetDeckId != null && deckCards != null) {
      existing = await deckCards!(targetDeckId);
    }
    if (incoming.isEmpty) {
      return _DedupOutcome(
        cards: cards,
        report: DedupReport.empty(),
        markedCards: 0,
      );
    }

    final DedupReport report = matcher.match(incoming, existing: existing);
    if (report.pairCount == 0) {
      return _DedupOutcome(cards: cards, report: report, markedCards: 0);
    }

    // Сильнейшая пара каждой карточки прогона и вторая сторона пары.
    final Map<int, ({DedupLevel level, String otherId})> strongest =
        <int, ({DedupLevel level, String otherId})>{};
    for (final DedupPair pair in report.pairs) {
      final int? left = _runIndex(pair.leftId);
      final int? right = _runIndex(pair.rightId);
      // Пара внутри колоды — не наша работа: обе стороны уже в колоде.
      if (left == null && right == null) continue;
      if (left != null) {
        _rememberStrongest(
          strongest,
          index: left,
          level: pair.level,
          otherId: pair.rightId,
        );
      }
      if (right != null) {
        _rememberStrongest(
          strongest,
          index: right,
          level: pair.level,
          otherId: pair.leftId,
        );
      }
    }
    if (strongest.isEmpty) {
      return _DedupOutcome(cards: cards, report: report, markedCards: 0);
    }

    final List<GeneratedCard> markedCards = List<GeneratedCard>.of(cards);
    final Map<String, DedupMark> marksByHash = <String, DedupMark>{};
    for (final MapEntry<int, ({DedupLevel level, String otherId})> entry
        in strongest.entries) {
      final GeneratedCard card = cards[entry.key];
      markedCards[entry.key] = card.copyWith(
        issues: <CardIssueCode>[
          ...card.issues.where(
            (CardIssueCode issue) => issue != CardIssueCode.possibleDuplicate,
          ),
          CardIssueCode.possibleDuplicate,
        ],
        gateReasons: <CardReasonCode>[
          ...card.gateReasons.where(
            (CardReasonCode reason) =>
                reason != CardReasonCode.possibleDuplicate,
          ),
          CardReasonCode.possibleDuplicate,
        ],
      );
      final String hash = draftContentHashOf(card);
      final DedupMark mark = DedupMark(
        contentHash: hash,
        duplicateOf: _persistableIdOf(entry.value.otherId, cards),
        level: entry.value.level,
      );
      final DedupMark? previous = marksByHash[hash];
      // Одинаковое содержимое — одна строка черновика: храним сильнейший уровень.
      if (previous == null || mark.level.index < previous.level.index) {
        marksByHash[hash] = mark;
      }
    }
    if (dedupMarks != null && marksByHash.isNotEmpty) {
      await dedupMarks!(runId, marksByHash.values.toList(growable: false));
    }
    return _DedupOutcome(
      cards: markedCards,
      report: report,
      markedCards: strongest.length,
    );
  }

  /// Помнит сильнейший уровень пары для карточки [index] (exact сильнее).
  static void _rememberStrongest(
    Map<int, ({DedupLevel level, String otherId})> found, {
    required int index,
    required DedupLevel level,
    required String otherId,
  }) {
    final ({DedupLevel level, String otherId})? previous = found[index];
    if (previous == null || level.index < previous.level.index) {
      found[index] = (level: level, otherId: otherId);
    }
  }

  /// Идентификатор карточки прогона в каскаде (индекс в списке принятых).
  static String _runCardId(int index) => '$_runPrefix$index';

  /// Индекс карточки прогона по идентификатору каскада; `null` — карточка
  /// колоды.
  static int? _runIndex(String id) {
    if (!id.startsWith(_runPrefix)) return null;
    return int.tryParse(id.substring(_runPrefix.length));
  }

  /// Вторая сторона пары в форме, пригодной для журнала прогона.
  ///
  /// Карточка прогона — её `content_hash` (ключ строки `card_drafts`);
  /// карточка колоды — `deck:<cards.id>` (у неё нет черновика в этом прогоне).
  static String _persistableIdOf(String id, List<GeneratedCard> cards) {
    final int? index = _runIndex(id);
    if (index == null) return DedupMark.deckKey(id);
    return draftContentHashOf(cards[index]);
  }

  /// Префикс id карточки прогона в парах каскада.
  static const String _runPrefix = 'run:';
}

/// Итог этапа Dedup: карточки с пометками, отчёт и число помеченных.
class _DedupOutcome {
  const _DedupOutcome({
    required this.cards,
    required this.report,
    required this.markedCards,
  });

  /// Принятые карточки с пометками `possibleDuplicate` (ни одна не удалена).
  final List<GeneratedCard> cards;

  /// Пары каскада и счётчики по уровням.
  final DedupReport report;

  /// Сколько карточек прогона помечено (уровень — в [report]).
  final int markedCards;
}

/// Понятый материал: единицы, расход этапа и коды помеченных фрагментов.
class _Understood {
  const _Understood({
    required this.units,
    this.usage,
    this.failures = const <String>[],
    this.requests = 0,
  });

  final List<KnowledgeUnit> units;
  final TokenUsage? usage;
  final List<String> failures;

  /// Запросов Understanding (включая повторы лестницы и деление обрывов).
  final int requests;
}

/// Итог генерации и добора под общим гейтом.
class _GateRun {
  const _GateRun({
    required this.generation,
    required this.outcome,
    required this.blocked,
  });

  /// Первый проход; `null` — плана по единицам нет.
  final CardsBatchRun? generation;

  final ReplenishOutcome outcome;
  final List<GeneratedCard> blocked;
}
