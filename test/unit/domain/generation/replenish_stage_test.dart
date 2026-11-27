import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';

/// DoD среза 7 (`TASK.txt` «Срез 7. Replenish и partial»): добор идёт только по
/// единицам с недобором и с контекстом принятого; предохранители (проходы,
/// запросы, токены, время) останавливают операцию с точной причиной;
/// `exhausted_material` — не ошибка и не повод добирать; недобор никогда не
/// выдаётся за успех; отмена сохраняет принятое.
///
/// Сеть и ключи не нужны: `LlmPort` — фейк в памяти.
void main() {
  group('предохранители операции (п. 2)', () {
    test('предел запросов — f(requested): запрос на карточку, минимум три', () {
      expect(maxRequestsForRequested(1), 3);
      expect(maxRequestsForRequested(2), 3);
      expect(maxRequestsForRequested(3), 3);
      expect(maxRequestsForRequested(4), 4);
      expect(maxRequestsForRequested(6), 6);
      expect(maxRequestsForRequested(10), 10);
      expect(maxRequestsForRequested(40), 40);
      expect(maxRequestsForRequested(100), 100);
      expect(maxRequestsForRequested(0), 0);
    });

    test('предел запросов не убывает с заказом', () {
      var previous = 0;
      for (var requested = 0; requested <= 200; requested++) {
        final int limit = maxRequestsForRequested(requested);
        expect(
          limit,
          greaterThanOrEqualTo(previous),
          reason: 'предел запросов не должен убывать: $requested',
        );
        previous = limit;
      }
    });

    test('бюджет токенов операции — оценки всех проходов плана', () {
      final AllocationPlan plan = _plan(<int>[2, 3, 4]);

      // Батчи: 900+600, 900+900, 900+1200 = 5400 на проход.
      expect(tokenBudgetForPlan(plan), 21600);
      expect(tokenBudgetForPlan(plan, passes: 1), 10800);
      expect(tokenBudgetForPlan(plan, passes: 0), 5400);
    });

    test('политика по умолчанию: три прохода, запросы и время от заказа', () {
      final AllocationPlan plan = _plan(<int>[2, 3, 4]);
      const ReplenishPolicy policy = ReplenishPolicy();

      expect(policy.maxPasses, 3);
      expect(ReplenishPolicy.defaultMaxPasses, 3);
      expect(policy.requestsLimit(40), 40);
      expect(policy.tokenLimit(plan), 21600);
      // Срез 10: время операции — max(10 мин, 2 с × заказ), а не константа.
      expect(policy.wallClock, isNull);
      expect(policy.wallClockFor(4), const Duration(minutes: 10));
      expect(policy.wallClockFor(40), const Duration(minutes: 10));
      expect(policy.wallClockFor(600), const Duration(minutes: 20));
      expect(
        ReplenishPolicy.wallClockForRequested(300),
        const Duration(minutes: 10),
      );
      expect(
        ReplenishPolicy.wallClockForRequested(0),
        const Duration(minutes: 10),
      );
    });

    test('явные пределы политики перекрывают вычисленные', () {
      final AllocationPlan plan = _plan(<int>[2, 3, 4]);
      const ReplenishPolicy policy = ReplenishPolicy(
        maxPasses: 5,
        maxRequests: 7,
        tokenBudget: 1000,
        wallClock: Duration(seconds: 30),
      );

      expect(policy.maxPasses, 5);
      expect(policy.requestsLimit(40), 7);
      expect(policy.tokenLimit(plan), 1000);
      expect(policy.wallClock, const Duration(seconds: 30));
      expect(policy.wallClockFor(600), const Duration(seconds: 30));
    });
  });

  group('добор — только единицы с недобором', () {
    test(
      'дозапрос идёт только по единицам долга, новые единицы не выдумываются',
      () async {
        // Три батча по две карточки: у U0 и U1 всё принято, U2 упал.
        final AllocationPlan plan = _plan(<int>[2, 2, 2]);
        final GenerationLedger ledger = _ledgerFor(
          plan,
          acceptedByBatch: <int, int>{0: 2, 1: 2},
          causes: <int, ShortfallKind>{2: ShortfallKind.providerError},
        );
        final _FakeLlmPort port = _FakeLlmPort();

        final ReplenishOutcome outcome = await _stage(port).run(
          plan: plan,
          ledger: ledger,
          acceptedCards: _cardsOf(plan, <int>[0, 1]),
        );

        expect(outcome.stage, GenerationStage.ready);
        expect(outcome.reason, ReplenishStopReason.complete);
        expect(outcome.accepted, 6);
        expect(port.calls.length, 1);

        final CardsBatch request = port.calls.single;
        expect(request.unitIds, <String>['U2']);
        expect(
          request.cards.map((AllocatedCard card) => card.unitId).toSet(),
          <String>{'U2'},
          reason: 'в добор не попадают единицы без долга',
        );
        expect(request.topUp, isTrue, reason: 'добор помечен как topUp');
        final ReplenishPass pass = outcome.passes.single;
        expect(
          pass.plan.units.map((UnitBudget budget) => budget.unit.id),
          <String>['U2'],
        );
        expect(pass.requested, 2);
        expect(pass.filledSlots, 2);
        expect(pass.unitIds, <String>['U2']);
        expect(pass.acceptedCount, 2);
        expect(pass.requests, 1);
        expect(pass.toString(), contains('принято 2'));
        expect(outcome.toString(), contains('complete'));
      },
    );

    test('план добора — ровно карточки долга, заказ равен долгу', () async {
      // Принята основная карточка U0, батч U1 целиком, U2 упал:
      // долг = reverse-угол U0 + две карточки U2.
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 1, 1: 2},
        causes: <int, ShortfallKind>{2: ShortfallKind.providerError},
      );
      // Из батча U0 принята только основная карточка, батч U1 — целиком.
      final List<GeneratedCard> accepted = <GeneratedCard>[
        _cardFor(plan, plan.batches[0].cards.first),
        for (final AllocatedCard card in plan.batches[1].cards)
          _cardFor(plan, card),
      ];
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome = await _stage(port)
          .run(plan: plan, ledger: ledger, acceptedCards: accepted);

      final ReplenishPass pass = outcome.passes.single;
      expect(pass.requested, 3, reason: 'долг: 1 угол U0 + 2 карточки U2');
      expect(
        pass.plan.cards,
        isNot(contains(const AllocatedCard(unitId: 'U0'))),
        reason: 'принятая карточка не заказывается снова',
      );
      expect(
        pass.plan.cards,
        containsAll(<AllocatedCard>[
          const AllocatedCard(unitId: 'U0', angle: AllocationAngle.reverse),
          const AllocatedCard(unitId: 'U2'),
          const AllocatedCard(unitId: 'U2', angle: AllocationAngle.reverse),
        ]),
      );
      expect(
        pass.plan.units.map((UnitBudget budget) => budget.unit.id),
        <String>['U0', 'U2'],
      );
      expect(outcome.accepted, 6);
    });

    test('запрос добора несёт контекст принятого тех же единиц', () async {
      final AllocationPlan plan = _plan(<int>[3]);
      final List<GeneratedCard> accepted = <GeneratedCard>[
        _cardFor(plan, plan.cards.first),
      ];
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 1},
      );
      final _FakeLlmPort port = _FakeLlmPort();

      await _stage(port)
          .run(plan: plan, ledger: ledger, acceptedCards: accepted);

      final CardsBatch request = port.calls.single;
      expect(request.accepted.length, 1);
      expect(request.accepted.single.front, accepted.single.front);
      expect(
        request.accepted.single.statement,
        _unit('U0').statement,
        reason: 'контекст — front принятого и утверждение его единицы',
      );
    });

    test('ответ перефразированием принятого не даёт прогресса', () async {
      final AllocationPlan plan = _plan(<int>[3]);
      final List<GeneratedCard> accepted = <GeneratedCard>[
        _cardFor(plan, plan.cards.first),
      ];
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 1},
      );
      // Модель повторяет уже принятую карточку вместо запрошенных слотов.
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) =>
            _result(batch, cards: <GeneratedCard>[accepted.single]),
      );

      final ReplenishOutcome outcome = await _stage(port)
          .run(plan: plan, ledger: ledger, acceptedCards: accepted);

      expect(outcome.reason, ReplenishStopReason.exhaustedMaterial);
      expect(
        outcome.passes.length,
        1,
        reason: 'перефразирование не добирается',
      );
      expect(port.calls.length, 1);
      expect(outcome.accepted, 1, reason: 'повтор не уменьшает долг');
      expect(outcome.passes.single.surplus, 1);
      expect(outcome.unfilledSlots, 2);
      expect(outcome.stage, GenerationStage.partial);
    });
  });

  group('DoD среза 7', () {
    test(
      '40 запрошено, материал на 12 → partial, accepted=12, exhausted_material',
      () async {
        // 40 карточек из семи батчей; принято 12 (два батча), остальные батчи
        // первый проход уже объявил исчерпанными.
        final AllocationPlan plan = _plan(<int>[6, 6, 6, 6, 6, 6, 4]);
        final GenerationLedger ledger = _ledgerFor(
          plan,
          acceptedByBatch: <int, int>{0: 6, 1: 6},
          causes: <int, ShortfallKind>{
            2: ShortfallKind.exhaustedMaterial,
            3: ShortfallKind.exhaustedMaterial,
            4: ShortfallKind.exhaustedMaterial,
            5: ShortfallKind.exhaustedMaterial,
            6: ShortfallKind.exhaustedMaterial,
          },
        );
        final _FakeLlmPort port = _FakeLlmPort();

        final ReplenishOutcome outcome = await _stage(port).run(
          plan: plan,
          ledger: ledger,
          acceptedCards: _cardsOf(plan, <int>[0, 1]),
        );

        expect(outcome.requested, 40);
        expect(outcome.accepted, 12);
        expect(outcome.stage, GenerationStage.partial);
        expect(outcome.isComplete, isFalse, reason: 'недобор — не успех');
        expect(outcome.reason, ReplenishStopReason.exhaustedMaterial);
        expect(outcome.remaining, 28);
        expect(outcome.unfilledSlots, 28);
        expect(outcome.materialCapacity, 12);
        expect(
          port.calls,
          isEmpty,
          reason: 'исчерпанный материал — не ошибка и не повод добирать',
        );
        expect(outcome.passes, isEmpty);
      },
    );

    test('сбой на третьем батче → добор, accepted растёт', () async {
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2, 1: 2},
        causes: <int, ShortfallKind>{2: ShortfallKind.providerError},
      );
      final List<GeneratedCard> accepted = _cardsOf(plan, <int>[0, 1]);
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome = await _stage(port)
          .run(plan: plan, ledger: ledger, acceptedCards: accepted);

      expect(outcome.accepted, 6);
      expect(outcome.accepted, greaterThan(accepted.length));
      expect(outcome.remaining, 0);
      expect(outcome.isComplete, isTrue);
      expect(outcome.reason, ReplenishStopReason.complete);
      expect(outcome.stage, GenerationStage.ready);
      expect(outcome.passes.length, 1);
      expect(
        outcome.requests,
        4,
        reason: '3 запроса первого прохода + 1 добор',
      );
    });

    test(
      'бесконечный цикл невозможен: maxPasses останавливает добор',
      () async {
        final AllocationPlan plan = _plan(<int>[2, 2, 2]);
        final GenerationLedger ledger = _ledgerFor(
          plan,
          acceptedByBatch: <int, int>{0: 2},
          causes: <int, ShortfallKind>{
            1: ShortfallKind.providerError,
            2: ShortfallKind.providerError,
          },
        );
        // Модель каждый раз возвращает ровно одну карточку — заказ не закрыть.
        final _FakeLlmPort port = _FakeLlmPort(
          onGenerate: (CardsBatch batch) => _result(
            batch,
            cards: <GeneratedCard>[_cardForBatch(batch, batch.cards.first)],
          ),
        );

        final ReplenishOutcome outcome = await _stage(port).run(
          plan: plan,
          ledger: ledger,
          acceptedCards: _cardsOf(plan, <int>[0]),
        );

        expect(outcome.reason, ReplenishStopReason.maxPasses);
        expect(
          outcome.passes.length,
          3,
          reason: 'не больше maxPasses проходов',
        );
        expect(port.calls.length, 3);
        expect(outcome.accepted, 5);
        expect(outcome.unfilledSlots, 1);
        expect(outcome.stage, GenerationStage.partial);
        expect(outcome.isComplete, isFalse);
      },
    );

    test('отмена → partial с сохранением принятого', () async {
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{
          1: ShortfallKind.providerError,
          2: ShortfallKind.providerError,
        },
      );
      final _FakeCancellation cancellation = _FakeCancellation();
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) {
          cancellation.cancel();
          return _success(batch);
        },
      );

      final ReplenishOutcome outcome =
          await _stage(port, outputTokensPerCard: 5000).run(
            plan: plan,
            ledger: ledger,
            acceptedCards: _cardsOf(plan, <int>[0]),
            cancellation: cancellation,
          );

      expect(outcome.reason, ReplenishStopReason.cancelled);
      expect(outcome.stage, GenerationStage.partial);
      expect(outcome.accepted, 3, reason: 'принятое до отмены сохраняется');
      expect(outcome.acceptedCards.length, 3);
      expect(outcome.remaining, 3);
      expect(port.calls.length, 1, reason: 'после отмены запросов нет');
    });
  });

  group('остановка предохранителем — точная причина', () {
    test('maxRequests: предел запросов операции', () async {
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{
          1: ShortfallKind.providerError,
          2: ShortfallKind.providerError,
        },
        attempts: false,
      );
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome =
          await _stage(
            port,
            policy: const ReplenishPolicy(maxRequests: 1),
            outputTokensPerCard: 5000,
          ).run(
            plan: plan,
            ledger: ledger,
            acceptedCards: _cardsOf(plan, <int>[0]),
          );

      expect(outcome.reason, ReplenishStopReason.maxRequests);
      expect(port.calls.length, 1);
      expect(outcome.requests, 1);
      expect(outcome.stage, GenerationStage.partial);
    });

    test('tokenBudget: расход операции', () async {
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{
          1: ShortfallKind.providerError,
          2: ShortfallKind.providerError,
        },
        attempts: false,
      );
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome =
          await _stage(
            port,
            policy: const ReplenishPolicy(tokenBudget: 100),
            outputTokensPerCard: 5000,
          ).run(
            plan: plan,
            ledger: ledger,
            acceptedCards: _cardsOf(plan, <int>[0]),
          );

      expect(outcome.reason, ReplenishStopReason.tokenBudget);
      expect(port.calls.length, 1);
      expect(outcome.usage.totalTokens, 150);
    });

    test('wallClock: предел времени операции', () async {
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{
          1: ShortfallKind.providerError,
          2: ShortfallKind.providerError,
        },
        attempts: false,
      );
      final _FakeClock clock = _FakeClock(DateTime.utc(2026, 11, 27, 12));
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) {
          clock.advance(const Duration(minutes: 11));
          return _success(batch);
        },
      );

      final ReplenishOutcome outcome =
          await _stage(
            port,
            policy: const ReplenishPolicy(wallClock: Duration(minutes: 10)),
            clock: clock,
            outputTokensPerCard: 5000,
          ).run(
            plan: plan,
            ledger: ledger,
            acceptedCards: _cardsOf(plan, <int>[0]),
          );

      expect(outcome.reason, ReplenishStopReason.wallClock);
      expect(port.calls.length, 1);
      expect(outcome.duration, const Duration(minutes: 11));
    });

    test('срез 10: предохранители в итоге, wallClock — от заказа', () async {
      final AllocationPlan plan = _plan(<int>[2, 2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{
          1: ShortfallKind.providerError,
          2: ShortfallKind.providerError,
        },
        attempts: false,
      );
      final _FakeClock clock = _FakeClock(DateTime.utc(2026, 11, 27, 12));
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) {
          clock.advance(const Duration(minutes: 11));
          return _success(batch);
        },
      );

      final ReplenishOutcome outcome =
          await _stage(port, clock: clock, outputTokensPerCard: 5000).run(
            plan: plan,
            ledger: ledger,
            acceptedCards: _cardsOf(plan, <int>[0]),
          );

      // Политика по умолчанию: заказ 6 → max(10 мин, 2 с × 6) = 10 минут.
      expect(outcome.reason, ReplenishStopReason.wallClock);
      final ReplenishGuards guards = outcome.guards!;
      expect(guards.hit, ReplenishStopReason.wallClock);
      expect(guards.hitsGuard, isTrue);
      expect(guards.maxPasses, ReplenishPolicy.defaultMaxPasses);
      expect(guards.maxRequests, 6);
      expect(guards.wallClock, const Duration(minutes: 10));
      expect(guards.tokenBudget, greaterThan(0));
    });

    test('срез 10: wallClock растёт с заказом (2 с на карточку)', () {
      expect(
        ReplenishPolicy.wallClockForRequested(40),
        const Duration(minutes: 10),
      );
      expect(
        ReplenishPolicy.wallClockForRequested(900),
        const Duration(minutes: 30),
      );
    });

    test('план без единиц (prompt-only) — no_unit_plan без запросов', () async {
      final AllocationPlan plan = AllocationPlan(
        requested: 5,
        profile: _profile,
        units: const <UnitBudget>[],
        cards: const <AllocatedCard>[],
        batches: const <AllocationBatch>[],
      );
      final GenerationLedger ledger = GenerationLedger.fromBudgets(<int>[5]);
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome = await _stage(port)
          .run(plan: plan, ledger: ledger);

      expect(outcome.reason, ReplenishStopReason.noUnitPlan);
      expect(outcome.stage, GenerationStage.partial);
      expect(port.calls, isEmpty);
      expect(outcome.accepted, 0);
    });

    test(
      'сбой провайдера в доборе — provider_error, принятое сохранено',
      () async {
        final AllocationPlan plan = _plan(<int>[2, 2]);
        final GenerationLedger ledger = _ledgerFor(
          plan,
          acceptedByBatch: <int, int>{0: 2},
          causes: <int, ShortfallKind>{1: ShortfallKind.providerError},
          attempts: false,
        );
        final _FakeLlmPort port = _FakeLlmPort(
          onGenerate: (CardsBatch batch) => throw const GenerationException(
            GenerationErrorCode.serverUnavailable,
          ),
        );

        final ReplenishOutcome outcome = await _stage(port).run(
          plan: plan,
          ledger: ledger,
          acceptedCards: _cardsOf(plan, <int>[0]),
        );

        expect(outcome.reason, ReplenishStopReason.providerError);
        expect(outcome.accepted, 2);
        expect(outcome.stage, GenerationStage.partial);
        expect(outcome.requests, 1);
      },
    );
  });

  group('итог не выдаёт успех при недоборе', () {
    test('ready только при закрытых слотах, а не по числу карточек', () async {
      // Две карточки уже приняты (переполнение по слоту), но угол reverse
      // остался незакрытым: accepted == requested, однако это недобор.
      final AllocationPlan plan = _plan(<int>[2]);
      final List<GeneratedCard> accepted = <GeneratedCard>[
        _cardFor(plan, plan.cards.first),
        _cardFor(plan, plan.cards.first),
      ];
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        attempts: false,
      );
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) =>
            _result(batch, cards: const <GeneratedCard>[]),
      );

      final ReplenishOutcome outcome = await _stage(port)
          .run(plan: plan, ledger: ledger, acceptedCards: accepted);

      expect(outcome.accepted, 2);
      expect(outcome.remaining, 0);
      expect(outcome.unfilledSlots, 1);
      expect(outcome.reason, ReplenishStopReason.exhaustedMaterial);
      expect(outcome.stage, GenerationStage.partial);
      expect(outcome.isComplete, isFalse, reason: 'слот не закрыт — не успех');
    });

    test('полное закрытие: ready, isComplete, materialCapacity нет', () async {
      final AllocationPlan plan = _plan(<int>[2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2, 1: 2},
      );
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome = await _stage(port).run(
        plan: plan,
        ledger: ledger,
        acceptedCards: _cardsOf(plan, <int>[0, 1]),
      );

      expect(outcome.reason, ReplenishStopReason.complete);
      expect(outcome.stage, GenerationStage.ready);
      expect(outcome.isComplete, isTrue);
      expect(outcome.materialCapacity, isNull);
      expect(outcome.remaining, 0);
      expect(outcome.unfilledSlots, 0);
      expect(port.calls, isEmpty);
    });

    test('исчерпание уже объявлено первым проходом — запросов нет', () async {
      final AllocationPlan plan = _plan(<int>[2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{1: ShortfallKind.exhaustedMaterial},
      );
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome = await _stage(port).run(
        plan: plan,
        ledger: ledger,
        acceptedCards: _cardsOf(plan, <int>[0]),
      );

      expect(outcome.reason, ReplenishStopReason.exhaustedMaterial);
      expect(outcome.materialCapacity, 2);
      expect(port.calls, isEmpty);
      expect(outcome.passes, isEmpty);
    });
  });

  group('коды причин и учёт расхода операции', () {
    test('причины — машинные коды: разбор строки и предохранители', () {
      for (final ReplenishStopReason reason in ReplenishStopReason.values) {
        expect(ReplenishStopReason.fromWire(reason.wireName), reason);
      }
      expect(
        () => ReplenishStopReason.fromWire('unknown_reason'),
        throwsFormatException,
      );
      expect(ReplenishStopReason.maxPasses.isGuard, isTrue);
      expect(ReplenishStopReason.maxRequests.isGuard, isTrue);
      expect(ReplenishStopReason.tokenBudget.isGuard, isTrue);
      expect(ReplenishStopReason.wallClock.isGuard, isTrue);
      expect(ReplenishStopReason.complete.isGuard, isFalse);
      expect(ReplenishStopReason.exhaustedMaterial.isGuard, isFalse);
      expect(ReplenishStopReason.providerError.isGuard, isFalse);
      expect(ReplenishStopReason.cancelled.isGuard, isFalse);
      expect(ReplenishStopReason.noUnitPlan.isGuard, isFalse);
    });

    test(
      'политика сравнивается по всем пределам, отрицательные проходы — ошибка',
      () {
        const ReplenishPolicy a = ReplenishPolicy(maxRequests: 5);
        const ReplenishPolicy b = ReplenishPolicy(maxRequests: 5);
        const ReplenishPolicy c = ReplenishPolicy(maxRequests: 6);

        expect(a, b);
        expect(a.hashCode, b.hashCode);
        expect(a, isNot(c));
        expect(a.toString(), contains('запросов 5'));
        expect(
          () => tokenBudgetForPlan(_plan(<int>[1]), passes: -1),
          throwsArgumentError,
        );
      },
    );

    test('отмена кодом провайдера — cancelled, принятое сохранено', () async {
      final AllocationPlan plan = _plan(<int>[2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{1: ShortfallKind.providerError},
        attempts: false,
      );
      final _FakeLlmPort port = _FakeLlmPort(
        onGenerate: (CardsBatch batch) =>
            throw const GenerationException(GenerationErrorCode.cancelled),
      );

      final ReplenishOutcome outcome = await _stage(port).run(
        plan: plan,
        ledger: ledger,
        acceptedCards: _cardsOf(plan, <int>[0]),
      );

      expect(outcome.reason, ReplenishStopReason.cancelled);
      expect(outcome.stage, GenerationStage.partial);
      expect(outcome.accepted, 2);
    });

    test('бюджет считает расход без totalTokens по слагаемым', () async {
      final AllocationPlan plan = _plan(<int>[2, 2]);
      final GenerationLedger ledger = _ledgerFor(
        plan,
        acceptedByBatch: <int, int>{0: 2},
        causes: <int, ShortfallKind>{1: ShortfallKind.providerError},
        attempts: false,
      );
      final _FakeLlmPort port = _FakeLlmPort();

      final ReplenishOutcome outcome =
          await _stage(
            port,
            policy: const ReplenishPolicy(tokenBudget: 1000),
          ).run(
            plan: plan,
            ledger: ledger,
            acceptedCards: _cardsOf(plan, <int>[0]),
            initialUsage: const TokenUsage(
              promptTokens: 1000,
              completionTokens: 500,
            ),
          );

      expect(outcome.reason, ReplenishStopReason.tokenBudget);
      expect(
        port.calls,
        isEmpty,
        reason: 'бюджет уже израсходован первым проходом',
      );
    });
  });
}

