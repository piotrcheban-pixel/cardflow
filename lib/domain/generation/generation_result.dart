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
    this.rejectedCards = 0,
    this.estimatedInputTokens,
    this.estimatedOutputTokens,
    this.estimatorVersion,
    this.sentDocumentImageIds = const <String>[],
    this.skippedDocumentImageIds = const <String>[],
    this.sourceExhausted = false,
    this.requestBytes,
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

  /// Сколько карточек отброшено поштучно (схема/структура), fix-gen Д6.
  final int rejectedCards;

  /// Оценка входа по фактически собранному запросу (TASK 03), эвристика.
  ///
  /// `null` — исполнитель не считал (старый путь/тест). Это **не** факт:
  /// фактический расход — [usage].
  final int? estimatedInputTokens;

  /// Бюджетный резерв вывода, отправленный в запросе (`max_tokens`).
  final int? estimatedOutputTokens;

  /// Версия оценщика, которой посчитан [estimatedInputTokens].
  final String? estimatorVersion;

  /// id изображений документов, реально вошедших image-частями в запрос.
  final List<String> sentDocumentImageIds;

  /// id изображений, исключённых исполнителем (сверх плана) по лимитам.
  final List<String> skippedDocumentImageIds;

  /// Модель сообщила, что материал focus исчерпан (`source_exhausted`, v8).
  final bool sourceExhausted;

  /// Фактический размер сериализованного тела запроса, байт (§3.4).
  ///
  /// Это **измерение** готового payload после адаптера (UTF-8 JSON), а не
  /// оценка плана: по нему проверяется `maxRequestBytes`.
  final int? requestBytes;

  @override
  String toString() =>
      'GenerationResult(provider: ${provider.wireName}, model: $model, '
      'cards: ${cards.length}, rejected: $rejectedCards, '
      'promptVersion: $promptVersion)';
}
