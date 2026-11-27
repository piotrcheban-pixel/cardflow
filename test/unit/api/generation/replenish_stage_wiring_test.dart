import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// Стык среза 5 и среза 7 на production-проводке: `CardsBatchEngine` (этап
/// Generation) отдаёт журнал и принятое, `ReplenishStage` добирает долг, а
/// `GenerationReport` показывает заказ/принятое. Сбой третьего батча в движке —
/// не «успех» и не тупик: добор закрывает заказ.
void main() {
  const ModelProfile profile = ModelProfile(
    id: 'deepseek-chat',
    provider: 'deepseek',
    contextWindow: 128000,
    maxOutputTokens: 8192,
    supportsJsonSchema: true,
    supportsVision: false,
    concurrency: 1,
  );

  const ProviderAccount account = ProviderAccount(
    id: 'account-1',
    label: 'DeepSeek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.test/v1',
    modelId: 'deepseek-chat',
  );

  test('сбой третьего батча в движке → добор закрывает заказ', () async {
    final AllocationPlan plan = _manualPlan(profile);

    // Первый проход: третий батч падает 400 (без повторов).
    final _FakeLlmPort failingPort = _FakeLlmPort(
      onGenerate: (CardsBatch batch, ProviderAccount account) {
        if (batch.index == 2) {
          throw const GenerationException(GenerationErrorCode.badRequest);
        }
        return _success(account, batch);
      },
    );
    final CardsBatchEngine engine = CardsBatchEngine(
      port: failingPort,
      account: account,
    );

    final CardsBatchRun run = await engine.run(plan);

    expect(run.accepted, 4, reason: 'два батча из трёх');
    expect(run.remaining, 2);
    expect(run.ledger.batch(2)!.cause, ShortfallKind.providerError);
    expect(
      run.usage.totalTokens,
      300,
      reason: 'расход успешных партий суммируется (150 + 150)',
    );

    // Второй проход: только по единице с долгом.
    final _FakeLlmPort replenishPort = _FakeLlmPort();
    final ReplenishStage stage = ReplenishStage(
      port: replenishPort,
      account: account,
      clock: _FixedClock(DateTime.utc(2026, 11, 27, 12)),
    );

    final ReplenishOutcome outcome = await stage.run(
      plan: plan,
      ledger: run.ledger,
      acceptedCards: run.acceptedCards,
      initialUsage: run.usage,
    );

    expect(outcome.accepted, 6);
    expect(outcome.reason, ReplenishStopReason.complete);
    expect(outcome.stage, GenerationStage.ready);
    expect(replenishPort.calls.single.unitIds, <String>['U2']);
    expect(replenishPort.calls.single.cards.length, 2);

    final GenerationReport report = GenerationReport.fromReplenish(
      plan: plan,
      outcome: outcome,
      initialUsage: run.usage,
      promptVersions: <String, String>{
        'generating': run.promptVersion,
        'replenishing': 'gen-cards-v3',
      },
    );

    expect(report.requested, 6);
    expect(report.accepted, 6);
    expect(report.isComplete, isTrue);
    expect(report.reasons, isEmpty);
    expect(report.coveredUnits, 3);
    expect(report.uncoveredUnits, 0);
    expect(report.tokensByStage[GenerationStage.generating]!.totalTokens, 300);
    expect(
      report.tokensByStage[GenerationStage.replenishing]!.totalTokens,
      150,
    );
    expect(report.promptVersions['generating'], 'gen-cards-v3');
  });
}

class _FakeLlmPort implements LlmPort {
  _FakeLlmPort({this.onGenerate});

  final GenerationResult Function(CardsBatch batch, ProviderAccount account)?
  onGenerate;
  final List<CardsBatch> calls = <CardsBatch>[];

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
    calls.add(batch);
    final GenerationResult Function(CardsBatch, ProviderAccount)? handler =
        onGenerate;
    if (handler != null) return handler(batch, account);
    return _success(account, batch);
  }
}

/// Ручной план: три батча по два единичных утверждения (U0, U1, U2).
AllocationPlan _manualPlan(ModelProfile profile) {
  final List<UnitBudget> units = <UnitBudget>[];
  final List<AllocatedCard> cards = <AllocatedCard>[];
  final List<AllocationBatch> batches = <AllocationBatch>[];
  for (var index = 0; index < 3; index++) {
    final String id = 'U$index';
    final KnowledgeUnit unit = _unit(id);
    final List<AllocatedCard> batchCards = <AllocatedCard>[
      AllocatedCard(unitId: id),
      AllocatedCard(unitId: id, angle: AllocationAngle.reverse),
    ];
    units.add(UnitBudget(unit: unit, cards: batchCards.length));
    cards.addAll(batchCards);
    batches.add(
      AllocationBatch(
        index: index,
        profile: profile,
        cards: batchCards,
        inputTokens: 900,
        outputTokens: batchCards.length * kDefaultOutputTokensPerCard,
      ),
    );
  }
  return AllocationPlan(
    requested: cards.length,
    profile: profile,
    units: units,
    cards: cards,
    batches: batches,
  );
}

GenerationResult _success(ProviderAccount account, CardsBatch batch) =>
    GenerationResult(
      provider: account.protocol.adapterProvider,
      model: account.modelId,
      promptVersion: 'gen-cards-v3',
      cards: <GeneratedCard>[
        for (final AllocatedCard planned in batch.cards)
          _cardFor(batch, planned),
      ],
      usage: const TokenUsage(
        promptTokens: 100,
        completionTokens: 50,
        totalTokens: 150,
      ),
    );

GeneratedCard _cardFor(CardsBatch batch, AllocatedCard planned) {
  final KnowledgeUnit unit = batch.unit(planned.unitId)!;
  return GeneratedCard(
    front: 'Вопрос ${unit.id}/${planned.angle?.wireName ?? 'primary'}',
    back: unit.statement,
    cardType: CardType.basic,
    unitId: unit.id,
    angle: planned.angle?.wireName,
    quoteRef: unit.anchors.first.quote,
  );
}

KnowledgeUnit _unit(String id) => KnowledgeUnit(
  id: id,
  sectionId: 'doc:материал.md#0',
  topic: 'тема $id',
  kind: KnowledgeUnitKind.definition,
  statement: 'Утверждение единицы $id о моменте силы.',
  anchors: <KnowledgeAnchor>[
    KnowledgeAnchor(
      blockId: 'doc:материал.md#0#0',
      quote: 'Цитата материала $id.',
    ),
  ],
);

class _FixedClock implements Clock {
  _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
