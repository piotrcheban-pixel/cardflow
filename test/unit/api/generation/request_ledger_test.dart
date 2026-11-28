import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/batch_job_recorder.dart';
import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// DoD среза 5 (`docs/generation/BACKLOG.md` S4, `TASK.txt` «Срез 5»):
/// Generation выполняется партиями по единицам через фейковый `LlmPort` —
/// без сети и ключей.
///
/// Проверяется: 20/40/80 карточек доводятся до заказа; обрезанный ответ
/// делится **по единицам**, а не пополам, и остаток добирается; 429 повторяется
/// через `Retry-After`; 400/401 не повторяются; отмена посреди батча сохраняет
/// принятое; версия промпта пишется в задание; повторы считаются в журнале.
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

  group('журнал запросов (GenerationLedger.attempts)', () {
    test('успешный запрос тоже попытка, события не сбрасывают счётчик', () {
      final GenerationLedger ledger = GenerationLedger.fromBudgets(<int>[3])
          .attempt(0)
          .record(0, generated: 2, invalid: 1)
          .attempt(0);
      expect(ledger.attempts, 2);
      expect(ledger.generated, 2);
      expect(ledger.invalid, 1);
      expect(ledger.accepted, 1);
      expect(ledger.batch(0)!.attempts, 2);
    });

    test('попытка не меняет бюджеты и причину партии', () {
      final GenerationLedger ledger = GenerationLedger.fromBudgets(<int>[2, 4])
          .markCause(1, ShortfallKind.truncated);

      final GenerationLedger after = ledger.attempt(1);

      expect(after.batch(1)!.cause, ShortfallKind.truncated);
      expect(after.requested, 6);
      expect(after.attempts, 1);
      expect(after.batch(0)!.attempts, 0);
    });

    test('нулевое или отрицательное приращение — ошибка программиста', () {
      final GenerationBatchLedger batch = const GenerationBatchLedger.budget(
        batchIndex: 0,
        requested: 2,
      );
      expect(() => batch.attempt(0), throwsArgumentError);
      expect(() => batch.attempt(-1), throwsArgumentError);
    });
  });

  group('деление партии по единицам (не пополам вслепую)', () {
    test(
      'две единицы: первая часть — целые единицы, карточки за единицами',
      () {
        final CardsBatch batch = _batch(
          units: <KnowledgeUnit>[_unit('A'), _unit('B')],
          cards: const <AllocatedCard>[
            AllocatedCard(unitId: 'A'),
            AllocatedCard(unitId: 'A', angle: AllocationAngle.cloze),
            AllocatedCard(unitId: 'B', angle: AllocationAngle.reverse),
          ],
        );

        final List<CardsBatch> parts = splitBatchByUnits(batch);

        expect(parts.length, 2);
        expect(parts[0].unitIds, <String>['A']);
        expect(parts[0].cards.length, 2);
        expect(parts[1].unitIds, <String>['B']);
        expect(parts[1].cards.length, 1);
        expect(parts[0].cards[1].angle, AllocationAngle.cloze);
      },
    );

    test('одна единица не делится: партия возвращается как есть', () {
      final CardsBatch batch = _batch(
        units: <KnowledgeUnit>[_unit('A')],
        cards: const <AllocatedCard>[
          AllocatedCard(unitId: 'A'),
          AllocatedCard(unitId: 'A', angle: AllocationAngle.application),
        ],
      );

      final List<CardsBatch> parts = splitBatchByUnits(batch);

      expect(parts.length, 1);
      expect(identical(parts.single, batch), isTrue);
    });
  });

  group('Generation: заказ 20/40/80 карточек', () {
    for (final int requested in <int>[20, 40, 80]) {
      test('$requested карточек принимаются полностью, долга нет', () async {
        final AllocationPlan plan = _plannedOrder(requested, profile);
        final _FakeLlmPort port = _FakeLlmPort();
        final _RecordingSink sink = _RecordingSink();
        final CardsBatchEngine engine = _engine(port, account, sink: sink);

        final CardsBatchRun run = await engine.run(plan);

        expect(
          run.accepted,
          requested,
          reason: 'принято должно быть ровно $requested',
        );
        expect(run.requested, requested);
        expect(run.remaining, 0);
        expect(run.isComplete, isTrue);
        expect(run.ledger.shortfall, isNull);
        expect(run.ledger.attempts, plan.batches.length);
        expect(sink.saved.length, requested);
        expect(port.calls.length, plan.batches.length);
        for (final GeneratedCard card in run.acceptedCards) {
          expect(card.unitId, isNotNull);
          expect(card.quoteRef, isNotNull);
          expect(card.angle, anyOf(isNull, 'reverse', 'cloze', 'application'));
        }
        for (final CardsBatch batch in port.calls) {
          final int budget = batch.budget;
          expect(budget, greaterThan(0));
        }
      });
    }

    test('каждая партия несёт только свои единицы и свой бюджет', () async {
      final AllocationPlan plan = _plannedOrder(40, profile);
      final _FakeLlmPort port = _FakeLlmPort();

      await _engine(port, account).run(plan);

      final Set<String> plannedUnits = <String>{
        for (final AllocatedCard card in plan.cards) card.unitId,
      };
      for (final CardsBatch batch in port.calls) {
        expect(batch.unitIds, isNotEmpty);
        for (final String unitId in batch.unitIds) {
          expect(plannedUnits, contains(unitId));
        }
        expect(batch.budget, batch.cards.length);
      }
      expect(
        port.calls.fold<int>(0, (int sum, CardsBatch b) => sum + b.budget),
        plan.cards.length,
      );
    });
  });

  group('Generation: обрезка ответа', () {
    test('truncated → деление по единицам → добор остатка', () async {
      final KnowledgeUnit unitA = _unit('A');
      final KnowledgeUnit unitB = _unit('B');
      final AllocationPlan plan = _manualPlan(
        profile: profile,
        units: <KnowledgeUnit>[unitA, unitB],
        cards: const <AllocatedCard>[
          AllocatedCard(unitId: 'A'),
          AllocatedCard(unitId: 'A', angle: AllocationAngle.cloze),
          AllocatedCard(unitId: 'B', angle: AllocationAngle.reverse),
        ],
      );
      late final _FakeLlmPort port;
      port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) {
          // Первый ответ «упёрся в max_tokens»: успела одна карточка из трёх.
          if (port.calls.length == 1) {
            return _result(
              account,
              batch,
              cards: <GeneratedCard>[_card(batch, batch.cards.first)],
              truncated: true,
            );
          }
          return _success(account, batch);
        },
      );
      final _RecordingSink sink = _RecordingSink();

      final CardsBatchRun run = await _engine(
        port,
        account,
        sink: sink,
      ).run(plan);

      expect(run.accepted, 3);
      expect(run.remaining, 0);
      expect(
        run.ledger.attempts,
        3,
        reason: 'первый запрос + две части по единицам',
      );
      expect(port.calls.length, 3);
      expect(port.calls[0].cards.length, 3);
      // Вторая часть — остаток целой единицы A (её cloze-карточка), а не
      // «половина карточек»: деление идёт по границе единиц.
      expect(port.calls[1].unitIds, <String>['A']);
      expect(port.calls[1].cards.length, 1);
      expect(port.calls[1].cards.single.angle, AllocationAngle.cloze);
      expect(port.calls[2].unitIds, <String>['B']);
      expect(port.calls[2].cards.length, 1);
      // Контекст «уже принято» — только текущего батча: front + statement.
      expect(port.calls[2].accepted.length, 2);
      expect(port.calls[2].accepted.first.front, isNotEmpty);
      expect(port.calls[2].accepted.first.statement, unitA.statement);
      expect(sink.saved.length, 3);
    });

    test(
      'обрезка одной единицы: одна повторная попытка, затем причина',
      () async {
        final KnowledgeUnit unitA = _unit('A');
        final AllocationPlan plan = _manualPlan(
          profile: profile,
          units: <KnowledgeUnit>[unitA],
          cards: const <AllocatedCard>[
            AllocatedCard(unitId: 'A'),
            AllocatedCard(unitId: 'A', angle: AllocationAngle.cloze),
          ],
        );
        late final _FakeLlmPort port;
        port = _FakeLlmPort(
          // Единица неделима: делиться не по чему; добор тоже обрезан и не дал
          // ни одной полной карточки.
          onGenerate: (CardsBatch batch) {
            if (port.calls.length == 1) {
              return _result(
                account,
                batch,
                cards: <GeneratedCard>[_card(batch, batch.cards.first)],
                truncated: true,
              );
            }
            return _result(
              account,
              batch,
              cards: const <GeneratedCard>[],
              truncated: true,
            );
          },
        );

        final CardsBatchRun run = await _engine(port, account).run(plan);

        expect(run.accepted, 1);
        expect(run.remaining, 1);
        expect(
          run.ledger.attempts,
          2,
          reason: 'первый запрос + ровно один добор',
        );
        expect(run.ledger.shortfall, ShortfallKind.truncated);
        expect(port.calls[1].topUp, isTrue);
      },
    );
  });

  group('Generation: повторы HTTP', () {
    test('429 → пауза Retry-After, затем успех (повтор в журнале)', () async {
      final AllocationPlan plan = _plannedOrder(4, profile);
      late final _FakeLlmPort port;
      port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) {
          if (port.calls.length == 1) {
            throw const GenerationException(
              GenerationErrorCode.rateLimited,
              retryAfter: Duration(seconds: 7),
            );
          }
          return _success(account, batch);
        },
      );
      final List<Duration> pauses = <Duration>[];

      final CardsBatchRun run = await _engine(
        port,
        account,
        delay: (Duration duration) async => pauses.add(duration),
      ).run(plan);

      expect(pauses, <Duration>[const Duration(seconds: 7)]);
      expect(run.accepted, 4);
      expect(run.remaining, 0);
      expect(run.ledger.attempts, plan.batches.length + 1);
    });

    for (final GenerationErrorCode code in <GenerationErrorCode>[
      GenerationErrorCode.badRequest,
      GenerationErrorCode.invalidApiKey,
    ]) {
      test('${code.name} → без повторов, партия помечена причиной', () async {
        final AllocationPlan plan = _plannedOrder(2, profile);
        final _FakeLlmPort port = _FakeLlmPort(
          onGenerate: (CardsBatch batch) => throw GenerationException(code),
        );
        final List<Duration> pauses = <Duration>[];

        final CardsBatchRun run = await _engine(
          port,
          account,
          delay: (Duration duration) async => pauses.add(duration),
        ).run(plan);

        expect(pauses, isEmpty, reason: '400/401 не повторяются');
        expect(run.ledger.attempts, 1);
        expect(run.remaining, plan.requested);
        expect(run.ledger.shortfall, ShortfallKind.providerError);
        expect(port.calls.length, 1);
      });
    }
  });

  group('Generation: отмена и задание', () {
    test('отмена посреди батча сохраняет принятое', () async {
      final _FakeCancellation cancellation = _FakeCancellation();
      final AllocationPlan plan = _manualPlan(
        profile: profile,
        units: <KnowledgeUnit>[_unit('A'), _unit('B')],
        cards: const <AllocatedCard>[
          AllocatedCard(unitId: 'A'),
          AllocatedCard(unitId: 'A', angle: AllocationAngle.cloze),
          AllocatedCard(unitId: 'B'),
        ],
      );
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) {
          // Модель успела одну карточку и упёрлась в лимит; пользователь
          // нажал «Отмена», пока шла партия.
          cancellation.cancel();
          return _result(
            account,
            batch,
            cards: <GeneratedCard>[_card(batch, batch.cards.first)],
            truncated: true,
          );
        },
      );
      final _RecordingSink sink = _RecordingSink();

      final CardsBatchRun run = await _engine(
        port,
        account,
        sink: sink,
      ).run(plan, cancellation: cancellation);

      expect(run.cancelled, isTrue);
      expect(run.accepted, 1, reason: 'принятое до отмены сохранено');
      expect(run.acceptedCards.single.unitId, 'A');
      expect(sink.saved.length, 1);
      expect(run.ledger.shortfall, ShortfallKind.cancelled);
      expect(port.calls.length, 1, reason: 'после отмены запросов нет');
    });

    test('версия промпта пишется в задание generation_jobs', () async {
      final _FakeJobRepository jobs = _FakeJobRepository();
      jobs.jobs['job-1'] = GenerationJob(
        id: 'job-1',
        status: GenerationJobStatus.running,
        createdAt: DateTime.utc(2026, 11, 27),
        provider: 'openai-compatible',
        model: 'deepseek-chat',
      );

      final CardsBatchRun run = await _engine(
        _FakeLlmPort(),
        account,
        jobRecorder: BatchJobRecorder(repository: jobs),
        jobId: 'job-1',
      ).run(_plannedOrder(3, profile));

      expect(run.promptVersion, cardsPromptVersion);
      expect(cardsPromptVersion, 'gen-cards-v3');
      expect(jobs.jobs['job-1']!.promptVersion, 'gen-cards-v3');
      expect(
        jobs.jobs['job-1']!.status,
        GenerationJobStatus.running,
        reason: 'статус задания — срез 9, здесь не меняется',
      );
      expect(jobs.saves, 1);
    });

    test('без помощника версия промпта только в итоге прогона', () async {
      final CardsBatchRun run = await _engine(
        _FakeLlmPort(),
        account,
      ).run(_plannedOrder(2, profile));

      expect(run.promptVersion, 'gen-cards-v3');
    });
  });
}