// --- Помощники и фейки -----------------------------------------------------

const ModelProfile _profile = ModelProfile(
  id: 'deepseek-chat',
  provider: 'deepseek',
  contextWindow: 128000,
  maxOutputTokens: 8192,
  supportsJsonSchema: true,
  supportsVision: false,
  concurrency: 1,
);

const ProviderAccount _account = ProviderAccount(
  id: 'account-1',
  label: 'DeepSeek',
  protocol: ProviderProtocol.openaiCompletions,
  baseUrl: 'https://api.deepseek.test/v1',
  modelId: 'deepseek-chat',
);

const List<AllocationAngle> _angles = <AllocationAngle>[
  AllocationAngle.reverse,
  AllocationAngle.cloze,
  AllocationAngle.application,
];

ReplenishStage _stage(
  LlmPort port, {
  ReplenishPolicy policy = const ReplenishPolicy(),
  Clock? clock,
  int outputTokensPerCard = kDefaultOutputTokensPerCard,
}) => ReplenishStage(
  port: port,
  account: _account,
  clock: clock ?? _FakeClock(DateTime.utc(2026, 11, 27, 12)),
  policy: policy,
  outputTokensPerCard: outputTokensPerCard,
);

/// Ручной план: каждый батч — своя единица, карточки — основная и углы.
AllocationPlan _plan(List<int> batchSizes) {
  final List<UnitBudget> units = <UnitBudget>[];
  final List<AllocatedCard> cards = <AllocatedCard>[];
  final List<AllocationBatch> batches = <AllocationBatch>[];
  for (var index = 0; index < batchSizes.length; index++) {
    final String id = 'U$index';
    final KnowledgeUnit unit = _unit(id);
    final List<AllocatedCard> batchCards = <AllocatedCard>[
      for (var card = 0; card < batchSizes[index]; card++)
        AllocatedCard(
          unitId: id,
          angle: card == 0 ? null : _angles[(card - 1) % _angles.length],
        ),
    ];
    units.add(UnitBudget(unit: unit, cards: batchCards.length));
    cards.addAll(batchCards);
    batches.add(
      AllocationBatch(
        index: index,
        profile: _profile,
        cards: batchCards,
        inputTokens: 900,
        outputTokens: batchCards.length * kDefaultOutputTokensPerCard,
      ),
    );
  }
  return AllocationPlan(
    requested: cards.length,
    profile: _profile,
    units: units,
    cards: cards,
    batches: batches,
  );
}

