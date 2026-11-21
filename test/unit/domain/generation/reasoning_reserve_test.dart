import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/model_limits_resolver.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// §3.4: «У reasoning-моделей калибровка сама учитывает токены рассуждения; до
/// замеров добавляется явный резерв на рассуждение (`assumption`)».
///
/// Дефект до фикса: `isReasoningModel` доезжал из discovery до `ModelLimits`, но
/// терялся в проекции `ModelCapabilities` и не влиял на `max_tokens` — резерв
/// вывода расходовался рассуждением, и партия карточек обрезалась.
void main() {
  const GenerationPlanningConfig config = GenerationPlanningConfig();

  /// Ожидаемый резерв рассуждения (допущение приложения, §3.4).
  const int expectedReserve = 2048;

  ProviderAccount account() => const ProviderAccount(
    id: 'reasoner',
    label: 'Reasoner',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.example.com/v1',
    modelId: 'reasoner-1',
    requiresApiKey: true,
  );

  ModelCapabilityRecord cachedRecord({bool reasoning = true}) {
    final ModelLimits limits = ModelLimits(
      contextTokens: const Sourced<int>(
        128000,
        source: CapabilitySource.providerApi,
        sourceRef: 'https://api.example.com/v1/models',
      ),
      maxOutputTokens: const Sourced<int>(
        8192,
        source: CapabilitySource.providerApi,
        sourceRef: 'https://api.example.com/v1/models',
      ),
      isReasoningModel: Sourced<bool>(
        reasoning,
        source: CapabilitySource.providerApi,
        sourceRef: 'https://api.example.com/v1/models',
      ),
    );
    return ModelCapabilityRecord(
      accountId: 'reasoner',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'https://api.example.com/v1',
      model: 'reasoner-1',
      fetchedAt: DateTime.utc(2026, 11, 21),
      limits: limits,
    );
  }

  ModelCapabilities capabilitiesFor({bool reasoning = true}) =>
      modelCapabilitiesFromLimits(
        resolveModelLimits(
          account: account(),
          cached: cachedRecord(reasoning: reasoning),
        ),
      );

  /// Материал с большой ёмкостью: 1200 понятий (≈7200 слов) — заказ 100
  /// карточек распределяется полностью.
  String material() => List<String>.generate(
    1200,
    (int index) => 'Понятие$index определяется как процесс$index.',
  ).join(' ');

  ParsedDocument docOf(String text) => ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'a.txt',
    text: text,
    sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
  );

  GenerationPlan planFor({
    required ModelCapabilities capabilities,
    int requestedCards = 100,
    GenerationPlanBuilder builder = const GenerationPlanBuilder(),
  }) => builder.build(
    documents: <ParsedDocument>[docOf(material())],
    capabilities: capabilities,
    requestedCards: requestedCards,
  );

  int largestBatch(GenerationPlan plan) => plan.chunks
      .map((PlannedChunk chunk) => chunk.limit)
      .reduce((int a, int b) => a > b ? a : b);

  /// Сбалансированный размер партии при [total] карточках и [perBatch].
  int balancedLargest(int total, int perBatch) {
    final int count = (total / perBatch).ceil();
    return (total / count).ceil();
  }

  test('признак reasoning-модели известен домену (источник API)', () {
    final ModelLimits limits = resolveModelLimits(
      account: account(),
      cached: cachedRecord(),
    );
    expect(limits.isReasoningModel.value, isTrue);
    expect(limits.isReasoningModel.source, CapabilitySource.providerApi);
  });

  test('резерв рассуждения вычитается из карточек партии', () {
    final GenerationPlan plan = planFor(
      capabilities: capabilitiesFor(),
      requestedCards: 20,
    );
    final int maxTokens = plan.inputPlan!.maxTokens;
    final int order = plan.chunks.fold<int>(
      0,
      (int sum, PlannedChunk chunk) => sum + chunk.limit,
    );
    final int perBatch = largestBatch(plan);
    expect(
      config.tokensFor(perBatch) + expectedReserve,
      lessThanOrEqualTo(maxTokens),
      reason:
          'карточки партии + рассуждение обязаны помещаться в max_tokens '
          '(maxTokens=$maxTokens, limit=$perBatch)',
    );
    expect(
      perBatch,
      balancedLargest(order, config.cardsFor(maxTokens - expectedReserve)),
      reason: 'ёмкость партии считается от остатка после резерва',
    );
  });

  test('обычная модель планируется без резерва (нет регрессии)', () {
    final GenerationPlan plan = planFor(
      capabilities: capabilitiesFor(reasoning: false),
      requestedCards: 20,
    );
    final int maxTokens = plan.inputPlan!.maxTokens;
    final int order = plan.chunks.fold<int>(
      0,
      (int sum, PlannedChunk chunk) => sum + chunk.limit,
    );
    expect(
      largestBatch(plan),
      balancedLargest(order, config.cardsFor(maxTokens)),
      reason: 'без reasoning-признака ёмкость партии прежняя',
    );
  });

  test('желаемый вывод reasoning-модели включает резерв', () {
    final GenerationPlan plan = planFor(
      capabilities: capabilitiesFor(),
      requestedCards: 5,
    );
    expect(
      plan.inputPlan!.maxTokens,
      config.tokensFor(5) + expectedReserve,
      reason: 'на initial-этапе max_tokens = карточки + рассуждение',
    );
  });

  test('калибровка снимает резерв: факт `usage` уже включает рассуждение', () {
    final TokenCalibration calibration = TokenCalibration(
      accountId: 'reasoner',
      model: 'reasoner-1',
      tokensPerCard: 450,
      samples: 3,
      updatedAt: DateTime.utc(2026, 11, 21),
    );
    final GenerationPlan plan = planFor(
      capabilities: capabilitiesFor(),
      requestedCards: 15,
      builder: generationPlanBuilderFor(calibration),
    );
    final GenerationPlanningConfig calibrated = config.copyWith(
      tokensPerCard: 450,
    );
    expect(
      plan.inputPlan!.maxTokens,
      calibrated.tokensFor(15),
      reason: 'с калибровкой отдельный резерв не добавляется',
    );
    expect(largestBatch(plan), 15);
  });
}
