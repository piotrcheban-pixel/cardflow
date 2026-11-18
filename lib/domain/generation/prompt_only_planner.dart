/// Планировщик генерации без материалов (prompt-only, ADR-024).
///
/// Строит [GenerationPlan] **до** первого API-запроса, когда у пользователя нет
/// ни документов, ни вложений, но есть тема/пожелания. Материалов нет по
/// определению: единицы содержимого не создаются, `<materials>` пуст, тема
/// уходит в `<wishes>`.
///
/// Что учитывает план:
/// - фиксированную обвязку (системный промпт, схема ответа, обёртка);
/// - токены пользовательского запроса (тема/пожелания) в каждом запросе;
/// - бюджет вывода модели: сколько карточек можно получить за один запрос;
/// - необходимое число запросов, если заказ больше потолка одного запроса;
/// - технический предохранитель [GenerationChunkPlannerConfig.maxChunks]:
///   превышение — явная невыполнимость (`tooManyChunks`), а не молчаливый срез;
/// - лимит тела запроса, если возможности модели его задают.
///
/// Никакого искусственного предела «20/25 карточек»: число карточек на запрос
/// считается из `outputCap`, ожидаемого размера карточки и
/// `maxCardsPerRequest`, если модель его объявляет. Домен не зависит от Flutter.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart'
    show GenerationChunkPlannerConfig, GenerationOverheadTokens;
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';

/// Служебный запас тела prompt-only запроса, байт (обёртка/JSON).
///
/// Оценка консервативная: точные байты обёртки зависят от протокола и длины
/// `<limit>`; значение — конфигурация приложения, а не лимит провайдера.
const int kPromptOnlyBodyOverheadBytes = 512;

/// Планировщик prompt-only генерации.
class PromptOnlyPlanner {
  /// Создаёт планировщик.
  const PromptOnlyPlanner({
    this.estimator = const HeuristicContentTokenEstimator(),
    this.config = const GenerationChunkPlannerConfig(),
  });

  /// Оценщик токенов (тот же, что у планировщика материалов).
  final ContentTokenEstimator estimator;

  /// Предохранители (число фрагментов, запас тела).
  final GenerationChunkPlannerConfig config;

  /// Строит план генерации по теме.
  GenerationPlan plan({
    required PromptOnlyRequest request,
    required ModelCapabilities capabilities,
    GenerationOverheadTokens overhead = GenerationOverheadTokens.none,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
  }) {
    final String prompt = request.prompt.trim();
    assert(prompt.isNotEmpty, 'Prompt-only план требует непустую тему');
    final int? requested = request.requestedCards;
    final int promptTokens = math.max(1, estimator.estimateText(prompt));
    final int promptBytes = utf8.encode(prompt).length;
    final int cardsCap = budgetCardsPerRequestCap(capabilities, budgetConfig);
    final int targetCards = math.max(1, requested ?? cardsCap);
    // Безопасное деление вверх: `(a + b - 1) ~/ b` переполняет int на
    // `requestedCards == int.max`; остаток считается отдельно.
    final int chunksByCards = targetCards ~/ cardsCap;
    final int chunkCount =
        chunksByCards + (targetCards % cardsCap == 0 ? 0 : 1);
    final int maxLimit = math.min(cardsCap, targetCards);

    if (chunkCount > config.maxChunks) {
      return _invalid(
        prompt: prompt,
        requestedCards: requested,
        capabilities: capabilities,
        overhead: overhead,
        budgetConfig: budgetConfig,
        reason: PlanInvalidReason.tooManyChunks,
        neededTokens: chunkCount,
        availableTokens: config.maxChunks,
      );
    }

    final GenerationBudget budget = GenerationBudget.compute(
      capabilities: capabilities,
      limit: maxLimit,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      catalogTokens: 0,
      imageTokens: 0,
      config: budgetConfig,
    );
    // Тело запроса проверяется до бюджета: при крошечном maxRequestBytes
    // причина — размер запроса, а не «неизвестное окно».
    final int? maxRequestBytes = capabilities.maxRequestBytes;
    final int bodyBytes = promptBytes + kPromptOnlyBodyOverheadBytes;
    if (maxRequestBytes != null && bodyBytes > maxRequestBytes) {
      return _invalid(
        prompt: prompt,
        requestedCards: requested,
        capabilities: capabilities,
        overhead: overhead,
        budgetConfig: budgetConfig,
        reason: PlanInvalidReason.payloadTooLarge,
        neededTokens: bodyBytes,
        availableTokens: maxRequestBytes,
      );
    }
    if (!budget.isWorkable || promptTokens > budget.inputBudget) {
      return _invalid(
        prompt: prompt,
        requestedCards: requested,
        capabilities: capabilities,
        overhead: overhead,
        budgetConfig: budgetConfig,
        reason: PlanInvalidReason.contextWindowTooSmall,
        neededTokens: promptTokens + overhead.fixedTokens,
        availableTokens: budget.inputBudget + overhead.fixedTokens,
      );
    }

    final List<int> limits = _distribute(targetCards, chunkCount, cardsCap);
    final List<PlannedChunk> chunks = <PlannedChunk>[
      for (var index = 0; index < limits.length; index++)
        PlannedChunk(
          index: index + 1,
          kind: ChunkKind.promptOnly,
          textTokens: promptTokens,
          imageTokens: 0,
          bodyBytes: bodyBytes,
          limit: limits[index],
        ),
    ];
    final List<String> unknown = capabilities.unknownFields;
    final List<PlanWarningCode> warnings = <PlanWarningCode>[
      if (unknown.isNotEmpty) PlanWarningCode.unknownCapabilities,
    ];
    final PlanValidity validity = warnings.isEmpty
        ? const PlanValidity.valid()
        : PlanValidity.warnings(List<PlanWarningCode>.unmodifiable(warnings));
    return GenerationPlan(
      validity: validity,
      estimate: _estimate(
        capabilities: capabilities,
        overhead: overhead,
        budgetConfig: budgetConfig,
        promptTokens: promptTokens,
        chunks: chunks,
      ),
      budget: budget.trace,
      chunks: chunks,
      requestedCards: requested ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
      unknownFields: unknown,
      mode: GenerationMode.promptOnly,
      promptOnlyPrompt: prompt,
    );
  }