// --- Фейки и помощники -----------------------------------------------------

CardsBatchEngine _engine(
  LlmPort port,
  ProviderAccount account, {
  CardSink? sink,
  Future<void> Function(Duration)? delay,
  BatchJobRecorder? jobRecorder,
  String? jobId,
}) => CardsBatchEngine(
  port: port,
  account: account,
  sink: sink,
  delay: delay,
  retryPolicy: RetryPolicy(jitter: () => 0.0),
  jobRecorder: jobRecorder,
  jobId: jobId,
);

/// Заказ: карта из достаточного числа единиц и полный план Allocation.
///
/// У единицы не больше [kMaxCardsPerUnit] различимых слотов (срез 14), поэтому
/// для заказа 40/80 нужно минимум 10/20 единиц — иначе план честно упрётся в
/// ёмкость, и «принято полностью» проверяло бы не то.
AllocationPlan _plannedOrder(int requested, ModelProfile profile) {
  final int needed = (requested + kMaxCardsPerUnit - 1) ~/ kMaxCardsPerUnit;
  final int unitCount = needed < 8 ? 8 : needed;
  final List<KnowledgeUnit> units = <KnowledgeUnit>[
    for (var index = 0; index < unitCount; index++) _unit('U$index'),
  ];
  return planAllocation(
    map: KnowledgeMap(documentId: 'doc:материал.md', units: units),
    requestedCards: requested,
    profile: profile,
  );
}

