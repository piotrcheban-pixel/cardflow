/// Replenish — этап добора долга (TASK «Срез 7», ARCH §2 этап 7, ADR-050).
///
/// Долг не «сколько вернулось сейчас», а разница между заказом и принятым:
/// [GenerationLedger] первого прохода называет число и причину, а этот этап
/// решает, **чего** не хватает. Добор идёт только по карточкам заказа, которым
/// не нашлось принятой пары (`unit_id` + `angle`), и только по единицам карты:
/// новые единицы знания не выдумываются (TASK п. 1). Каждая партия добора несёт
/// контекст уже принятого по своим единицам (`<already_accepted>` промпта
/// `gen-cards-v3`) — поэтому модель не пересказывает принятые факты.
///
/// Предохранители операции (TASK п. 2) — все проверяются до запроса и попадают
/// в итог с точной причиной ([ReplenishStopReason]):
/// - [ReplenishPolicy.maxPasses] = 3 прохода — бесконечный цикл невозможен;
/// - [ReplenishPolicy.maxRequests] = `f(requested)` запросов на операцию
///   (первый проход тоже считается);
/// - [ReplenishPolicy.tokenBudget] — расход токенов операции (факт ответа, при
///   неизвестном расходе — оценка партии, чтобы бюджет не был фикцией);
/// - [ReplenishPolicy.wallClock] — время операции от [ReplenishStage.run].
///
/// `exhausted_material` — не ошибка и не повод добирать (TASK п. 3): если
/// первый проход уже объявил материал исчерпанным или проход не закрыл ни одного
/// слота долга, этап останавливается и сообщает, на сколько карточек материала
/// хватило ([ReplenishOutcome.materialCapacity]). Недобор никогда не становится
/// успехом: [GenerationStage.ready] возможен только при закрытых слотах заказа.
///
/// Этап без сети в правилах: `LlmPort` — доменный порт, время — [Clock],
/// отмена — [CancellationSignal]. HTTP и ключи живут в `lib/api/`.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';

/// Предел запросов операции добора: `f(requested)` (TASK «Срез 7», п. 2).
///
/// Не больше одного запроса на заказанную карточку, но не меньше трёх: даже
/// заказ из одной карточки может потребовать короткого добора, а «ноль
/// запросов» означал бы, что предохранитель отключён. Первый проход Generation
/// тоже считается (журнал несёт `attempts`), поэтому предел никогда не меньше
/// числа уже сделанных запросов плана — иначе добор был бы невозможен.
int maxRequestsForRequested(int requested) {
  if (requested <= 0) return 0;
  return math.max(3, requested);
}

/// Бюджет токенов операции по оценкам плана (TASK п. 2).
///
/// Оценка партий ([AllocationBatch.totalTokens]) — вход плюс выход каждого
/// запроса; [passes] — сколько проходов добора допускает политика (+1 — сам
/// первый проход). Бюджет не «на глаз»: он выводится из того же плана, что
/// уходит в модель.
int tokenBudgetForPlan(
  AllocationPlan plan, {
  int passes = ReplenishPolicy.defaultMaxPasses,
}) {
  if (passes < 0) {
    throw ArgumentError.value(
      passes,
      'passes',
      'Число проходов не может быть отрицательным',
    );
  }
  var total = 0;
  for (final AllocationBatch batch in plan.batches) {
    total += batch.totalTokens;
  }
  return total * (passes + 1);
}

/// Причина остановки добора (TASK п. 2: «partial с точной причиной»).
///
/// [wireName] — машинный код для журнала запуска и отчёта; пользовательский
/// текст живёт в ARB на слое UI.
enum ReplenishStopReason {
  /// Долг закрыт: принято всё, что заказано.
  complete('complete'),

  /// Материал исчерпан: больше качественных карточек из него не сделать.
  ///
  /// Это не ошибка и не повод добирать (TASK п. 3): число, на которое хватило
  /// материала, — [ReplenishOutcome.materialCapacity].
  exhaustedMaterial('exhausted_material'),

  /// Исчерпан предохранитель проходов ([ReplenishPolicy.maxPasses]).
  maxPasses('max_passes'),

  /// Исчерпан предохранитель запросов ([ReplenishPolicy.maxRequests]).
  maxRequests('max_requests'),

  /// Исчерпан бюджет токенов операции ([ReplenishPolicy.tokenBudget]).
  tokenBudget('token_budget'),

