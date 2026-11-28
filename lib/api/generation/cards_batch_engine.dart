/// Этап Generation: партии по единицам через [LlmPort] (срез 5, ARCH §2 этап 4).
///
/// Один последовательный проход по партиям `AllocationPlan` (SPEC A8.5 шаг 6:
/// без параллельных запросов). Журнал (`GenerationLedger`) ведётся по партиям:
/// каждый запрос — попытка, ответ — произведённые/отброшенные карточки,
/// принятое пишется в [CardSink] **по ходу** (инвариант ARCH §3.5).
///
/// Обрезка ответа (`finish_reason: length`) не «добирается повтором того же
/// запроса»: остаток долга делится по **единицам** ([splitBatchByUnits]) и
/// добирается отдельным запросом; повторы и добор считаются в журнале
/// ([GenerationBatchLedger.attempts]), отдельного recovery-бюджета нет.
///
/// Контекст «уже принято» — только принятое **текущего** батча
/// ([CardsBatch.accepted]): между партиями он не переносится.
library;

import 'package:cardflow/api/generation/batch_job_recorder.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/card_gate.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';

/// Итог этапа Generation: журнал, принятые карточки и версия промпта.
class CardsBatchRun {
  /// Создаёт итог.
  CardsBatchRun({
    required this.ledger,
    List<GeneratedCard> acceptedCards = const <GeneratedCard>[],
    List<GeneratedCard> blockedCards = const <GeneratedCard>[],
    this.usage = const TokenUsage(),
    required this.promptVersion,
    this.cancelled = false,
    List<Duration> batchDurations = const <Duration>[],
  }) : acceptedCards = List<GeneratedCard>.unmodifiable(acceptedCards),
       blockedCards = List<GeneratedCard>.unmodifiable(blockedCards),
       batchDurations = List<Duration>.unmodifiable(batchDurations);

  /// Пустой итог (ни одного запроса).
  factory CardsBatchRun.empty({required String promptVersion}) => CardsBatchRun(
    ledger: GenerationLedger.empty(),
    promptVersion: promptVersion,
  );

  /// Журнал прогона по партиям (долг, причины, число запросов).
  final GenerationLedger ledger;

  /// Принятые карточки в порядке принятия.
  final List<GeneratedCard> acceptedCards;

  /// Карточки, заблокированные гейтом первого прохода (TASK «Срез 11», п. 2).
  ///
  /// В журнал «принято» не входят; хранятся для «показать отброшенные» и для
  /// учёта попыток на слот в доборе.
  final List<GeneratedCard> blockedCards;

  /// Фактический расход токенов принятых ответов.
  final TokenUsage usage;

  /// Версия промпта, которой получены карточки (`generation_jobs.prompt_version`).
  final String promptVersion;

  /// Прогон отменён: принятое сохранено ([acceptedCards]), остальное не заказано.
  final bool cancelled;

  /// Отметки времени успешных вызовов модели (TASK «Срез 12», п. 6).
  ///
  /// p50/p95 батча считаются из этого списка, а не «на глаз»; повторы и
  /// деление обрыва дают отдельные отметки — это фактические запросы.
  final List<Duration> batchDurations;

  /// Принято карточек.
  int get accepted => acceptedCards.length;

  /// Запрошено карточек (Σ бюджетов партий).
  int get requested => ledger.requested;

  /// Долг: `requested − accepted`.
  int get remaining => ledger.remaining;

  /// true — заказ выполнен полностью и прогон не отменён.
  bool get isComplete => !cancelled && ledger.remaining == 0;

  @override
  String toString() =>
      'CardsBatchRun(принято $accepted/$requested, '
      'запросов ${ledger.attempts}${cancelled ? ', отмена' : ''})';
}

/// Движок этапа Generation.
class CardsBatchEngine {
  /// Создаёт движок.
  CardsBatchEngine({
    required this.port,
    required this.account,
    this.sink,
    this.progress,
    RetryPolicy? retryPolicy,
    Future<void> Function(Duration duration)? delay,
    this.jobRecorder,
    this.jobId,
    this.promptVersion = cardsPromptVersion,
  }) : retryPolicy = retryPolicy ?? RetryPolicy(),
       delay = delay ?? Future<void>.delayed;

  /// Вызов модели на партию.
  final LlmPort port;

  /// Аккаунт провайдера партии.
  final ProviderAccount account;

  /// Запись принятого по ходу прогона (журнал запуска, срез 8).
  final CardSink? sink;

  /// Прогресс: этап и снимок журнала.
  final ProgressSink? progress;

  /// Политика повторов (429 `Retry-After`, 5xx, таймауты).
  final RetryPolicy retryPolicy;

  /// Пауза перед повтором (инжектируется в тестах).
  final Future<void> Function(Duration duration) delay;

  /// Запись версии промпта в задание (`generation_jobs`).
  final BatchJobRecorder? jobRecorder;

