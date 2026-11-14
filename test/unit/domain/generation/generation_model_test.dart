import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_model.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

void main() {
  test('каталог моделей: у трёх встроенных провайдеров есть модели', () {
    for (final provider in <GenerationProvider>[
      GenerationProvider.openai,
      GenerationProvider.gemini,
      GenerationProvider.anthropic,
    ]) {
      expect(
        generationModelsFor(provider),
        isNotEmpty,
        reason: 'нет моделей для ${provider.wireName}',
      );
    }
  });

  test('у OpenAI-совместимого сервера списка моделей нет (ADR-013)', () {
    expect(generationModelsFor(GenerationProvider.openaiCompatible), isEmpty);
  });

  test('id моделей уникальны внутри провайдера', () {
    for (final provider in GenerationProvider.values) {
      final ids = generationModelsFor(provider)
          .map((model) => model.id)
          .toList();
      expect(ids.toSet().length, ids.length);
    }
  });

  test('generationModelById находит модель и возвращает null на чужой', () {
    expect(
      generationModelById(GenerationProvider.openai, 'gpt-4o')?.label,
      'GPT-4o',
    );
    expect(
      generationModelById(GenerationProvider.openai, 'gemini-2.0-flash'),
      isNull,
    );
    expect(generationModelById(GenerationProvider.openai, 'нет-такой'), isNull);
  });

  test('бюджет входа: контекст − ответ − промпт − обёртка', () {
    final int budget = inputTokenBudget(
      provider: GenerationProvider.openai,
      modelId: 'gpt-4o',
      systemPromptTokens: 1000,
    );
    expect(
      budget,
      128000 -
          kGenerationOutputTokenReserve -
          1000 -
          kPromptWrapperTokenReserve,
    );
  });

  test('бюджет входа не опускается ниже минимума', () {
    final int budget = inputTokenBudget(
      provider: GenerationProvider.anthropic,
      modelId: 'claude-3-5-haiku-latest',
      systemPromptTokens: 500000,
    );
    expect(budget, kMinInputTokenBudget);
  });

  test('OpenAI-совместимый сервер — консервативный бюджет', () {
    expect(
      inputTokenBudget(
        provider: GenerationProvider.openaiCompatible,
        modelId: 'любая',
        systemPromptTokens: 1000,
      ),
      kCompatibleInputTokenBudget,
    );
  });
}