  /// Исчерпан лимит времени операции ([ReplenishPolicy.wallClock]).
  wallClock('wall_clock'),

  /// Провайдер не ответил или ответил ошибкой: партия добора не сгенерирована.
  providerError('provider_error'),

  /// Прогон отменён пользователем; принятое сохранено.
  cancelled('cancelled'),

  /// Плана по единицам нет (prompt-only): добор по единицам невозможен, долг
  /// остаётся за старым путём.
  noUnitPlan('no_unit_plan');

  const ReplenishStopReason(this.wireName);

  /// Машинный код причины в журнале запуска (snake_case, как в TASK.txt).
  final String wireName;

  /// true — остановил предохранитель операции, а не материал и не сбой.
  bool get isGuard => switch (this) {
    ReplenishStopReason.maxPasses ||
    ReplenishStopReason.maxRequests ||
    ReplenishStopReason.tokenBudget ||
    ReplenishStopReason.wallClock => true,
    _ => false,
  };

  /// Разбирает причину из строки журнала.
  ///
  /// Неизвестная строка — [FormatException]: журнал повреждён или версия
  /// несовместима, угадывать причину нельзя.
  static ReplenishStopReason fromWire(String value) {
    for (final ReplenishStopReason reason in values) {
      if (reason.wireName == value) return reason;
    }
    throw FormatException('Неизвестная причина остановки добора: $value');
  }
}

/// Предохранители операции добора (TASK «Срез 7», п. 2).
class ReplenishPolicy {
  /// Создаёт политику; неположительные пределы — ошибка программиста.
  const ReplenishPolicy({
    this.maxPasses = defaultMaxPasses,
    this.maxRequests,
    this.tokenBudget,
    this.wallClock = defaultWallClock,
  }) : assert(maxPasses > 0, 'Число проходов положительно'),
       assert(
         maxRequests == null || maxRequests > 0,
         'Предел запросов положителен',
       ),
       assert(
         tokenBudget == null || tokenBudget > 0,
         'Бюджет токенов положителен',
       );

  /// Число проходов добора по умолчанию (TASK: `maxPasses = 3`).
  static const int defaultMaxPasses = 3;

  /// Предел времени операции по умолчанию.
  static const Duration defaultWallClock = Duration(minutes: 10);

  /// Сколько проходов добора допускается после первого прохода Generation.
  final int maxPasses;

  /// Предел запросов операции; `null` — [maxRequestsForRequested].
  final int? maxRequests;

  /// Бюджет токенов операции; `null` — [tokenBudgetForPlan].
  final int? tokenBudget;

  /// Предел времени операции.
  ///
  /// Положительность — обязанность вызывающего: сравнение `Duration` не
  /// вычисляется в const-конструкторе, поэтому проверки в `assert` нет.
  final Duration wallClock;

  /// Предел запросов операции для заказа [requested].
  int requestsLimit(int requested) =>
      maxRequests ?? maxRequestsForRequested(requested);

  /// Бюджет токенов операции для плана [plan].
  int tokenLimit(AllocationPlan plan) =>
      tokenBudget ?? tokenBudgetForPlan(plan, passes: maxPasses);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReplenishPolicy &&
          other.maxPasses == maxPasses &&
          other.maxRequests == maxRequests &&
          other.tokenBudget == tokenBudget &&
          other.wallClock == wallClock;

  @override
  int get hashCode =>
      Object.hash(maxPasses, maxRequests, tokenBudget, wallClock);

  @override
  String toString() =>
      'ReplenishPolicy(проходов $maxPasses, запросов '
      '${maxRequests ?? 'от заказа'}, токенов '
      '${tokenBudget ?? 'от плана'}, время $wallClock)';
}

/// Один проход добора: план (только единицы с долгом), журнал и принятое.
class ReplenishPass {
  /// Создаёт запись прохода; списки копируются и становятся неизменяемыми.
  ReplenishPass({
    required this.index,
    required this.plan,
    required this.ledger,
    List<GeneratedCard> accepted = const <GeneratedCard>[],
    this.usage = const TokenUsage(),
    this.filledSlots = 0,
    this.surplus = 0,
  }) : accepted = List<GeneratedCard>.unmodifiable(accepted);

  /// Номер прохода с 1 (первый проход Generation не считается).
  final int index;

