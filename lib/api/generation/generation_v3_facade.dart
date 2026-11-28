/// Сквозной путь генерации v3 (TASK «Срез 10», п. 6–7; срез 11 — гейт,
/// HTTP-карта и проводка; ARCH §2, ADR-050).
///
/// Фасад **собирает этапы из портов** и не содержит собственной политики:
/// ни бюджетов, ни калибровок, ни recovery-логики. Он делает ровно четыре
/// вещи:
/// 1) понимание материала — [UnderstandingStage] (или единственная единица
///    `kind=topic` для prompt-only);
/// 2) план заказа — `planAllocation` (этап Allocation);
/// 3) генерация — [CardsBatchEngine] (партии, повторы — внутри движка);
/// 4) проверка, добор и журнал — гейт [CardGate] (тот же, что у добора),
///    [ReplenishStage], [CardSink]/импорт.
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
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

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

    final GenerationReport report = GenerationReport.fromReplenish(
      plan: plan,
      outcome: outcome,
      initialUsage: gated.generation?.usage ?? const TokenUsage(),
      understandingUsage: understood.usage,
      promptVersions: promptVersions,
      understandingFailures: understood.failures,
      batchDurations: gated.generation?.batchDurations ?? const <Duration>[],
      duplicatesByLevel:
          gated.generation?.ledger.dedup.byLevel ?? const <DedupLevel, int>{},
    );
    final int imported = importer == null ? 0 : await importer!(runId);
    return GenerationV3Run(
      runId: runId,
      map: map,
      plan: plan,
      report: report,
      acceptedCards: List<GeneratedCard>.unmodifiable(accepted),
      blockedCards: List<GeneratedCard>.unmodifiable(gated.blocked),
      imported: imported,
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
}

/// Понятый материал: единицы, расход этапа и коды помеченных фрагментов.
class _Understood {
  const _Understood({
    required this.units,
    this.usage,
    this.failures = const <String>[],
  });

  final List<KnowledgeUnit> units;
  final TokenUsage? usage;
  final List<String> failures;
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