/// Журнал первого прохода: бюджеты плана, принятое по батчам и причины.
GenerationLedger _ledgerFor(
  AllocationPlan plan, {
  Map<int, int> acceptedByBatch = const <int, int>{},
  Map<int, ShortfallKind> causes = const <int, ShortfallKind>{},
  bool attempts = true,
}) {
  var ledger = GenerationLedger.fromBudgets(<int>[
    for (final AllocationBatch batch in plan.batches) batch.cards.length,
  ]);
  for (final AllocationBatch batch in plan.batches) {
    if (attempts) ledger = ledger.attempt(batch.index);
    final int accepted = acceptedByBatch[batch.index] ?? 0;
    if (accepted > 0) {
      ledger = ledger.record(batch.index, generated: accepted);
    }
    final ShortfallKind? cause = causes[batch.index];
    if (cause != null) ledger = ledger.markCause(batch.index, cause);
  }
  return ledger;
}

/// Принятые карточки батчей [batchIndexes] (номера не повторяются).
List<GeneratedCard> _cardsOf(AllocationPlan plan, List<int> batchIndexes) {
  final Set<int> indexes = batchIndexes.toSet();
  return <GeneratedCard>[
    for (final AllocationBatch batch in plan.batches)
      if (indexes.contains(batch.index))
        for (final AllocatedCard card in batch.cards) _cardFor(plan, card),
  ];
}

