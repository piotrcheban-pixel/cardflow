import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../live/support/live_budget.dart';
import '../../live/support/live_fixtures.dart';
import '../../live/support/live_pricing.dart';
import '../../live/support/live_scenarios.dart';
import '../../live/support/live_test_config.dart';

/// TASK 05: offline-проверка готовности сценариев A–C.
///
/// Здесь не отправляется ни одного запроса: production-`GenerationPlanBuilder`
/// строит те же планы, что получит `GenerationPipeline`, а числа проверяются
/// по подтверждённым тарифам. Это доказывает, что:
/// - `deepseek-flash` действительно подключён к каталогу (окно 1M, Vision);
/// - 5/40 карточек и небольшой документ дают ожидаемое число запросов;
/// - бюджеты logical/HTTP/стоимость покрывают эти планы;
/// - стоимость A–C достоверно ограничена.
void main() {
  LiveTestConfig task05Config() {
    return LiveTestConfig.fromEnvironment(const <String, String>{
      kLiveTestsVariable: '1',
      kLiveProviderVariable: 'deepseek',
      kLiveModelVariable: 'deepseek-flash',
      kLiveMaxRequestsVariable: '20',
      kLiveMaxCostVariable: '0.12',
      kLiveEnablePromptOnlyVariable: '1',
      kLiveEnableMaterialsVariable: '1',
      'DEEPSEEK_API_KEY': 'offline-placeholder',
    });
  }

  group('TASK 05 readiness: конфигурация A–C', () {
    test('deepseek-flash подтверждён каталогом и тарифом, запросы разрешены '
        'только явно', () {
      final LiveTestConfig config = task05Config();
      expect(config.skipReason, isNull);
      expect(config.account.modelId, 'deepseek-flash');
      expect(config.account.baseUrl, 'https://api.deepseek.com');
      expect(config.account.contextTokens, 1000000);
      expect(config.account.supportsVision, isTrue);
      expect(config.maxRequests, 20);
      expect(config.maxEstimatedCostUsd, 0.12);
      expect(livePriceFor('deepseek', 'deepseek-flash'), isNotNull);
      expect(
        livePriceFor('deepseek', 'deepseek-flash')!.verifiedOn,
        '2026-11-19',
      );

      // Без явного разрешения запросы запрещены даже при наличии ключа.
      final LiveTestConfig disabled = LiveTestConfig.fromEnvironment(
        const <String, String>{'DEEPSEEK_API_KEY': 'offline-placeholder'},
      );
      expect(disabled.skipReason, isNotNull);
      expect(disabled.maxRequests, 0);
      expect(disabled.maxEstimatedCostUsd, 0);
    });

    test('Test A: 5 карточек — один логический запрос, лимит 5', () {
      final LiveTestConfig config = task05Config();
      final ModelCapabilities capabilities = resolveModelCapabilities(
        config.account,
      );
      final PromptOnlyRequest request = PromptOnlyRequest(
        prompt: liveWishesShort(cards: 5),
        requestedCards: 5,
      );
      final GenerationPlan plan = const GenerationPlanBuilder().buildPromptOnly(
        request: request,
        capabilities: capabilities,
      );
      expect(plan.isPromptOnly, isTrue);
      expect(plan.isExecutable, isTrue);
      expect(plan.chunks, hasLength(1));
      expect(plan.chunks.single.limit, 5);
      expect(plan.plannedRequests, 1);
      expect(plan.estimate.totalTokens, greaterThan(0));
      expect(plan.estimate.continuationReserveTokens, 0);
    });

    test('Test B: 40 карточек — 6 логических запросов, continuity-резерв', () {
      final LiveTestConfig config = task05Config();
      final ModelCapabilities capabilities = resolveModelCapabilities(
        config.account,
      );
      final PromptOnlyRequest request = PromptOnlyRequest(
        prompt: liveWishesMany(cards: 40),
        requestedCards: 40,
      );
      final GenerationPlan plan = const GenerationPlanBuilder().buildPromptOnly(
        request: request,
        capabilities: capabilities,
      );
      expect(plan.isPromptOnly, isTrue);
      expect(plan.isExecutable, isTrue);
      expect(plan.chunks, hasLength(6));
      expect(plan.plannedRequests, 6);
      final int limits = plan.chunks.fold<int>(
        0,
        (int sum, PlannedChunk chunk) => sum + chunk.limit,
      );
      expect(limits, 40);
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.limit, lessThanOrEqualTo(kLiveCardsPerRequest));
      }
      // Сводка продолжения резервируется в бюджете уже на этапе плана.
      expect(plan.estimate.continuationReserveTokens, greaterThan(0));
      expect(plan.estimate.totalTokens, greaterThan(0));
    });

    test(
      'Test C: небольшой документ — один запрос, связи doc:, без потерь',
      () async {
        final LiveTestConfig config = task05Config();
        final ModelCapabilities capabilities = resolveModelCapabilities(
          config.account,
        );
        // Production-парсер TXT, а не заранее собранный ParsedDocument.
        final ParsedDocument document = await liveSmallDocumentParsed();
        expect(document.sections, hasLength(3));
        final GenerationPlan plan = const GenerationPlanBuilder().build(
          documents: <ParsedDocument>[document],
          capabilities: capabilities,
          wishes:
              'Сделай 6 карточек по этому материалу. Опирайся только на текст '
              'документа.',
          requestedCards: 6,
        );
        expect(plan.isPromptOnly, isFalse);
        expect(plan.isExecutable, isTrue);
        expect(plan.omitted, isEmpty);
        expect(plan.chunks, hasLength(1));
        expect(plan.plannedRequests, 1);
        final List<UnitSpan> units = plan.chunks
            .expand((PlannedChunk chunk) => chunk.units)
            .toList(growable: false);
        expect(units, isNotEmpty);
        expect(
          units.every((UnitSpan unit) => unit.unitId.startsWith('doc:')),
          isTrue,
        );
        expect(plan.chunks.single.materialsText, contains('Испарение'));
        expect(plan.chunks.single.materialsText, contains('Конденсация'));
        expect(plan.chunks.single.materialsText, contains('Осадки'));
      },
    );
  });

  group('TASK 05 readiness: бюджет A–C', () {
    test('8 логических / 16 HTTP-обменов укладываются в 20 / 40', () {
      final LiveTestConfig config = task05Config();
      final List<LiveScenarioPlan> plans = <LiveScenarioPlan>[
        liveScenarioPlanById('prompt_only_short')!,
        liveScenarioPlanById('prompt_only_many_40')!,
        liveScenarioPlanById('small_document')!,
      ];
      final int logical = plans.fold<int>(
        0,
        (int sum, LiveScenarioPlan plan) => sum + plan.expectedRequests,
      );
      final int http = plans.fold<int>(
        0,
        (int sum, LiveScenarioPlan plan) => sum + plan.expectedHttpRequests,
      );
      expect(logical, 8);
      expect(http, 16);
      expect(logical, lessThanOrEqualTo(config.maxRequests));
      expect(http, lessThanOrEqualTo(config.maxRequests * 2));
      for (final LiveScenarioPlan plan in plans) {
        expect(plan.costFor(config).isKnown, isTrue, reason: plan.id);
        expect(
          plan.costFor(config).blockReason(config),
          isNull,
          reason: plan.id,
        );
      }
    });

    test('стоимость A–C по пиковому тарифу ≈ \$0.0528 и ≤ \$0.12', () {
      final LiveTestConfig config = task05Config();
      final Map<String, double> amounts = <String, double>{
        for (final String id in <String>[
          'prompt_only_short',
          'prompt_only_many_40',
          'small_document',
        ])
          id: liveScenarioPlanById(id)!.costFor(config).amount!,
      };
      expect(amounts['prompt_only_short'], closeTo(0.00534, 1e-9));
      expect(amounts['prompt_only_many_40'], closeTo(0.0414, 1e-9));
      expect(amounts['small_document'], closeTo(0.00606, 1e-9));
      final double total = amounts.values.fold<double>(
        0,
        (double sum, double amount) => sum + amount,
      );
      expect(total, closeTo(0.0528, 1e-9));
      expect(total, lessThanOrEqualTo(config.maxEstimatedCostUsd));
    });

    test('cost guard блокирует запрос, который выводит A–C за \$0.05', () {
      final LivePrice price = livePriceFor('deepseek', 'deepseek-flash')!;
      final LiveCostGuard guard = LiveCostGuard(
        price: price,
        maxCostUsd: 0.05,
        outputTokensPerRequest: 3500,
      );
      // A: 7800/2500.
      guard
          .reserve(inputTokens: 7800, outputTokens: 2500)
          .commit(actualInputTokens: 7800, actualOutputTokens: 2500);
      // B: 6 запросов по 9000/3500.
      for (var index = 0; index < 6; index++) {
        guard
            .reserve(inputTokens: 9000, outputTokens: 3500)
            .commit(actualInputTokens: 9000, actualOutputTokens: 3500);
      }
      // C: 8200/3000 — выводит за $0.05.
      expect(
        () => guard.reserve(inputTokens: 8200, outputTokens: 3000),
        throwsA(isA<LiveBudgetExceeded>()),
      );
      expect(guard.blocked, 1);
      expect(guard.spentUsd, lessThanOrEqualTo(0.05));
    });

    test('12 HTTP-обменов Test B не обходят лимит 40', () {
      final LiveRequestBudget http = LiveRequestBudget(maxRequests: 40);
      for (var index = 0; index < 12; index++) {
        http.reserve();
      }
      expect(http.used, 12);
      expect(http.isExhausted, isFalse);
      expect(http.remaining, 28);
    });
  });
}
