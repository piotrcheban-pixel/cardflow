import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_card_limit.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_planner.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';

/// TASK 02B-FINAL: prompt-only планы без фиктивных материалов.
void main() {
  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 1000,
    schemaTokens: 200,
    wrapperTokens: 100,
  );

  ModelCapabilities caps({
    int? context = 128000,
    int? maxOutput,
    int? maxCards,
    int? maxRequestBytes,
    CapabilitySource source = CapabilitySource.preset,
  }) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: context == null ? CapabilitySource.unknown : source,
      maxOutputTokens: maxOutput,
      maxCardsPerRequest: maxCards,
      maxRequestBytes: maxRequestBytes,
    );
  }

  GenerationPlan planWith(
    String prompt, {
    int? requestedCards,
    ModelCapabilities? capabilities,
    GenerationOverheadTokens overheadTokens = overhead,
    GenerationChunkPlannerConfig config = const GenerationChunkPlannerConfig(),
  }) {
    return PromptOnlyPlanner(config: config).plan(
      request: PromptOnlyRequest(
        prompt: prompt,
        requestedCards: requestedCards,
      ),
      capabilities: capabilities ?? caps(),
      overhead: overheadTokens,
    );
  }

  test('тема без файлов: один фрагмент без единиц материалов', () {
    final GenerationPlan plan = planWith('Фотосинтез');
    expect(plan.isPromptOnly, isTrue);
    expect(plan.mode, GenerationMode.promptOnly);
    expect(plan.promptOnlyPrompt, 'Фотосинтез');
    expect(plan.validity.isInvalid, isFalse);
    expect(plan.chunks, hasLength(1));
    final PlannedChunk chunk = plan.chunks.single;
    expect(chunk.isPromptOnly, isTrue);
    expect(chunk.kind, ChunkKind.promptOnly);
    expect(chunk.units, isEmpty);
    expect(chunk.imageParts, isEmpty);
    expect(chunk.catalogOnly, isEmpty);
    expect(chunk.attachments, isEmpty);
    expect(chunk.materialsText, isEmpty);
    expect(chunk.limit, greaterThanOrEqualTo(1));
  });

  test('тема с пожеланиями и явным числом карточек: ровно заказ', () {
    final GenerationPlan plan = planWith(
      'Создай карточки по истории Древнего Рима, от простого к сложному',
      requestedCards: 20,
      capabilities: caps(maxOutput: 50000),
    );
    expect(plan.requestedCards, 20);
    expect(plan.plannedCards, 20);
    expect(plan.achievableCards, 20);
    expect(plan.chunks, hasLength(1));
  });

  test('большой заказ: несколько запросов, сумма равна заказу', () {
    final GenerationPlan plan = planWith(
      '500 фактов о фотосинтезе',
      requestedCards: 500,
      capabilities: caps(maxOutput: 50000),
    );
    expect(plan.requestedCards, 500);
    expect(plan.chunks.length, greaterThan(1));
    expect(plan.plannedCards, 500);
    final int cap = budgetCardsPerRequestCap(caps(maxOutput: 50000));
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.limit, greaterThanOrEqualTo(1));
      expect(chunk.limit, lessThanOrEqualTo(cap));
    }
  });

  test('недостаточный бюджет: план invalid, а не «всё равно 2000»', () {
    final GenerationPlan plan = planWith(
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
    expect(plan.chunks, isEmpty);
  });

  test('неизвестное окно модели: консервативный потолок с пометкой', () {
    final GenerationPlan plan = planWith(
      'Тема',
      capabilities: caps(context: null),
    );
    expect(plan.validity.isInvalid, isFalse);
    expect(plan.budget.source, BudgetSource.assumption);
    expect(
      plan.unknownFields,
      contains(ModelCapabilities.unknownContextWindow),
    );
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.unknownCapabilities),
    );
    expect(plan.chunks, isNotEmpty);
    expect(plan.chunks.every((PlannedChunk chunk) => chunk.limit >= 1), isTrue);
  });

  test('слишком много запросов: явная невыполнимость, а не срез заказа', () {
    final GenerationPlan plan = planWith(
      'Огромная тема',
      requestedCards: 100000,
      capabilities: caps(maxOutput: 50000),
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.tooManyChunks);
    expect(plan.requestedCards, 100000, reason: 'заказ не подменяется');
    expect(plan.chunks, isEmpty);
  });

  test('int.max заказ: без переполнения, invalid tooManyChunks', () {
    final GenerationPlan plan = planWith(
      'Огромная тема',
      requestedCards: kMaxRepresentableRequestedCards,
      capabilities: caps(maxOutput: 50000),
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.tooManyChunks);
    expect(plan.requestedCards, kMaxRepresentableRequestedCards);
  });

  test('лимит тела запроса: invalid payloadTooLarge', () {
    final GenerationPlan plan = planWith(
      'Т' * 2000,
      capabilities: caps(maxRequestBytes: 100),
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.payloadTooLarge);
  });

  test('builder считает токены темы один раз (без двойного счёта)', () {
    final GenerationPlanBuilder builder = GenerationPlanBuilder();
    final GenerationPlan plan = builder.buildPromptOnly(
      request: const PromptOnlyRequest(
        prompt: 'Тема запроса',
        requestedCards: 10,
      ),
      capabilities: caps(maxOutput: 50000),
      overhead: overhead,
    );
    expect(plan.chunks.single.textTokens, greaterThan(0));
    expect(
      plan.estimate.inputTextTokens,
      plan.chunks.single.textTokens * plan.chunks.length,
    );
    expect(plan.isPromptOnly, isTrue);
  });

  test('лимит модели maxCardsPerRequest режет число запросов на карточку', () {
    final GenerationPlan plan = planWith(
      'Тема',
      requestedCards: 50,
      capabilities: caps(maxOutput: 50000, maxCards: 4),
    );
    expect(plan.plannedCards, 50);
    for (final PlannedChunk chunk in plan.chunks) {
      expect(chunk.limit, lessThanOrEqualTo(4));
    }
    expect(plan.chunks.length, greaterThanOrEqualTo(13));
  });
}