  /// id задания, в которое пишется версия промпта.
  final String? jobId;

  /// Версия промпта этапа.
  final String promptVersion;

  /// Выполняет план Allocation по партиям.
  ///
  /// [gate] — гейт карточки (TASK «Срез 11», п. 4): первый проход и добор
  /// спрашивают его, поэтому в принятое и в [CardSink] попадает только карточка
  /// после проверки. `null` — прогон без проверки (совместимость тестов пути
  /// без гейта; production-фасад передаёт гейт всегда).
  Future<CardsBatchRun> run(
    AllocationPlan plan, {
    CardGate? gate,
    CancellationSignal? cancellation,
  }) async {
    final BatchJobRecorder? recorder = jobRecorder;
    final String? id = jobId;
    if (recorder != null && id != null) {
      await recorder.record(id);
    }

    final Map<String, KnowledgeUnit> unitsById = <String, KnowledgeUnit>{
      for (final UnitBudget budget in plan.units) budget.unit.id: budget.unit,
    };
    GenerationLedger ledger = GenerationLedger.fromBudgets(
      plan.batches.map((AllocationBatch batch) => batch.cards.length),
    );
    final List<GeneratedCard> acceptedCards = <GeneratedCard>[];
    final List<GeneratedCard> blockedCards = <GeneratedCard>[];
    final List<Duration> batchDurations = <Duration>[];
    final Map<int, List<AcceptedCard>> acceptedByBatch =
        <int, List<AcceptedCard>>{};
    var usage = const TokenUsage();

    for (final AllocationBatch batch in plan.batches) {
      final List<KnowledgeUnit> batchUnits = <KnowledgeUnit>[];
      final Set<String> seenUnits = <String>{};
      for (final AllocatedCard card in batch.cards) {
        final KnowledgeUnit? unit = unitsById[card.unitId];
        if (unit != null && seenUnits.add(unit.id)) batchUnits.add(unit);
      }
      final List<CardsBatch> queue = <CardsBatch>[
        CardsBatch(index: batch.index, units: batchUnits, cards: batch.cards),
      ];

      while (queue.isNotEmpty) {
        if (cancellation?.isCancelled ?? false) {
          ledger = ledger.markCause(batch.index, ShortfallKind.cancelled);
          return _finish(
            ledger,
            acceptedCards,
            usage,
            blockedCards: blockedCards,
            cancelled: true,
            batchDurations: batchDurations,
          );
        }
        final CardsBatch slice = queue.removeAt(0);
        ledger = ledger.attempt(slice.index);
        _report(ledger);

        GenerationResult? result;
        var attempt = 1;
        var cancelledNow = false;
        // Контекст «уже принято» этого батча берётся на момент запроса: партия
        // в очереди могла быть создана до того, как ответила предыдущая часть.
        final List<AcceptedCard> context = acceptedByBatch.putIfAbsent(
          batch.index,
          () => <AcceptedCard>[],
        );
        final CardsBatch request = slice.withAcceptedContext(context);
        while (true) {
          try {
            final Stopwatch callWatch = Stopwatch()..start();
            try {
              result = await port.generate(
                request,
                account: account,
                maxOutputTokens: batch.outputTokens,
              );
            } finally {
              callWatch.stop();
              batchDurations.add(callWatch.elapsed);
            }
            break;
          } on GenerationException catch (error) {
            if (error.code == GenerationErrorCode.cancelled ||
                (cancellation?.isCancelled ?? false)) {
              cancelledNow = true;
              break;
            }
            final RetryDecision decision = retryPolicy.decide(
              attempt: attempt,
              statusCode: statusFor(error.code),
              isTimeout: error.code == GenerationErrorCode.timeout,
              isConnectionError: error.code == GenerationErrorCode.network,
              retryAfter: error.retryAfter,
            );
            if (!decision.shouldRetry) {
              ledger = ledger.markCause(
                slice.index,
                ShortfallKind.providerError,
              );
              break;
            }
            await delay(decision.delay);
            attempt++;
            // Повтор — отдельная попытка партии: журнал, а не recovery-бюджет.
            ledger = ledger.attempt(slice.index);
            _report(ledger);
          }
        }
        if (cancelledNow) {
          ledger = ledger.markCause(slice.index, ShortfallKind.cancelled);
          return _finish(
            ledger,
            acceptedCards,
            usage,
            blockedCards: blockedCards,
            cancelled: true,
            batchDurations: batchDurations,
          );
        }
        if (result == null) {
          break; // партия не сгенерирована — причина в журнале
        }

        ledger = ledger.record(
          slice.index,
          generated: result.cards.length + result.rejectedCards,
          invalid: result.rejectedCards,
        );
        usage = _addUsage(usage, result.usage);

        // Гейт — до принятия: журнал увеличивает accepted только после
        // проверки (TASK «Срез 11», п. 2). Заблокированная карточка не идёт ни
        // в принятое, ни в контекст партии, ни в [CardSink].
        final List<GeneratedCard> acceptedNow = <GeneratedCard>[];
        var blockedNow = 0;
        for (final GeneratedCard card in result.cards) {
          final String? unitId = card.unitId;
          if (unitId == null || slice.unit(unitId) == null) continue;
          final CardGateResult verdict =
              gate?.evaluate(card) ??
              CardGateResult(verdict: CardGateVerdict.accepted);
          if (verdict.verdict == CardGateVerdict.blocked) {
            blockedCards.add(card);
            blockedNow++;
            continue;
          }
          acceptedNow.add(
            verdict.verdict == CardGateVerdict.warning
                ? card.copyWith(gateReasons: verdict.reasons)
                : card,
          );
        }
        if (blockedNow > 0) {
          ledger = ledger.record(slice.index, invalid: blockedNow);
        }
        for (final GeneratedCard card in acceptedNow) {
          acceptedCards.add(card);
          final KnowledgeUnit unit = unitsById[card.unitId!]!;
          context.add(
            AcceptedCard(front: card.front, statement: unit.statement),
          );
          final CardSink? sink = this.sink;
          if (sink != null) {
            await sink.save(card, batchIndex: batch.index);
          }
        }
        _report(ledger);

        final List<AllocatedCard> debt = _debtOf(slice, acceptedNow);
        if (!result.truncated) {
          if (debt.isNotEmpty) {
            ledger = ledger.markCause(
              batch.index,
              blockedNow > 0
                  ? ShortfallKind.validationRejects
                  : ShortfallKind.exhaustedMaterial,
            );
          }
          continue;
        }
        if (debt.isEmpty) continue;
        final CardsBatch rest = slice.slice(debt, accepted: context);
        if (rest.unitIds.length >= 2) {
          queue.insertAll(0, splitBatchByUnits(rest));
          continue;
        }
        // Единица неделима: делить по единицам больше не на что. Ровно одна
        // повторная попытка на остаток; второй обрез — исчерпание с причиной
        // truncated (отдельного recovery-бюджета нет, TASK п. 3).
        if (slice.topUp) {
          ledger = ledger.markCause(batch.index, ShortfallKind.truncated);
          continue;
        }
        queue.insert(0, rest.slice(rest.cards, accepted: context, topUp: true));
      }
    }

    _report(ledger);
    return _finish(
      ledger,
      acceptedCards,
      usage,
      blockedCards: blockedCards,
      cancelled: false,
      batchDurations: batchDurations,
    );
  }

