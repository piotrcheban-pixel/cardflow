/// Сквозной путь генерации v3 (TASK «Срез 10», п. 6–7; ARCH §2, ADR-050).
///
/// Фасад **собирает этапы из портов** и не содержит собственной политики:
/// ни бюджетов, ни калибровок, ни recovery-логики. Он делает ровно четыре
/// вещи:
/// 1) понимание материала — [UnderstandingStage] (или единственная единица
///    `kind=topic` для prompt-only);
/// 2) план заказа — `planAllocation` (этап Allocation);
/// 3) генерация — [CardsBatchEngine] (партии, повторы — внутри движка);
/// 4) проверка, добор и журнал — [CardValidator], [ReplenishStage],
///    [CardSink]/`importRun`.
///
/// Итог — [GenerationReport]: «заказано/принято», причины недобора с числами,
/// покрытие единиц и предохранители операции. Легаси-конвейер
/// (`generation_pipeline.dart`) не меняется: флаг `generationPipelineV3`
/// остаётся выключенным по умолчанию (протокол §9), поэтому проводка
/// production-провайдеров — следующий шаг (`journal/QUESTIONS.md` Q22).
library;

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/validation/card_validator.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Этап Understanding: материал → карта знаний (без сети внутри фасада).
typedef UnderstandingStage = Future<KnowledgeMap> Function(Document document);

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

  /// Этап Validation.
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
  Future<GenerationV3Run> run({
    required String runId,
    required int requestedCards,
    Document? document,
    String? theme,
    CancellationSignal? cancellation,
    DateTime? startedAt,
  }) async {
    final List<KnowledgeUnit> units = await _unitsOf(document, theme);
    final KnowledgeMap map = KnowledgeMap(
      documentId: document?.fileName ?? 'prompt',
      units: units,
    );
    final AllocationPlan plan = planAllocation(
      map: map,
      requestedCards: requestedCards,
      profile: profile,
      outputTokensPerCard: outputTokensPerCard,
    );

    final CardsBatchRun generation = await engine.run(
      plan,
      cancellation: cancellation,
    );
    final ({
      List<GeneratedCard> accepted,
      List<GeneratedCard> blocked,
      GenerationLedger ledger,
    })
    checked = _validate(
      generation.acceptedCards,
      run: generation,
      plan: plan,
      map: map,
      document: document,
    );

    final ReplenishOutcome outcome = await replenish.run(
      plan: plan,
      ledger: checked.ledger,
      acceptedCards: checked.accepted,
      startedAt: startedAt,
      cancellation: cancellation,
    );

    // Добор тоже проходит проверку: иначе жёсткий дефект вернулся бы в колоду
    // «через чёрный ход» (в тесте — повторно сгенерированный blocked-карточкой).
    final List<GeneratedCard> fresh = <GeneratedCard>[
      for (final GeneratedCard card in outcome.acceptedCards)
        if (!checked.accepted.contains(card)) card,
    ];
    final ({
      List<GeneratedCard> accepted,
      List<GeneratedCard> blocked,
      GenerationLedger ledger,
    })
    replenished = _validate(
      fresh,
      run: null,
      plan: plan,
      map: map,
      document: document,
    );
    final List<GeneratedCard> accepted = <GeneratedCard>[
      ...checked.accepted,
      ...replenished.accepted,
    ];
    await _persist(accepted, _batchOfUnit(plan));

    final GenerationReport report = GenerationReport.fromReplenish(
      plan: plan,
      outcome: _withAccepted(
        outcome,
        accepted,
        invalid: outcome.invalid + replenished.blocked.length,
      ),
      initialUsage: generation.usage,
      promptVersions: promptVersions,
    );
    final int imported = importer == null ? 0 : await importer!(runId);
    return GenerationV3Run(
      runId: runId,
      map: map,
      plan: plan,
      report: report,
      acceptedCards: List<GeneratedCard>.unmodifiable(accepted),
      blockedCards: List<GeneratedCard>.unmodifiable(<GeneratedCard>[
        ...checked.blocked,
        ...replenished.blocked,
      ]),
      imported: imported,
    );
  }

  Future<List<KnowledgeUnit>> _unitsOf(
    Document? document,
    String? theme,
  ) async {
    if (document != null) {
      final UnderstandingStage? stage = understanding;
      if (stage == null) {
        throw ArgumentError('Без этапа Understanding материал не понять');
      }
      return (await stage(document)).units;
    }
    final String topic = theme?.trim() ?? '';
    if (topic.isEmpty) {
      throw ArgumentError('Нужен материал или тема: иначе нечего генерировать');
    }
    return <KnowledgeUnit>[
      KnowledgeUnit(
        id: 'ku:prompt#0',
        sectionId: 'prompt',
        topic: topic,
        kind: KnowledgeUnitKind.topic,
        statement: topic,
        salience: 1,
      ),
    ];
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

  /// Проверка карточек: жёсткие дефекты блокируются и считаются отброшенными.
  ///
  /// [run] — итог первого прохода: его журнал дополняется отброшенными, чтобы
  /// бухгалтерия (`accepted = generated − invalid − duplicates`) совпадала со
  /// списком принятого. Для карточек добора (`run == null`) журнал не нужен.
  ({
    List<GeneratedCard> accepted,
    List<GeneratedCard> blocked,
    GenerationLedger ledger,
  })
  _validate(
    List<GeneratedCard> cards, {
    required CardsBatchRun? run,
    required AllocationPlan plan,
    required KnowledgeMap map,
    required Document? document,
  }) {
    final Map<String, int> batchOfUnit = _batchOfUnit(plan);
    final List<GeneratedCard> accepted = <GeneratedCard>[];
    final List<GeneratedCard> blocked = <GeneratedCard>[];
    final Map<int, int> blockedPerBatch = <int, int>{};
    GenerationLedger ledger = run?.ledger ?? GenerationLedger.empty();

    for (final GeneratedCard card in cards) {
      final CardValidationReport report = validator.validate(
        <String, Object?>{
          'cards': <Object?>[_cardJson(card)],
        },
        document: document,
        knownUnitIds: <String>{
          for (final UnitBudget budget in plan.units) budget.unit.id,
        },
        unanchoredUnitIds: map.unanchoredUnitIds,
      );
      final int batchIndex = batchOfUnit[card.unitId] ?? 0;
      if (report.blockedCount > 0) {
        blocked.add(card);
        blockedPerBatch[batchIndex] = (blockedPerBatch[batchIndex] ?? 0) + 1;
      } else {
        accepted.add(card);
      }
    }
    if (run != null) {
      for (final MapEntry<int, int> entry in blockedPerBatch.entries) {
        ledger = ledger.record(entry.key, invalid: entry.value);
      }
    }
    return (accepted: accepted, blocked: blocked, ledger: ledger);
  }

  static Map<String, Object?> _cardJson(GeneratedCard card) =>
      <String, Object?>{
        'front': card.front,
        'back': card.back,
        'card_type': card.cardType.wireName,
        'hint': card.hint,
        'tags': card.tags,
        'unit_id': card.unitId,
        'angle': card.angle,
        'quote_ref': card.quoteRef,
        'section_id': card.sectionId,
        'source_excerpt': card.sourceExcerpt,
      };

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

  /// Итог добора с принятым, включающим проверенные карточки первого прохода.
  ReplenishOutcome _withAccepted(
    ReplenishOutcome outcome,
    List<GeneratedCard> accepted, {
    required int invalid,
  }) => ReplenishOutcome(
    stage: outcome.stage,
    reason: outcome.reason,
    requested: outcome.requested,
    acceptedCards: accepted,
    passes: outcome.passes,
    requests: outcome.requests,
    invalid: invalid,
    duplicates: outcome.duplicates,
    usage: outcome.usage,
    duration: outcome.duration,
    unfilledSlots: outcome.unfilledSlots,
    guards: outcome.guards,
  );
}