  /// План добора: карточки долга и только единицы с недобором.
  final AllocationPlan plan;

  /// Журнал прохода: бюджеты, принятое, отброшенное, число запросов.
  final GenerationLedger ledger;

  /// Принятые в проходе карточки (порядок ответов модели).
  final List<GeneratedCard> accepted;

  /// Фактический расход токенов прохода.
  final TokenUsage usage;

  /// Сколько слотов долга закрыто этим проходом.
  final int filledSlots;

  /// Сколько карточек ответа не закрыли долг (повтор закрытого слота, чужой
  /// угол): они не приняты и не уменьшают долг (TASK: «не добирать
  /// перефразированием принятых фактов»).
  final int surplus;

  /// Бюджет прохода: сколько карточек просили.
  int get requested => plan.requested;

  /// Принято карточек в проходе.
  int get acceptedCount => accepted.length;

  /// Запросов модели в проходе.
  int get requests => ledger.attempts;

  /// id единиц, по которым шёл добор (только единицы с недобором).
  List<String> get unitIds => <String>[
    for (final UnitBudget budget in plan.units) budget.unit.id,
  ];

  @override
  String toString() =>
      'ReplenishPass($index, ${plan.requested} карт., принято $acceptedCount, '
      'слотов $filledSlots, запросов $requests)';
}

/// Итог этапа добора: этап, причина, принятое и счётчики операции.
class ReplenishOutcome {
  /// Создаёт итог; списки копируются и становятся неизменяемыми.
  ReplenishOutcome({
    required this.stage,
    required this.reason,
    required this.requested,
    List<GeneratedCard> acceptedCards = const <GeneratedCard>[],
    List<ReplenishPass> passes = const <ReplenishPass>[],
    this.requests = 0,
    this.invalid = 0,
    this.duplicates = 0,
    this.usage = const TokenUsage(),
    this.duration = Duration.zero,
    this.unfilledSlots = 0,
  }) : acceptedCards = List<GeneratedCard>.unmodifiable(acceptedCards),
       passes = List<ReplenishPass>.unmodifiable(passes);

  /// Терминальный этап прогона: [GenerationStage.ready] — только при закрытых
  /// слотах, [GenerationStage.partial] — недобор, [GenerationStage.cancelled] —
  /// отмена без принятого.
  final GenerationStage stage;

  /// Точная причина остановки (TASK п. 2).
  final ReplenishStopReason reason;

  /// Заказ карточек ([AllocationPlan.requested]).
  final int requested;

  /// Принятые карточки всей операции (первый проход и добор).
  final List<GeneratedCard> acceptedCards;

  /// Проходы добора в порядке выполнения.
  final List<ReplenishPass> passes;

  /// Запросов модели за операцию, включая первый проход и повторы.
  final int requests;

  /// Отброшено валидацией/схемой за операцию.
  final int invalid;

  /// Отброшено как дубли за операцию.
  final int duplicates;

  /// Фактический расход токенов добора (первый проход — у вызывающего).
  final TokenUsage usage;

  /// Длительность операции от [ReplenishStage.run].
  final Duration duration;

  /// Сколько слотов заказа осталось без принятой карточки.
  final int unfilledSlots;

  /// Принято карточек.
  int get accepted => acceptedCards.length;

  /// Долг: `max(0, requested − accepted)`.
  int get remaining => requested > accepted ? requested - accepted : 0;

  /// true — заказ закрыт: этап [GenerationStage.ready], все слоты заполнены и
  /// принято не меньше заказанного (недобор успехом не считается).
  bool get isComplete =>
      stage == GenerationStage.ready &&
      unfilledSlots == 0 &&
      accepted >= requested;

  /// Класс недобора для журнала; `null` — долга нет.
  ShortfallKind? get shortfall {
    if (remaining == 0) return null;
    return switch (reason) {
      ReplenishStopReason.cancelled => ShortfallKind.cancelled,
      ReplenishStopReason.providerError => ShortfallKind.providerError,
      ReplenishStopReason.exhaustedMaterial => ShortfallKind.exhaustedMaterial,
      _ => null,
    };
  }

  /// «Материала достаточно примерно на N качественных карточек» (TASK п. 3);
  /// `null` — материал не признан исчерпанным.
  int? get materialCapacity =>
      reason == ReplenishStopReason.exhaustedMaterial ? accepted : null;

