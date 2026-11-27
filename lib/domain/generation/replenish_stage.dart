/// Replenish — этап добора долга (TASK «Срез 7», ARCH §2 этап 7, ADR-050).
///
/// ЗАГЛУШКА красной фазы: типы объявлены, правила добора ещё не реализованы.
library;

import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';

/// Предел запросов операции: `f(requested)` (заглушка).
int maxRequestsForRequested(int requested) => 0;

/// Бюджет токенов операции по оценкам плана (заглушка).
int tokenBudgetForPlan(
  AllocationPlan plan, {
  int passes = ReplenishPolicy.defaultMaxPasses,
}) => 0;

/// Причина остановки добора.
enum ReplenishStopReason {
  complete('complete'),
  exhaustedMaterial('exhausted_material'),
  maxPasses('max_passes'),
  maxRequests('max_requests'),
  tokenBudget('token_budget'),
  wallClock('wall_clock'),
  providerError('provider_error'),
  cancelled('cancelled'),
  noUnitPlan('no_unit_plan');

  const ReplenishStopReason(this.wireName);

  final String wireName;

  /// true — остановил предохранитель операции, а не материал/сбой.
  bool get isGuard => switch (this) {
    ReplenishStopReason.maxPasses ||
    ReplenishStopReason.maxRequests ||
    ReplenishStopReason.tokenBudget ||
    ReplenishStopReason.wallClock => true,
    _ => false,
  };

  /// Разбирает причину из строки журнала.
  static ReplenishStopReason fromWire(String value) {
    for (final ReplenishStopReason reason in values) {
      if (reason.wireName == value) return reason;
    }
    throw FormatException('Неизвестная причина остановки добора: $value');
  }
}

/// Предохранители операции добора.
class ReplenishPolicy {
  /// Создаёт политику.
  const ReplenishPolicy({
    this.maxPasses = defaultMaxPasses,
    this.maxRequests,
    this.tokenBudget,
    this.wallClock = defaultWallClock,
  });

  /// Число проходов добора по умолчанию (TASK: `maxPasses = 3`).
  static const int defaultMaxPasses = 3;

  /// Предел времени операции по умолчанию.
  static const Duration defaultWallClock = Duration(minutes: 10);

  final int maxPasses;
  final int? maxRequests;
  final int? tokenBudget;
  final Duration wallClock;

  /// Предел запросов операции.
  int requestsLimit(int requested) => maxRequests ?? 0;

  /// Предел токенов операции.
  int tokenLimit(AllocationPlan plan) => tokenBudget ?? 0;
}

/// Один проход добора.
class ReplenishPass {
  /// Создаёт запись прохода.
  ReplenishPass({
    required this.index,
    required this.plan,
    required this.ledger,
    List<GeneratedCard> accepted = const <GeneratedCard>[],
    this.usage = const TokenUsage(),
    this.filledSlots = 0,
    this.surplus = 0,
  }) : accepted = List<GeneratedCard>.unmodifiable(accepted);

  final int index;
  final AllocationPlan plan;
  final GenerationLedger ledger;
  final List<GeneratedCard> accepted;
  final TokenUsage usage;
  final int filledSlots;
  final int surplus;

  int get requested => plan.requested;
  int get acceptedCount => accepted.length;
  int get requests => ledger.attempts;
  List<String> get unitIds => const <String>[];
}

/// Итог этапа добора.
class ReplenishOutcome {
  /// Создаёт итог.
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

  final GenerationStage stage;
  final ReplenishStopReason reason;
  final int requested;
  final List<GeneratedCard> acceptedCards;
  final List<ReplenishPass> passes;
  final int requests;
  final int invalid;
  final int duplicates;
  final TokenUsage usage;
  final Duration duration;
  final int unfilledSlots;

  int get accepted => acceptedCards.length;
  int get remaining => 0;
  bool get isComplete => false;
  int? get materialCapacity => null;
}

/// Этап добора.
class ReplenishStage {
  /// Создаёт этап.
  ReplenishStage({
    required this.port,
    required this.account,
    required this.clock,
    this.policy = const ReplenishPolicy(),
    this.estimator = const TokenEstimator(),
    this.outputTokensPerCard = kDefaultOutputTokensPerCard,
  });

  final LlmPort port;
  final ProviderAccount account;
  final Clock clock;
  final ReplenishPolicy policy;
  final TokenEstimator estimator;
  final int outputTokensPerCard;

  /// Запускает добор долга (заглушка).
  Future<ReplenishOutcome> run({
    required AllocationPlan plan,
    required GenerationLedger ledger,
    List<GeneratedCard> acceptedCards = const <GeneratedCard>[],
    TokenUsage initialUsage = const TokenUsage(),
    DateTime? startedAt,
    CancellationSignal? cancellation,
  }) async => ReplenishOutcome(
    stage: GenerationStage.partial,
    reason: ReplenishStopReason.complete,
    requested: plan.requested,
    requests: ledger.attempts,
    unfilledSlots: plan.cards.length,
  );
}
