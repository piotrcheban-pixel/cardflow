import 'generation_job.dart';
import 'generation_ledger.dart';

/// Итог прогона генерации (ARCH §2, этап 9 Completion).
///
/// Вердикт считается **только по журналу** (ARCH §3.2): «ложный успех» запрещён,
/// `done` возможен лишь при `принято ≥ заказано`; любой недобор — `partial` с
/// числом и машинными причинами ([ShortfallKind]).
enum CompletionOutcome {
  /// Заказ закрыт (или авто-режим без долга).
  done,

  /// Заказ не закрыт: часть карточек потеряна/не создана.
  partial,

  /// Прогон остановился ошибкой провайдера и не дал карточек.
  failed,

  /// Пользователь отменил прогон до первой принятой карточки.
  cancelled,
}

/// Вердикт завершения прогона: единственное место, где решается исход.
class CompletionVerdict {
  /// Создаёт вердикт (обычно через [fromLedger]/[auto]).
  const CompletionVerdict({
    required this.outcome,
    required this.requested,
    required this.accepted,
    this.reasons = const <ShortfallKind>[],
    this.requestsWithoutCards = 0,
    this.materialCapacity = 0,
  }) : assert(requestsWithoutCards >= 0, 'Число запросов без карточек ≥ 0'),
       assert(materialCapacity >= 0, 'Ёмкость материала ≥ 0');

  /// Вердикт по журналу прогона (ARCH §3.2, BACKLOG S9).
  ///
  /// [cancelled] и [failed] — исходы, которые журнал не выводит из чисел:
  /// отмена сохраняет принятое (срез 7), поэтому `cancelled` возможен только
  /// без принятых карточек, иначе это честный `partial`.
  factory CompletionVerdict.fromLedger(
    GenerationLedger ledger, {
    bool cancelled = false,
    bool failed = false,
    int materialCapacity = 0,
  }) {
    final int accepted = ledger.accepted;
    final int requested = ledger.requested;
    final List<ShortfallKind> reasons = <ShortfallKind>[];

    if (cancelled) {
      reasons.add(ShortfallKind.cancelled);
      final ShortfallKind? extra = ledger.shortfall;
      if (extra != null && extra != ShortfallKind.cancelled) reasons.add(extra);
      return CompletionVerdict(
        outcome: accepted > 0
            ? CompletionOutcome.partial
            : CompletionOutcome.cancelled,
        requested: requested,
        accepted: accepted,
        reasons: List<ShortfallKind>.unmodifiable(reasons),
        materialCapacity: materialCapacity,
      );
    }

    if (failed) {
      reasons.add(ShortfallKind.providerError);
      return CompletionVerdict(
        outcome: accepted > 0
            ? CompletionOutcome.partial
            : CompletionOutcome.failed,
        requested: requested,
        accepted: accepted,
        reasons: List<ShortfallKind>.unmodifiable(reasons),
        materialCapacity: materialCapacity,
      );
    }

    // Заказ задан: успех — только закрытый заказ.
    if (requested > 0 && accepted >= requested) {
      return CompletionVerdict(
        outcome: CompletionOutcome.done,
        requested: requested,
        accepted: accepted,
        materialCapacity: materialCapacity,
      );
    }
    // Авто-режим (заказ не задан): долга нет, если журнал его не объявил, но
    // «долг» без единой карточки успехом не становится (false success).
    if (requested == 0 && accepted > 0) {
      return CompletionVerdict(
        outcome: CompletionOutcome.done,
        requested: requested,
        accepted: accepted,
        materialCapacity: materialCapacity,
      );
    }

    final ShortfallKind? kind = ledger.shortfall;
    if (kind != null) reasons.add(kind);
    final int requestsWithoutCards = ledger.generated == 0 && ledger.attempts > 0
        ? ledger.attempts
        : 0;
    return CompletionVerdict(
      outcome: CompletionOutcome.partial,
      requested: requested,
      accepted: accepted,
      reasons: List<ShortfallKind>.unmodifiable(reasons),
      requestsWithoutCards: requestsWithoutCards,
      materialCapacity: materialCapacity,
    );
  }

  /// Вердикт для авто-режима: заказ не задан, долг — упавшие запросы.
  ///
  /// `done` требует отсутствия долга **и** хотя бы одной карточки: пустой ответ
  /// — не успех, но и не ошибка провайдера (`generationNoCardsFound`).
  factory CompletionVerdict.auto({
    required int accepted,
    required int requests,
    required int failedRequests,
    bool cancelled = false,
    int materialCapacity = 0,
  }) {
    final List<ShortfallKind> reasons = <ShortfallKind>[];
    if (cancelled) {
      reasons.add(ShortfallKind.cancelled);
      return CompletionVerdict(
        outcome: accepted > 0
            ? CompletionOutcome.partial
            : CompletionOutcome.cancelled,
        requested: 0,
        accepted: accepted,
        reasons: List<ShortfallKind>.unmodifiable(reasons),
        materialCapacity: materialCapacity,
      );
    }
    if (failedRequests > 0) reasons.add(ShortfallKind.providerError);
    if (accepted > 0 && failedRequests == 0) {
      return CompletionVerdict(
        outcome: CompletionOutcome.done,
        requested: 0,
        accepted: accepted,
        materialCapacity: materialCapacity,
      );
    }
    return CompletionVerdict(
      outcome: CompletionOutcome.partial,
      requested: 0,
      accepted: accepted,
      reasons: List<ShortfallKind>.unmodifiable(reasons),
      requestsWithoutCards: accepted == 0 ? requests : 0,
      materialCapacity: materialCapacity,
    );
  }

  /// Исход прогона.
  final CompletionOutcome outcome;

  /// Запрошено карточек (0 — заказ не задан, авто-режим).
  final int requested;

  /// Принято карточек.
  final int accepted;

  /// Машинные причины недобора в порядке журнала (без текста для UI).
  final List<ShortfallKind> reasons;

  /// Сколько запросов не дало ни карточки (пустой ответ модели).
  final int requestsWithoutCards;

  /// Ёмкость материала в карточках (0 — неизвестна/не ограничена).
  final int materialCapacity;

  /// true — заказ закрыт.
  bool get isDone => outcome == CompletionOutcome.done;

  /// Недобор в карточках (`max(0, requested − accepted)`).
  int get shortfall => requested > accepted ? requested - accepted : 0;

  /// true — цель достигнута (в авто-режиме совпадает с [isDone]).
  bool get targetReached =>
      requested > 0 ? accepted >= requested : isDone;

  /// Статус задания `generation_jobs` (SPEC A5).
  GenerationJobStatus get jobStatus => switch (outcome) {
    CompletionOutcome.done => GenerationJobStatus.done,
    CompletionOutcome.partial => GenerationJobStatus.partial,
    CompletionOutcome.failed => GenerationJobStatus.error,
    CompletionOutcome.cancelled => GenerationJobStatus.cancelled,
  };
}
