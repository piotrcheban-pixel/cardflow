/// Бюджеты входа для генерации (SPEC A6.8, ADR-015, ADR-020).
///
/// Каталог моделей живёт в провайдерах (`provider_preset.dart`): у каждого
/// аккаунта есть окно контекста выбранной модели ([ProviderAccount.contextTokens]),
/// поэтому здесь остаются только резервы и формула бюджета.
library;

/// Резерв токенов под ответ модели (`max_output_tokens` 3b).
const int kGenerationOutputTokenReserve = 8192;

/// Консервативный бюджет входа для пользовательского провайдера (ADR-013):
/// контекст неизвестен, точного значения нет.
const int kCompatibleInputTokenBudget = 16000;

/// Бюджет входа, если контекст модели неизвестен.
const int kFallbackInputTokenBudget = 8000;

/// Минимальный бюджет входа на фрагмент.
const int kMinInputTokenBudget = 2000;

/// Запас бюджета на обёртку сообщения (`<materials>`, `<wishes>`, `<limit>`).
const int kPromptWrapperTokenReserve = 512;

/// Бюджет токенов входа на один фрагмент.
///
/// [contextTokens] — окно контекста модели аккаунта; [systemPromptTokens] —
/// оценка системного промпта в токенах.
int inputTokenBudget({
  required int contextTokens,
  required int systemPromptTokens,
}) {
  if (contextTokens <= 0) return kFallbackInputTokenBudget;
  final int budget =
      contextTokens -
      kGenerationOutputTokenReserve -
      systemPromptTokens -
      kPromptWrapperTokenReserve;
  return budget < kMinInputTokenBudget ? kMinInputTokenBudget : budget;
}
