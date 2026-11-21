import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/model_limits.dart';

/// Итерация 7.18.3 §3: число провайдера, оценка, резерв и плановый бюджет —
/// разные величины. «Точный» бюджет нельзя выдавать за результат `count_tokens`.
void main() {
  ModelLimits limits({int context = 128000, int output = 8192}) => ModelLimits(
    contextTokens: Sourced<int>(
      context,
      source: CapabilitySource.userConfigured,
    ),
    maxOutputTokens: Sourced<int>(
      output,
      source: CapabilitySource.userConfigured,
    ),
  );

  test('exact: native отдельно, запас 3 %, бюджет = native + запас', () {
    final RequestBudget budget = RequestBudget.compute(
      limits: limits(),
      fixedTokens: 3000,
      materialTokens: 5000,
      desiredOutputTokens: 2000,
      nativeCount: const NativeInputCount(
        tokens: 1000,
        source: 'count_tokens:anthropic-messages',
      ),
    );
    expect(budget.accuracy, InputAccuracy.exact);
    expect(budget.nativeInputTokens, 1000);
    expect(budget.estimatedExtraTokens, 0);
    expect(budget.marginTokens, 30, reason: '3 % от 1000, а не от бюджета');
    expect(budget.effectiveBudgetTokens, 1030);
    expect(
      budget.effectiveBudgetTokens,
      isNot(budget.nativeInputTokens),
      reason: 'резерв не выдаётся за результат провайдера',
    );
  });

  test('mixed: native + оценённая схема → не exact, запас 10 %', () {
    final RequestBudget budget = RequestBudget.compute(
      limits: limits(),
      fixedTokens: 3000,
      materialTokens: 5000,
      desiredOutputTokens: 2000,
      nativeCount: const NativeInputCount(
        tokens: 1000,
        estimatedExtraTokens: 300,
        estimatedComponents: <String>['response_schema'],
        source: 'count_tokens:gemini-generate-content',
      ),
    );
    expect(
      budget.accuracy,
      InputAccuracy.estimated,
      reason: 'часть входа оценена — «точный» результат запрещён',
    );
    expect(budget.nativeInputTokens, 1000);
    expect(budget.estimatedExtraTokens, 300);
    expect(budget.estimatedComponents, <String>['response_schema']);
    expect(budget.marginTokens, 130, reason: '10 % от (1000 + 300)');
    expect(budget.effectiveBudgetTokens, 1430);
  });

  test('без нативного подсчёта: оценка P+D и запас 10 %', () {
    final RequestBudget budget = RequestBudget.compute(
      limits: limits(),
      fixedTokens: 3000,
      materialTokens: 3000,
      desiredOutputTokens: 2000,
    );
    expect(budget.accuracy, InputAccuracy.estimated);
    expect(budget.nativeInputTokens, isNull);
    expect(budget.estimatedExtraTokens, 0);
    expect(budget.marginTokens, 600);
    expect(budget.effectiveBudgetTokens, 6600);
  });

  test('estimate остаётся estimate, даже если задан countedInputTokens', () {
    final RequestBudget budget = RequestBudget.compute(
      limits: limits(),
      fixedTokens: 1,
      materialTokens: 1,
      desiredOutputTokens: 100,
      countedInputTokens: 2000,
    );
    expect(budget.accuracy, InputAccuracy.estimated);
    expect(budget.nativeInputTokens, 2000);
    expect(budget.marginTokens, 200, reason: '10 % — это оценка, не exact');
    expect(budget.effectiveBudgetTokens, 2200);
  });

  test('коэффициенты запаса не менялись: 3 % exact, 10 % estimate', () {
    const GenerationPlanningConfig config = GenerationPlanningConfig();
    expect(config.margin(exact: true), closeTo(0.03, 1e-9));
    expect(config.margin(exact: false), closeTo(0.10, 1e-9));
  });
}
