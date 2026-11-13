/// Результат генерации карточек (SPEC A8.5 шаг 7, A8.6 счётчик токенов).
library;

import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

/// Расход токенов провайдером (факт после ответа; оценка до — итерация 3c).
class TokenUsage {
  /// Создаёт расход; неизвестные поля — `null`.
  const TokenUsage({
    this.promptTokens,
    this.completionTokens,
    this.totalTokens,
  });

  /// Токены запроса (материалы + системный промпт).
  final int? promptTokens;

  /// Токены ответа модели.
  final int? completionTokens;

  /// Всего токенов, если провайдер сообщает.
  final int? totalTokens;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenUsage &&
          other.promptTokens == promptTokens &&
          other.completionTokens == completionTokens &&
          other.totalTokens == totalTokens;

  @override
  int get hashCode => Object.hash(promptTokens, completionTokens, totalTokens);

  @override
  String toString() =>
      'TokenUsage(prompt: $promptTokens, completion: $completionTokens, '
      'total: $totalTokens)';
}

/// Результат одного вызова модели: карточки, пометки и расход.
class GenerationResult {
  /// Создаёт результат.
  const GenerationResult({
    required this.provider,
    required this.model,
    required this.promptVersion,
    required this.cards,
    required this.usage,
  });

  /// Провайдер ответа.
  final GenerationProvider provider;

  /// Модель ответа.
  final String model;

  /// Версия встроенного системного промпта (`generation_jobs.prompt_version`).
  final String promptVersion;

  /// Карточки в порядке ответа модели (с пометками качества A8.4).
  final List<GeneratedCard> cards;

  /// Фактический расход токенов (если провайдер вернул).
  final TokenUsage usage;

  @override
  String toString() =>
      'GenerationResult(provider: ${provider.wireName}, model: $model, '
      'cards: ${cards.length}, promptVersion: $promptVersion)';
}
