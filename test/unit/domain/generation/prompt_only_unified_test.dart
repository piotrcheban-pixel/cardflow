import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';

/// Итерация 7.18.1 (§0.11/§2.1): prompt-only использует **ту же** машинерию
/// планирования (`InputPlanner` → `OutputBatchPlanner` → `GenerationPlan`), а
/// не отдельный планировщик; распределения по разделам у него нет.
void main() {
  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 1000,
    schemaTokens: 200,
    wrapperTokens: 100,
    taskTailTokens: 20,
  );

  ModelCapabilities caps({
    int? context = 128000,
    int? maxOutput,
    int? maxCards,
    int? maxRequestBytes,
  }) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: context == null
          ? CapabilitySource.unknown
          : CapabilitySource.officialCatalog,
      maxOutputTokens: maxOutput,
      maxCardsPerRequest: maxCards,
      maxRequestBytes: maxRequestBytes,
    );
  }

  GenerationPlan viaBuilder(
    String prompt, {
    int? requested,
    ModelCapabilities? capabilities,
    GenerationOverheadTokens overheadTokens = overhead,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
  }) {
    return const GenerationPlanBuilder().buildPromptOnly(
      request: PromptOnlyRequest(prompt: prompt, requestedCards: requested),
      capabilities: capabilities ?? caps(maxOutput: 50000),
      overhead: overheadTokens,
      budgetConfig: budgetConfig,
    );
  }

  GenerationPlan viaPlanner(
    String prompt, {
    int? requested,
    ModelCapabilities? capabilities,
  }) {
    return const GenerationChunkPlanner().plan(
      inventory: ContentInventory.empty,
      capabilities: capabilities ?? caps(maxOutput: 50000),
      overhead: overhead,
      requestedCards: requested,
      allowPromptOnly: true,
      wishes: prompt,
    );
  }

  test('buildPromptOnly возвращает общий InputPlan стратегии promptOnly', () {
    final GenerationPlan plan = viaBuilder('Фотосинтез', requested: 20);
    expect(plan.inputPlan, isNotNull);
    expect(plan.inputPlan!.strategy, InputStrategy.promptOnly);
    expect(plan.isPromptOnly, isTrue);
    expect(plan.mode, GenerationMode.promptOnly);
  });

  test('предпросмотр и общий планировщик дают один и тот же план', () {
    const String prompt = 'Создай карточки по истории Древнего Рима';
    final GenerationPlan preview = viaBuilder(prompt, requested: 120);
    final GenerationPlan general = viaPlanner(prompt, requested: 120);
    expect(
      preview.chunks.map((PlannedChunk chunk) => chunk.limit).toList(),
      general.chunks.map((PlannedChunk chunk) => chunk.limit).toList(),
    );
    expect(preview.plannedRequests, general.plannedRequests);
    expect(preview.estimate.totalTokens, general.estimate.totalTokens);
    expect(preview.inputPlan!.inputTokens, general.inputPlan!.inputTokens);
    expect(preview.validity.kind, general.validity.kind);
  });

  test('prompt-only не применяет распределение по разделам', () {
    final GenerationPlan plan = viaBuilder('Тема', requested: 10);
    expect(plan.allocation, isNotNull);
    expect(plan.allocation!.planned, isEmpty);
    expect(
      plan.chunks.every((PlannedChunk c) => c.focusSectionIds.isEmpty),
      isTrue,
    );
  });

  test('тема входит в бюджет каждого запроса (без двойного счёта)', () {
    const String prompt = 'Тема запроса';
    final GenerationPlan plan = viaBuilder(prompt, requested: 10);
    final int themeTokens = plan.chunks.first.textTokens;
    expect(themeTokens, greaterThan(0));
    expect(plan.estimate.inputTextTokens, themeTokens * plan.chunks.length);
    final int fixed = plan.inputPlan!.fixedTokens;
    expect(
      fixed,
      greaterThan(overhead.fixedTokens),
      reason: 'тема прибавлена к обвязке, а не потеряна',
    );
  });

  test('недостаточный бюджет темы: invalid, а не «всё равно»', () {
    final GenerationPlan plan = viaBuilder(
      'Тема',
      capabilities: caps(context: 8000),
      overheadTokens: const GenerationOverheadTokens(
        systemPromptTokens: 7000,
        schemaTokens: 400,
        wrapperTokens: 100,
      ),
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.contextWindowTooSmall);
  });

  test('лимит тела prompt-only: invalid payloadTooLarge', () {
    final GenerationPlan plan = viaBuilder(
      'Т' * 2000,
      capabilities: caps(maxRequestBytes: 100),
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.payloadTooLarge);
  });

  test('большой заказ prompt-only делится только на партии', () {
    final GenerationPlan plan = viaBuilder(
      '500 фактов о фотосинтезе',
      requested: 500,
      capabilities: caps(maxOutput: 50000, maxCards: 4),
    );
    expect(plan.plannedCards, 500);
    expect(plan.inputPlan!.parts, isEmpty);
    expect(plan.chunks.length, greaterThanOrEqualTo(13));
    expect(plan.chunks.every((PlannedChunk chunk) => chunk.limit <= 4), isTrue);
  });
}