  @override
  String toString() =>
      'ReplenishOutcome(${reason.wireName}, принято $accepted/$requested, '
      'слотов без карточки $unfilledSlots, проходов ${passes.length}, '
      'запросов $requests)';
}

/// Этап добора долга (TASK «Срез 7»).
class ReplenishStage {
  /// Создаёт этап.
  ReplenishStage({
    required this.port,
    required this.account,
    required this.clock,
    this.policy = const ReplenishPolicy(),
    this.estimator = const TokenEstimator(),
    this.outputTokensPerCard = kDefaultOutputTokensPerCard,
  }) : assert(
         outputTokensPerCard > 0,
         'Оценка вывода карточки должна быть положительной',
       );

  /// Вызов модели на партию (этап Generation уже прошёл первым проходом).
  final LlmPort port;

  /// Аккаунт провайдера.
  final ProviderAccount account;

  /// Время операции (wallClock) и длительность.
  final Clock clock;

  /// Предохранители операции.
  final ReplenishPolicy policy;

  /// Оценщик входа при упаковке партий добора.
  final TokenEstimator estimator;

  /// Оценка вывода одной карточки при упаковке партий добора.
  final int outputTokensPerCard;

  /// Запускает добор долга по плану [plan] и журналу первого прохода [ledger].
  ///
  /// [acceptedCards] — принятое первого прохода (то же, что считает [ledger]);
  /// [initialUsage] — расход первого прохода (входит в бюджет токенов);
  /// [startedAt] — начало операции для [ReplenishPolicy.wallClock] (по
  /// умолчанию — текущий момент по [clock]); [cancellation] — сигнал отмены.
  Future<ReplenishOutcome> run({
    required AllocationPlan plan,
    required GenerationLedger ledger,
    List<GeneratedCard> acceptedCards = const <GeneratedCard>[],
    TokenUsage initialUsage = const TokenUsage(),
    DateTime? startedAt,
    CancellationSignal? cancellation,
  }) async {
    final DateTime start = startedAt ?? clock.now();
    assert(
      plan.cards.isEmpty || ledger.requested == plan.requested,
      'Журнал и план обязаны говорить об одном заказе',
    );
    assert(
      ledger.accepted == acceptedCards.length,
      'Принятое журнала и список карточек обязаны совпадать',
    );

    final int requestsLimit = policy.requestsLimit(plan.requested);
    final int tokenLimit = policy.tokenLimit(plan);

    final Map<String, KnowledgeUnit> unitsById = <String, KnowledgeUnit>{
      for (final UnitBudget budget in plan.units) budget.unit.id: budget.unit,
    };
    final List<GeneratedCard> accepted = List<GeneratedCard>.of(acceptedCards);
    final Set<String> satisfied = <String>{
      for (final GeneratedCard card in accepted)
        if (card.unitId != null)
          _slot(card.unitId!, _normalizeAngle(card.angle)),
    };
    final Map<String, List<AcceptedCard>> context =
        <String, List<AcceptedCard>>{};
    for (final GeneratedCard card in accepted) {
      final String? unitId = card.unitId;
      final KnowledgeUnit? unit = unitId == null ? null : unitsById[unitId];
      if (unit == null) continue;
      context
          .putIfAbsent(unit.id, () => <AcceptedCard>[])
          .add(AcceptedCard(front: card.front, statement: unit.statement));
    }
    // Долг единиц, которые первый проход уже объявил исчерпанными, не
    // добирается: это не ошибка и не повод просить модель снова (TASK п. 3).
    final Set<String> exhaustedUnits = <String>{};
    for (final GenerationBatchLedger batch in ledger.batches) {
      if (batch.cause != ShortfallKind.exhaustedMaterial) continue;
      if (batch.batchIndex >= plan.batches.length) continue;
      for (final AllocatedCard card in plan.batches[batch.batchIndex].cards) {
        exhaustedUnits.add(card.unitId);
      }
    }

    var requests = ledger.attempts;
    var spent = _knownTokens(initialUsage);
    var usage = const TokenUsage();
    var invalid = ledger.invalid;
    var duplicates = ledger.duplicates;
    var unfilled = plan.cards.isEmpty
        ? math.max(0, plan.requested - accepted.length)
        : _unfilledSlots(plan, satisfied);
    final List<ReplenishPass> passes = <ReplenishPass>[];
    ReplenishStopReason reason = ReplenishStopReason.complete;

    if (unfilled > 0) {
      List<AllocatedCard> debt = _debtOf(plan, satisfied, exhaustedUnits);
      if (cancellation?.isCancelled ?? false) {
        reason = ReplenishStopReason.cancelled;
      } else if (ledger.shortfall == ShortfallKind.cancelled) {
        reason = ReplenishStopReason.cancelled;
      } else if (plan.cards.isEmpty || plan.units.isEmpty) {
        reason = ReplenishStopReason.noUnitPlan;
      } else if (debt.isEmpty) {
        reason = ReplenishStopReason.exhaustedMaterial;
      } else {
        while (true) {
          if (passes.length >= policy.maxPasses) {
            reason = ReplenishStopReason.maxPasses;
            break;
          }
          final ReplenishStopReason? guard = _stopBeforeRequest(
            cancellation: cancellation,
            now: clock.now(),
            startedAt: start,
            wallClock: policy.wallClock,
            requests: requests,
            requestsLimit: requestsLimit,
            spent: spent,
            tokenLimit: tokenLimit,
          );
          if (guard != null) {
            reason = guard;
            break;
          }

          final _PassRun result = await _runPass(
            index: passes.length + 1,
            debt: debt,
            plan: plan,
            unitsById: unitsById,
            context: context,
            satisfied: satisfied,
            requests: requests,
            spent: spent,
            requestsLimit: requestsLimit,
            tokenLimit: tokenLimit,
            startedAt: start,
            cancellation: cancellation,
          );
          passes.add(result.pass);
          requests = result.requests;
          spent = result.spent;
          usage = _addUsage(usage, result.usage);
          invalid += result.pass.ledger.invalid;
          duplicates += result.pass.ledger.duplicates;
          accepted.addAll(result.pass.accepted);

          final ReplenishStopReason? stop = result.stop;
          if (stop != null) {
            reason = stop;
            break;
          }
          unfilled = _unfilledSlots(plan, satisfied);
          if (result.pass.filledSlots == 0) {
            // Ответ не закрыл ни одного слота: материал по этим вопросам
            // исчерпан, добирать перефразированием запрещено (TASK п. 3).
            reason = ReplenishStopReason.exhaustedMaterial;
            break;
          }
          debt = _debtOf(plan, satisfied, exhaustedUnits);
          if (debt.isEmpty) {
            reason = unfilled == 0
                ? ReplenishStopReason.complete
                : ReplenishStopReason.exhaustedMaterial;
            break;
          }
        }
      }
    }

    if (plan.cards.isEmpty) {
      unfilled = math.max(0, plan.requested - accepted.length);
    }
    final GenerationStage stage = _stageOf(reason, accepted.length);
    return ReplenishOutcome(
      stage: stage,
      reason: reason,
      requested: plan.requested,
      acceptedCards: accepted,
      passes: passes,
      requests: requests,
      invalid: invalid,
      duplicates: duplicates,
      usage: usage,
      duration: clock.now().difference(start),
      unfilledSlots: unfilled,
    );
  }