/// Ручной план с одной партией (для сценариев обрезки и отмены).
AllocationPlan _manualPlan({
  required ModelProfile profile,
  required List<KnowledgeUnit> units,
  required List<AllocatedCard> cards,
}) {
  final Map<String, int> counts = <String, int>{};
  for (final AllocatedCard card in cards) {
    counts[card.unitId] = (counts[card.unitId] ?? 0) + 1;
  }
  return AllocationPlan(
    requested: cards.length,
    profile: profile,
    units: <UnitBudget>[
      for (final KnowledgeUnit unit in units)
        UnitBudget(unit: unit, cards: counts[unit.id]!),
    ],
    cards: cards,
    batches: <AllocationBatch>[
      AllocationBatch(
        index: 0,
        profile: profile,
        cards: cards,
        inputTokens: 1000,
        outputTokens: cards.length * kDefaultOutputTokensPerCard,
      ),
    ],
  );
}

CardsBatch _batch({
  required List<KnowledgeUnit> units,
  required List<AllocatedCard> cards,
}) => CardsBatch(index: 0, units: units, cards: cards);

/// Единица фикстуры с полной ёмкостью (срез 16: углы по богатству).
KnowledgeUnit _unit(String id) => KnowledgeUnit(
  id: id,
  sectionId: 'doc:материал.md#0',
  topic: 'тема $id',
  kind: KnowledgeUnitKind.procedure,
  statement: 'Утверждение единицы $id о моменте силы.',
  anchors: <KnowledgeAnchor>[
    KnowledgeAnchor(
      blockId: 'doc:материал.md#0#0',
      quote:
          'Цитата материала $id. Второе верное утверждение. '
          'Третье верное утверждение.',
    ),
  ],
  salience: 1,
);

