/// Политика повторов HTTP-запросов генерации (SPEC A8.6).
///
/// Число попыток, задержки и классификация ошибок — в ADR-012 §1. Политика
/// чистая и детерминируемая (инжектируемые jitter/now) — покрывается unit-тестами.
library;

/// Решение о повторе после неудачной попытки.
class RetryDecision {
  /// Повторить через [delay].
  const RetryDecision.retry(this.delay) : shouldRetry = true;

  /// Не повторять (ошибка терминальна).
  const RetryDecision.giveUp() : shouldRetry = false, delay = Duration.zero;

  /// Нужно ли повторить запрос.
  final bool shouldRetry;

  /// Пауза перед повтором.
  final Duration delay;

  @override
  String toString() =>
      'RetryDecision(shouldRetry: $shouldRetry, delay: $delay)';
}

/// Разбирает заголовок `Retry-After` (RFC 9110): число секунд или HTTP-date.
///
/// Возвращает `null`, если заголовок отсутствует/невалиден; отрицательное
/// значение приводится к нулю.
Duration? parseRetryAfter(String? headerValue, {DateTime Function()? now}) {
  throw UnimplementedError('parseRetryAfter');
}

/// Политика повторов (SPEC A8.6, ADR-012 §1).
class RetryPolicy {
  /// Создаёт политику.
  ///
  /// [maxAttempts] — всего попыток (по умолчанию 4: 1 + 3 повтора).
  /// [baseDelay]/[maxDelay] — экспоненциальный backoff с full jitter.
  /// [maxRetryAfter] — если `Retry-After` больше, автоматический повтор не
  /// выполняется (пользователь увидит «Повтор через N секунд» и повторит сам).
  RetryPolicy({
    this.maxAttempts = 4,
    this.baseDelay = const Duration(seconds: 1),
    this.maxDelay = const Duration(seconds: 30),
    this.maxRetryAfter = const Duration(seconds: 60),
    double Function()? jitter,
  }) : jitter = jitter ?? _defaultJitter;

  /// Всего попыток.
  final int maxAttempts;

  /// Базовая задержка backoff.
  final Duration baseDelay;

  /// Верхняя граница backoff.
  final Duration maxDelay;

  /// Максимальный `Retry-After`, при котором выполняется автоматический повтор.
  final Duration maxRetryAfter;

  /// Источник jitter (по умолчанию равномерное [0, 1)).
  final double Function() jitter;

  /// Решает, повторять ли запрос после неудачной попытки [attempt] (1-based).
  ///
  /// [statusCode] — HTTP-статус, если ответ получен; [isTimeout] и
  /// [isConnectionError] — транспортные ошибки; [retryAfter] — разобранный
  /// заголовок `Retry-After`.
  RetryDecision decide({
    required int attempt,
    int? statusCode,
    bool isTimeout = false,
    bool isConnectionError = false,
    Duration? retryAfter,
  }) {
    throw UnimplementedError('RetryPolicy.decide');
  }
}

/// Значение jitter по умолчанию — равномерное [0, 1).
double _defaultJitter() {
  throw UnimplementedError('_defaultJitter');
}
