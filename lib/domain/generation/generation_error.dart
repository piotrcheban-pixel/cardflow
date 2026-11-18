/// Ошибки слоя генерации карточек (SPEC A8.6).
///
/// Наружу (в UI) попадает только код, который маппится в строку ARB; [details]
/// предназначены для журналов/тестов и не показываются пользователю.
library;

import 'package:cardflow/domain/generation/generation_failure_reason.dart';

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

  /// Переполнение контекстного окна модели (провайдер сообщил о лимите
  /// токенов или план его посчитал невыполнимым).
  contextOverflow,

  /// Тело запроса больше допустимого (HTTP 413 или лимит `maxRequestBytes`).
  payloadTooLarge,

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

  /// После парсинга нет текста для генерации (итерация 3c, ADR-015; с 7.8 —
  /// пустой текст после санитизации, скан или пустая форма).
  noMaterials,

  /// Модель не поддерживает изображения, а пользователь приложил картинку.
  visionUnsupported,

  /// Текст не извлечён, а модель не поддерживает изображения (скан).
  fileWithoutTextAndVision,

  /// PDF-скан, но протокол/модель не принимает PDF как документ.
  pdfScanUnsupported,

  /// PDF-скан отрендерен в страницы, а у модели нет Vision (итерация 7.9).
  pdfScanVisionRequired,

  /// Вложение больше inline-лимита (10 МБ).
  attachmentTooLarge,
}

/// Исключение слоя генерации.
class GenerationException implements Exception {
  /// Создаёт исключение с кодом [code].
  ///
  /// [failureReason] — внутренняя причина (fix-gen): уточняет, что именно
  /// сломалось у фрагмента (`json_parse`, `schema_invalid`, ...), и пишется в
  /// `generation_jobs`/отладочный лог. По умолчанию выводится из [code].
  const GenerationException(
    this.code, {
    this.retryAfter,
    this.details,
    this.providerReason,
    this.failureReason,
  });

  /// Код ошибки для маппинга в ARB.
  final GenerationErrorCode code;

  /// Пауза из `Retry-After` (для кода `rateLimited`), если была.
  final Duration? retryAfter;

  /// Диагностическая информация (не показывается пользователю, без ключей/материалов).
  final String? details;

  /// Короткая безопасная причина отказа провайдера (HTTP 400), показывается
  /// пользователю в ARB-шаблоне «Запрос отклонён: {reason}». Очищена от
  /// управляющих символов и секретоподобных значений, ограничена по длине.
  final String? providerReason;

  /// Внутренняя причина сбоя фрагмента (fix-gen); `null` — выводится из [code].
  final GenerationFailureReason? failureReason;

  /// Итоговая причина сбоя фрагмента для журнала и `generation_jobs`.
  GenerationFailureReason get reason =>
      failureReason ?? GenerationFailureReason.forErrorCode(code);

  @override
  String toString() =>
      'GenerationException(${code.name}'
      '${reason == GenerationFailureReason.forErrorCode(code) ? '' : '/${reason.code}'}'
      '${details == null ? '' : ': $details'})';
}
