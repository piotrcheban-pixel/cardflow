/// Ошибки слоя генерации карточек (SPEC A8.6).
///
/// Наружу (в UI) попадает только код, который маппится в строку ARB; [details]
/// предназначены для журналов/тестов и не показываются пользователю.
library;

/// Коды ошибок генерации.
enum GenerationErrorCode {
  /// Ключ API не задан в настройках.
  missingApiKey,

  /// OpenAI-совместимый сервер не настроен: нет адреса или модели (ADR-013).
  providerNotConfigured,

  /// Провайдер отверг ключ (HTTP 401/403).
  invalidApiKey,

  /// Запрос отвергнут (HTTP 400/404/422 и прочие 4xx кроме 429).
  badRequest,

  /// Лимит запросов (HTTP 429) после всех попыток.
  rateLimited,

  /// Ошибка на стороне провайдера (HTTP 5xx) после всех попыток.
  serverUnavailable,

  /// Таймаут соединения/отправки/приёма.
  timeout,

  /// Нет сети / обрыв соединения.
  network,

  /// Запрос отменён пользователем.
  cancelled,

  /// Модель вернула пустой контент.
  emptyResponse,

  /// Ответ обрезан по лимиту токенов (итерация 3c дробит фрагмент).
  truncated,

  /// Отказ модели или safety-фильтр.
  refused,

  /// Невалидный ответ: не JSON, не соответствует схеме, нет `tool_use`.
  invalidResponse,
}

/// Исключение слоя генерации.
class GenerationException implements Exception {
  /// Создаёт исключение с кодом [code].
  const GenerationException(this.code, {this.retryAfter, this.details});

  /// Код ошибки для маппинга в ARB.
  final GenerationErrorCode code;

  /// Пауза из `Retry-After` (для кода `rateLimited`), если была.
  final Duration? retryAfter;

  /// Диагностическая информация (не показывается пользователю, без ключей/материалов).
  final String? details;

  @override
  String toString() =>
      'GenerationException(${code.name}${details == null ? '' : ': $details'})';
}
