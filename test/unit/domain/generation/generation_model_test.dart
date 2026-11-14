import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_model.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';

/// Итерация 7.5 (ADR-020): бюджеты входа по контексту модели аккаунта.
///
/// Каталог моделей переехал в провайдеры (`provider_preset.dart`): контекст
/// берётся из аккаунта, а здесь остаются резервы и формула.
void main() {
  test('у каждой модели каталога положительный контекст', () {
    for (final ProviderPreset preset in kProviderPresets) {
      expect(preset.models, isNotEmpty, reason: 'нет моделей для ${preset.id}');
      for (final ProviderPresetModel model in preset.models) {
        expect(model.contextTokens, greaterThan(0), reason: preset.id);
      }
    }
  });

  test('id моделей уникальны внутри пресета', () {
    for (final ProviderPreset preset in kProviderPresets) {
      final List<String> ids = preset.models
          .map((ProviderPresetModel model) => model.id)
          .toList();
      expect(ids.toSet().length, ids.length, reason: preset.id);
    }
  });

  test('аккаунт из пресета несёт контекст выбранной модели', () {
    final ProviderAccount account = ProviderAccount.fromPreset(
      providerPresetById('openai')!,
      id: 'openai',
      modelId: 'gpt-4o',
    );
    expect(account.contextTokens, 128000);
    expect(
      ProviderAccount.fromPreset(
        providerPresetById('gemini')!,
        id: 'gemini',
        modelId: 'gemini-2.5-flash',
      ).contextTokens,
      1048576,
    );
  });

  test('бюджет входа: контекст − ответ − промпт − обёртка', () {
    final int budget = inputTokenBudget(
      contextTokens: 128000,
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
    expect(
      inputTokenBudget(contextTokens: 200000, systemPromptTokens: 500000),
      kMinInputTokenBudget,
    );
  });

  test('неизвестный контекст — консервативный бюджет 8000', () {
    expect(
      inputTokenBudget(contextTokens: 0, systemPromptTokens: 5000),
      kFallbackInputTokenBudget,
    );
  });

  test('пользовательский провайдер — консервативный контекст', () {
    expect(kCustomProviderContextTokens, kCompatibleInputTokenBudget);
  });
}