  /// Терминальный этап по причине остановки.
  ///
  /// [GenerationStage.ready] — только закрытый заказ: недобор успехом не
  /// становится. Отмена без принятого — [GenerationStage.cancelled], с
  /// принятым — [GenerationStage.partial]: принятое сохраняется (TASK DoD).
  GenerationStage _stageOf(ReplenishStopReason reason, int acceptedCount) {
    if (reason == ReplenishStopReason.complete) return GenerationStage.ready;
    if (reason == ReplenishStopReason.cancelled && acceptedCount == 0) {
      return GenerationStage.cancelled;
    }
    return GenerationStage.partial;
  }

  /// Один проход добора: партии из карточек [debt] с контекстом принятого.
  Future<_PassRun> _runPass({
    required int index,
    required List<AllocatedCard> debt,
    required AllocationPlan plan,
    required Map<String, KnowledgeUnit> unitsById,
    required Map<String, List<AcceptedCard>> context,
    required Set<String> satisfied,
    required int requests,
    required int spent,
    required int requestsLimit,
    required int tokenLimit,
    required DateTime startedAt,
    required CancellationSignal? cancellation,
  }) async {
    final AllocationPlan passPlan = _passPlan(debt, plan);
    GenerationLedger passLedger = GenerationLedger.fromBudgets(<int>[
      for (final AllocationBatch batch in passPlan.batches) batch.cards.length,
    ]);
    final List<GeneratedCard> accepted = <GeneratedCard>[];
    var usage = const TokenUsage();
    var requestsNow = requests;
    var spentNow = spent;
    var filled = 0;
    var surplus = 0;
    ReplenishStopReason? stop;

    for (final AllocationBatch batch in passPlan.batches) {
      stop = _stopBeforeRequest(
        cancellation: cancellation,
        now: clock.now(),
        startedAt: startedAt,
        wallClock: policy.wallClock,
        requests: requestsNow,
        requestsLimit: requestsLimit,
        spent: spentNow,
        tokenLimit: tokenLimit,
      );
      if (stop != null) break;

      final List<KnowledgeUnit> batchUnits = <KnowledgeUnit>[];
      final Set<String> batchUnitIds = <String>{};
      for (final AllocatedCard card in batch.cards) {
        final KnowledgeUnit? unit = unitsById[card.unitId];
        if (unit != null && batchUnitIds.add(unit.id)) batchUnits.add(unit);
      }
      final List<AcceptedCard> requestContext = <AcceptedCard>[
        for (final KnowledgeUnit unit in batchUnits) ...?context[unit.id],
      ];
      final CardsBatch request = CardsBatch(
        index: batch.index,
        units: batchUnits,
        cards: batch.cards,
        accepted: requestContext,
        topUp: true,
      );
      final Set<String> requestedSlots = <String>{
        for (final AllocatedCard card in batch.cards)
          _slot(card.unitId, card.angle?.wireName),
      };

      passLedger = passLedger.attempt(batch.index);
      requestsNow++;
      GenerationResult result;
      try {
        result = await port.generate(
          request,
          account: account,
          maxOutputTokens: batch.outputTokens,
        );
      } on GenerationException catch (error) {
        final bool cancelledNow =
            error.code == GenerationErrorCode.cancelled ||
            (cancellation?.isCancelled ?? false);
        passLedger = passLedger.markCause(
          batch.index,
          cancelledNow ? ShortfallKind.cancelled : ShortfallKind.providerError,
        );
        stop = cancelledNow
            ? ReplenishStopReason.cancelled
            : ReplenishStopReason.providerError;
        break;
      }
      spentNow += _requestCost(result.usage, batch);
      usage = _addUsage(usage, result.usage);

      var produced = 0;
      for (final GeneratedCard card in result.cards) {
        final String? unitId = card.unitId;
        if (unitId == null || !batchUnitIds.contains(unitId)) continue;
        final KnowledgeUnit unit = unitsById[unitId]!;
        final String slot = _slot(unitId, _normalizeAngle(card.angle));
        if (!satisfied.contains(slot) && requestedSlots.contains(slot)) {
          satisfied.add(slot);
          filled++;
          produced++;
          accepted.add(card);
          context
              .putIfAbsent(unit.id, () => <AcceptedCard>[])
              .add(AcceptedCard(front: card.front, statement: unit.statement));
        } else {
          // Повтор закрытого слота или незаказанный угол: долг не уменьшает и
          // в принятое не идёт (TASK: не добирать перефразированием).
          surplus++;
        }
      }
      passLedger = passLedger.record(
        batch.index,
        generated: produced + result.rejectedCards,
        invalid: result.rejectedCards,
      );
    }

    return _PassRun(
      pass: ReplenishPass(
        index: index,
        plan: passPlan,
        ledger: passLedger,
        accepted: accepted,
        usage: usage,
        filledSlots: filled,
        surplus: surplus,
      ),
      stop: stop,
      requests: requestsNow,
      spent: spentNow,
      usage: usage,
    );
  }

