/// Узкий контракт вызова модели на понимание фрагмента (этап Understanding,
/// TASK «Срез 3»).
///
/// Аналогичен `GenerationCaller` (ADR-015): этап не зависит от адаптеров, HTTP
/// и ключей. Ошибки — `GenerationException` (домен): сервис понимания не видит
/// HTTP-коды и тела ответов провайдера.
library;

import 'package:cardflow/domain/generation/generation_result.dart';

/// Запрос понимания одного фрагмента материала.
class KnowledgeMapRequest {
  /// Создаёт запрос.
  const KnowledgeMapRequest({
    required this.fragmentId,
    required this.sectionId,
    required this.promptVersion,
    required this.systemPrompt,
    required this.userContent,
    this.maxOutputTokens,
  });

  /// id фрагмента: раздел `ContentModel` (`doc:<файл>#<раздел>`).
  final String fragmentId;

  /// id раздела, к которому относятся единицы фрагмента.
  final String sectionId;

  /// Версия системного промпта (`gen-map-v1`).
  final String promptVersion;

  /// Системный промпт понимания (скрыт от пользователя).
  final String systemPrompt;

  /// Пользовательское сообщение: раздел и блоки с id.
  final String userContent;

  /// Лимит вывода запроса (`max_tokens`); `null` — лимит реализации.
  ///
  /// По этому лимиту Understanding делит обрезанный ответ на части **целыми
  /// блоками раздела**, а не пополам (TASK «Срез 11», п. 5).
  final int? maxOutputTokens;

  @override
  String toString() => 'KnowledgeMapRequest($fragmentId, $promptVersion)';
}

/// Ответ модели на запрос понимания после проверки причины остановки.
class KnowledgeMapRawResponse {
  /// Создаёт ответ.
  const KnowledgeMapRawResponse({
    required this.json,
    this.usage = const TokenUsage(),
    this.truncated = false,
    this.attempts = 1,
  });

  /// JSON-строка с ответом модели по канонической схеме `gen-map-v1`.
  final String json;

  /// Фактический расход токенов из ответа (если провайдер сообщил).
  final TokenUsage usage;

  /// Ответ оборван по лимиту вывода — карта фрагмента непригодна целиком.
  final bool truncated;

  /// Сколько HTTP-обменов стоил ответ (ступени лестницы ADR-021 и повторы).
  ///
  /// Успех без упрощений — 1; отказ strict-схемы — 2 и больше. Отчёт
  /// Understanding складывает это число, а не считает «один вызов на раздел»
  /// (срез 13): иначе цена лестницы не видна.
  final int attempts;

  @override
  String toString() =>
      'KnowledgeMapRawResponse(${json.length} симв., truncated: $truncated, '
      'attempts: $attempts)';
}

/// Вызов модели на понимание фрагмента.
abstract interface class KnowledgeMapCaller {
  /// Возвращает сырой ответ модели; ошибки — [GenerationException].
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request);
}