  /// Делит [total] карточек по фрагментам без нулей и выше [cap] на запрос.
  List<int> _distribute(int total, int chunks, int cap) {
    final int base = total ~/ chunks;
    final int remainder = total % chunks;
    return <int>[
      for (var index = 0; index < chunks; index++)
        math.max(1, math.min(cap, base + (index < remainder ? 1 : 0))),
    ];
  }

  /// Оценка работы (G.6) по числу запросов prompt-only плана.
  GenerationEstimate _estimate({
    required ModelCapabilities capabilities,
    required GenerationOverheadTokens overhead,
    required GenerationBudgetConfig budgetConfig,
    required int promptTokens,
    required List<PlannedChunk> chunks,
  }) {
    final int outputCap = budgetOutputCapTokens(capabilities, budgetConfig);
    final int requests = chunks.length;
    int reservedOutput = 0;
    for (final PlannedChunk chunk in chunks) {
      reservedOutput += math.min(
        outputCap,
        chunk.limit * budgetConfig.perCardOutputTokens +
            budgetConfig.jsonEnvelopeTokens,
      );
    }
    final int inputText = promptTokens * requests;
    final int fixedPrompt = overhead.systemPromptTokens * requests;
    final int wrapper = overhead.wrapperTokens * requests;
    final int schema = overhead.schemaTokens * requests;
    final int inputTotal = inputText + fixedPrompt + wrapper + schema;
    final int total = inputTotal + reservedOutput;
    final GenerationCost? cost = capabilities.pricing?.costFor(
      inputTokens: inputTotal,
      outputTokens: reservedOutput,
    );
    return GenerationEstimate(
      inputTextTokens: inputText,
      imageTokens: 0,
      fixedPromptTokens: fixedPrompt,
      wrapperTokens: wrapper,
      schemaTokens: schema,
      catalogTokens: 0,
      reservedOutputTokens: reservedOutput,
      expectedOutputTokens: reservedOutput,
      totalTokens: total,
      plannedChunks: requests,
      plannedRequests: requests,
      retryAllowanceRequests: config.retryAllowanceRequests,
      pricingState: capabilities.pricingState,
      estimatorVersion: '${estimator.version}/prompt-only-1',
      inputCost: cost?.input,
      outputCost: cost?.output,
      totalCost: cost?.total,
      currency: cost?.currency,
      unknownFields: capabilities.unknownFields,
      confidence: capabilities.unknownFields.isEmpty ? 1 : 0.5,
    );
  }

  /// Невыполнимый план (без фрагментов) с трассировкой бюджета.
  GenerationPlan _invalid({
    required String prompt,
    required int? requestedCards,
    required ModelCapabilities capabilities,
    required GenerationOverheadTokens overhead,
    required GenerationBudgetConfig budgetConfig,
    required PlanInvalidReason reason,
    required int neededTokens,
    required int availableTokens,
  }) {
    final GenerationBudget budget = GenerationBudget.compute(
      capabilities: capabilities,
      limit: 1,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      catalogTokens: 0,
      imageTokens: 0,
      config: budgetConfig,
    );
    final List<String> unknown = capabilities.unknownFields;
    return GenerationPlan(
      validity: PlanValidity.invalid(
        reason,
        neededTokens: neededTokens,
        availableTokens: availableTokens,
      ),
      estimate: GenerationEstimate(
        inputTextTokens: 0,
        imageTokens: 0,
        fixedPromptTokens: overhead.systemPromptTokens,
        wrapperTokens: overhead.wrapperTokens,
        schemaTokens: overhead.schemaTokens,
        catalogTokens: 0,
        reservedOutputTokens: 0,
        expectedOutputTokens: 0,
        totalTokens: overhead.fixedTokens,
        plannedChunks: 0,
        plannedRequests: 0,
        retryAllowanceRequests: config.retryAllowanceRequests,
        pricingState: capabilities.pricingState,
        estimatorVersion: '${estimator.version}/prompt-only-1',
        unknownFields: unknown,
      ),
      budget: budget.trace,
      requestedCards: requestedCards ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
      unknownFields: unknown,
      mode: GenerationMode.promptOnly,
      promptOnlyPrompt: prompt,
    );
  }
}