  /// План добора: карточки долга по единицам карты (новые единицы не берутся).
  AllocationPlan _passPlan(List<AllocatedCard> debt, AllocationPlan source) {
    final Map<String, List<AllocatedCard>> byUnit =
        <String, List<AllocatedCard>>{};
    for (final AllocatedCard card in debt) {
      byUnit.putIfAbsent(card.unitId, () => <AllocatedCard>[]).add(card);
    }
    final List<UnitBudget> units = <UnitBudget>[];
    final List<AllocatedCard> cards = <AllocatedCard>[];
    for (final UnitBudget budget in source.units) {
      final List<AllocatedCard>? unitCards = byUnit[budget.unit.id];
      if (unitCards == null) continue;
      units.add(UnitBudget(unit: budget.unit, cards: unitCards.length));
      cards.addAll(unitCards);
    }
    return AllocationPlan(
      requested: cards.length,
      profile: source.profile,
      units: units,
      cards: cards,
      batches: packBatches(
        units: units,
        cards: cards,
        profile: source.profile,
        estimator: estimator,
        outputTokensPerCard: outputTokensPerCard,
      ),
    );
  }

  /// Карточки заказа, которым не нашлось принятой пары и которые можно добрать.
  static List<AllocatedCard> _debtOf(
    AllocationPlan plan,
    Set<String> satisfied,
    Set<String> exhaustedUnits,
  ) => <AllocatedCard>[
    for (final AllocatedCard card in plan.cards)
      if (!satisfied.contains(_slot(card.unitId, card.angle?.wireName)) &&
          !exhaustedUnits.contains(card.unitId))
        card,
  ];