  /// HTTP-статус для [RetryPolicy] по коду ошибки генерации.
  static int? statusFor(GenerationErrorCode code) => switch (code) {
    GenerationErrorCode.rateLimited => 429,
    GenerationErrorCode.serverUnavailable => 503,
    GenerationErrorCode.payloadTooLarge => 413,
    GenerationErrorCode.badRequest => 400,
    GenerationErrorCode.invalidApiKey => 401,
    GenerationErrorCode.insufficientBalance => 402,
    _ => null,
  };

  CardsBatchRun _finish(
    GenerationLedger ledger,
    List<GeneratedCard> acceptedCards,
    TokenUsage usage, {
    required List<GeneratedCard> blockedCards,
    required bool cancelled,
    List<Duration> batchDurations = const <Duration>[],
  }) => CardsBatchRun(
    ledger: ledger,
    acceptedCards: acceptedCards,
    blockedCards: blockedCards,
    usage: usage,
    promptVersion: promptVersion,
    cancelled: cancelled,
    batchDurations: batchDurations,
  );

  void _report(GenerationLedger ledger) {
    progress?.report(GenerationStage.generating, ledger);
  }

  /// Долг партии: карточки плана, которым не нашлось принятой пары
  /// (`unit_id` + `angle`).
  static List<AllocatedCard> _debtOf(
    CardsBatch slice,
    List<GeneratedCard> accepted,
  ) {
    final Set<String> satisfied = <String>{
      for (final GeneratedCard card in accepted)
        _slot(card.unitId!, card.angle == 'primary' ? null : card.angle),
    };
    return <AllocatedCard>[
      for (final AllocatedCard planned in slice.cards)
        if (!satisfied.contains(_slot(planned.unitId, planned.angle?.wireName)))
          planned,
    ];
  }

  static String _slot(String unitId, String? angle) =>
      '$unitId\u0000${angle ?? ''}';

  /// Сумма фактического расхода; неизвестное слагаемое — `null`, а не 0.
  ///
  /// Накопитель стартует с `const TokenUsage()` (все поля `null`) — это
  /// «расхода ещё нет», а не «неизвестный расход»: иначе первое успешное
  /// сложение обнуляло бы всю сумму, и `CardsBatchRun.usage` всегда был бы
  /// `null` (находка среза 7: отчёт по этапам без расхода бесполезен).
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