GeneratedCard _cardFor(AllocationPlan plan, AllocatedCard planned) {
  final KnowledgeUnit unit = plan.units
      .firstWhere((UnitBudget budget) => budget.unit.id == planned.unitId)
      .unit;
  return GeneratedCard(
    front: 'Вопрос ${unit.id}/${planned.angle?.wireName ?? 'primary'}',
    back: unit.statement,
    cardType: CardType.basic,
    unitId: unit.id,
    angle: planned.angle?.wireName,
    quoteRef: unit.anchors.first.quote,
  );
}

/// Карточка по слоту конкретного запроса (как ответит модель).
GeneratedCard _cardForBatch(CardsBatch batch, AllocatedCard planned) {
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
  CardsBatch batch, {
  required List<GeneratedCard> cards,
  bool truncated = false,
}) => GenerationResult(
  provider: _account.protocol.adapterProvider,
  model: _account.modelId,
  promptVersion: 'gen-cards-v3',
  cards: cards,
  usage: const TokenUsage(
    promptTokens: 100,
    completionTokens: 50,
    totalTokens: 150,
  ),
  truncated: truncated,
);

GenerationResult _success(CardsBatch batch) => _result(
  batch,
  cards: <GeneratedCard>[
    for (final AllocatedCard planned in batch.cards)
      _cardForBatch(batch, planned),
  ],
);

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
    return _success(batch);
  }
}

class _FakeCancellation implements CancellationSignal {
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class _FakeClock implements Clock {
  _FakeClock(this._now);

  DateTime _now;

  void advance(Duration duration) => _now = _now.add(duration);

  @override
  DateTime now() => _now;
}