GeneratedCard _card(CardsBatch batch, AllocatedCard planned) {
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

GenerationResult _result(
  ProviderAccount account,
  CardsBatch batch, {
  required List<GeneratedCard> cards,
  bool truncated = false,
}) => GenerationResult(
  provider: account.protocol.adapterProvider,
  model: account.modelId,
  promptVersion: cardsPromptVersion,
  cards: cards,
  usage: const TokenUsage(
    promptTokens: 100,
    completionTokens: 50,
    totalTokens: 150,
  ),
  truncated: truncated,
);

GenerationResult _success(ProviderAccount account, CardsBatch batch) => _result(
  account,
  batch,
  cards: <GeneratedCard>[
    for (final AllocatedCard planned in batch.cards) _card(batch, planned),
  ],
);

class _FakeLlmPort implements LlmPort {
  _FakeLlmPort({this.onGenerate});

  final GenerationResult Function(CardsBatch batch)? onGenerate;
  final List<CardsBatch> calls = <CardsBatch>[];

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
    calls.add(batch);
    final GenerationResult Function(CardsBatch batch)? handler = onGenerate;
    if (handler != null) return handler(batch);
    return _success(account, batch);
  }
}

class _FakeCancellation implements CancellationSignal {
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class _RecordingSink implements CardSink {
  final List<GeneratedCard> saved = <GeneratedCard>[];

  @override
  Future<void> save(GeneratedCard card, {required int batchIndex}) async {
    saved.add(card);
  }
}

class _FakeJobRepository implements GenerationJobRepository {
  final Map<String, GenerationJob> jobs = <String, GenerationJob>{};
  int saves = 0;

  @override
  Future<GenerationJob?> jobById(String id) async => jobs[id];

  @override
  Future<void> save(GenerationJob job) async {
    saves++;
    jobs[job.id] = job;
  }
}