  /// Сколько слотов заказа осталось без принятой карточки.
  static int _unfilledSlots(AllocationPlan plan, Set<String> satisfied) {
    var count = 0;
    for (final AllocatedCard card in plan.cards) {
      if (!satisfied.contains(_slot(card.unitId, card.angle?.wireName))) {
        count++;
      }
    }
    return count;
  }

  /// Предохранители, проверяемые перед каждым запросом.
  ReplenishStopReason? _stopBeforeRequest({
    required CancellationSignal? cancellation,
    required DateTime now,
    required DateTime startedAt,
    required Duration wallClock,
    required int requests,
    required int requestsLimit,
    required int spent,
    required int tokenLimit,
  }) {
    if (cancellation?.isCancelled ?? false) {
      return ReplenishStopReason.cancelled;
    }
    if (now.difference(startedAt) >= wallClock) {
      return ReplenishStopReason.wallClock;
    }
    if (spent >= tokenLimit) return ReplenishStopReason.tokenBudget;
    if (requests >= requestsLimit) return ReplenishStopReason.maxRequests;
    return null;
  }

  /// Слот заказа: карточка единицы под конкретным углом.
  static String _slot(String unitId, String? angle) =>
      '$unitId\u0000${angle ?? ''}';

  /// Угол ответа модели: `primary` — та же основная карточка, что `null`.
  static String? _normalizeAngle(String? angle) =>
      angle == null || angle == 'primary' ? null : angle;

  /// Известный расход ответа; неизвестные слагаемые — 0, а не выдуманное число.
  static int _knownTokens(TokenUsage usage) {
    final int? total = usage.totalTokens;
    if (total != null) return total;
    final int? prompt = usage.promptTokens;
    final int? completion = usage.completionTokens;
    if (prompt != null && completion != null) return prompt + completion;
    return 0;
  }

  /// Стоимость запроса для бюджета: факт ответа, иначе оценка партии (иначе
  /// бюджет не ограничивал бы провайдера, который не сообщает расход).
  static int _requestCost(TokenUsage usage, AllocationBatch batch) {
    final int known = _knownTokens(usage);
    return known > 0 ? known : batch.totalTokens;
  }

  /// Сумма расхода; неизвестное слагаемое обнуляет сумму полей, но не числа.
  static TokenUsage _addUsage(TokenUsage a, TokenUsage b) {
    int? sum(int? Function(TokenUsage usage) pick) {
      final int? left = pick(a);
      final int? right = pick(b);
      if (left == null && right == null) return null;
      return (left ?? 0) + (right ?? 0);
    }

    return TokenUsage(
      promptTokens: sum((TokenUsage usage) => usage.promptTokens),
      completionTokens: sum((TokenUsage usage) => usage.completionTokens),
      totalTokens: sum((TokenUsage usage) => usage.totalTokens),
    );
  }
}

/// Итог одного прохода вместе с израсходованными предохранителями.
class _PassRun {
  const _PassRun({
    required this.pass,
    required this.stop,
    required this.requests,
    required this.spent,
    required this.usage,
  });

  final ReplenishPass pass;

  /// Причина остановки внутри прохода; `null` — план прохода пройден целиком.
  final ReplenishStopReason? stop;

  /// Запросов операции после прохода (включая предыдущие).
  final int requests;

  /// Израсходовано токенов операции после прохода.
  final int spent;

  /// Расход токенов этого прохода.
  final TokenUsage usage;
}
