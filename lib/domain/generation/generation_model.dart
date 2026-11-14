/// Каталог моделей и бюджеты входа для генерации (SPEC A6.8, ADR-015).
///
/// Список моделей — данные приложения, а не вызов API: для встроенных
/// провайдеров он статический, для OpenAI-совместимого сервера модели нет
/// (ADR-013: модель берётся из настроек).
library;

import 'package:cardflow/domain/generation/generation_provider.dart';

/// Резерв токенов под ответ модели (`max_output_tokens` 3b).
const int kGenerationOutputTokenReserve = 8192;

/// Консервативный бюджет входа для OpenAI-совместимого сервера (ADR-013):
/// контекст локальных моделей обычно 8k–32k, точного значения нет.
const int kCompatibleInputTokenBudget = 16000;

/// Бюджет входа, если модель не найдена в каталоге.
const int kFallbackInputTokenBudget = 8000;

/// Минимальный бюджет входа на фрагмент.
const int kMinInputTokenBudget = 2000;

/// Запас бюджета на обёртку сообщения (`<materials>`, `<wishes>`, `<limit>`).
const int kPromptWrapperTokenReserve = 512;

/// Описание модели провайдера для селектора и нарезки.
class GenerationModel {
  /// Создаёт описание модели.
  const GenerationModel({
    required this.id,
    required this.label,
    required this.provider,
    required this.contextTokens,
  });

  /// Идентификатор модели в запросе провайдеру.
  final String id;

  /// Отображаемое имя (бренд/модель, латиница допустима).
  final String label;

  /// Провайдер модели.
  final GenerationProvider provider;

  /// Окно контекста модели, токенов.
  final int contextTokens;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GenerationModel &&
          other.id == id &&
          other.label == label &&
          other.provider == provider &&
          other.contextTokens == contextTokens;

  @override
  int get hashCode => Object.hash(id, label, provider, contextTokens);

  @override
  String toString() => 'GenerationModel(${provider.wireName}/$id)';
}

/// Статический каталог моделей MVP.
const List<GenerationModel> kGenerationModels = <GenerationModel>[
  GenerationModel(
    id: 'gpt-4o-mini',
    label: 'GPT-4o mini',
    provider: GenerationProvider.openai,
    contextTokens: 128000,
  ),
  GenerationModel(
    id: 'gpt-4o',
    label: 'GPT-4o',
    provider: GenerationProvider.openai,
    contextTokens: 128000,
  ),
  GenerationModel(
    id: 'gemini-2.0-flash',
    label: 'Gemini 2.0 Flash',
    provider: GenerationProvider.gemini,
    contextTokens: 1048576,
  ),
  GenerationModel(
    id: 'gemini-2.5-flash',
    label: 'Gemini 2.5 Flash',
    provider: GenerationProvider.gemini,
    contextTokens: 1048576,
  ),
  GenerationModel(
    id: 'claude-3-5-haiku-latest',
    label: 'Claude 3.5 Haiku',
    provider: GenerationProvider.anthropic,
    contextTokens: 200000,
  ),
  GenerationModel(
    id: 'claude-3-5-sonnet-latest',
    label: 'Claude 3.5 Sonnet',
    provider: GenerationProvider.anthropic,
    contextTokens: 200000,
  ),
];

/// Модели провайдера для селектора; у OpenAI-совместимого — пусто (ADR-013).
List<GenerationModel> generationModelsFor(GenerationProvider provider) {
  return kGenerationModels
      .where((GenerationModel model) => model.provider == provider)
      .toList(growable: false);
}

/// Модель по id или `null`.
GenerationModel? generationModelById(
  GenerationProvider provider,
  String modelId,
) {
  for (final model in kGenerationModels) {
    if (model.provider == provider && model.id == modelId) return model;
  }
  return null;
}

/// Бюджет токенов входа на один фрагмент.
///
/// [systemPromptTokens] — оценка системного промпта в токенах.
int inputTokenBudget({
  required GenerationProvider provider,
  required String modelId,
  required int systemPromptTokens,
}) {
  if (provider == GenerationProvider.openaiCompatible) {
    return kCompatibleInputTokenBudget;
  }
  final GenerationModel? model = generationModelById(provider, modelId);
  if (model == null) {
    // Бюджет неизвестной модели — сам бюджет входа (ADR-015 §1), а не
    // «контекст», из которого повторно вычитался бы резерв ответа.
    return kFallbackInputTokenBudget;
  }
  final int budget =
      model.contextTokens -
      kGenerationOutputTokenReserve -
      systemPromptTokens -
      kPromptWrapperTokenReserve;
  return budget < kMinInputTokenBudget ? kMinInputTokenBudget : budget;
}
