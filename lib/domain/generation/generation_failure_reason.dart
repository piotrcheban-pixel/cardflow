/// Внутренние коды причины падения фрагмента генерации (итерация fix-gen).
///
/// Код не содержит текста материалов и ключей: только машинную причину, чтобы
/// отличить «модель обрезала ответ» от «модель вернула не JSON», «схема не
/// сошлась» и «валидатор отверг структуру». Код пишется в `generation_jobs` и
/// в отладочный лог (ADR-024), а пользователю показывается строка ARB.
library;

import 'package:cardflow/domain/generation/generation_error.dart';

/// Внутренняя причина сбоя фрагмента.
enum GenerationFailureReason {
  /// Ответ обрезан по лимиту токенов.
  truncated('truncated'),

  /// Модель отказалась отвечать (`refusal`).
  refusal('refusal'),

  /// Ответ заблокирован safety-фильтром провайдера.
  safety('safety'),

  /// Текст ответа не является валидным JSON (например, одиночные `\` LaTeX).
  jsonParse('json_parse'),

  /// Переполнение контекстного окна модели.
  contextOverflow('context_overflow'),

  /// Тело запроса больше допустимого (HTTP 413 / лимит байт).
  payloadTooLarge('payload_too_large'),

  /// Модальность не поддерживается (Vision/PDF/вложение).
  unsupportedModality('unsupported_modality'),

  /// JSON валиден, но не соответствует канонической схеме A8.4.
  schemaInvalid('schema_invalid'),

  /// Структура карточек не соответствует ожидаемой (валидатор отверг ответ).
  validatorRejected('validator_rejected'),

  /// Нет сети/таймаут.
  network('network'),

  /// HTTP 4xx (кроме повторов, которые уже обработал `RetryPolicy`).
  httpClientError('http_4xx'),

  /// HTTP 5xx после всех попыток.
  httpServerError('http_5xx'),

  /// Модель вернула пустой контент.
  emptyResponse('empty_response'),

  /// Ответ провайдера не разобрался (нет `choices`/`tool_use` и т.п.).
  providerResponse('provider_response'),

  /// Запрос отменён пользователем.
  cancelled('cancelled'),

  /// Непредвиденная ошибка адаптера/пайплайна.
  unknown('unknown'),

  /// Локальное хранилище недоступно (журнал задания не читается/не пишется).
  storage('storage_unavailable');

  const GenerationFailureReason(this.code);

  /// Машинный код для `generation_jobs` и лога.
  final String code;

  /// Код причины для [code] ошибки по умолчанию.
  static GenerationFailureReason forErrorCode(GenerationErrorCode code) {
    return switch (code) {
      GenerationErrorCode.missingApiKey ||
      GenerationErrorCode.providerNotConfigured ||
      GenerationErrorCode.noMaterials => unknown,
      GenerationErrorCode.visionUnsupported ||
      GenerationErrorCode.fileWithoutTextAndVision ||
      GenerationErrorCode.pdfScanUnsupported ||
      GenerationErrorCode.pdfScanVisionRequired ||
      GenerationErrorCode.attachmentTooLarge => unsupportedModality,
      GenerationErrorCode.invalidApiKey ||
      GenerationErrorCode.insufficientBalance ||
      GenerationErrorCode.badRequest => httpClientError,
      GenerationErrorCode.contextOverflow => contextOverflow,
      GenerationErrorCode.payloadTooLarge => payloadTooLarge,
      GenerationErrorCode.rateLimited => httpClientError,
      GenerationErrorCode.serverUnavailable => httpServerError,
      GenerationErrorCode.timeout || GenerationErrorCode.network => network,
      GenerationErrorCode.cancelled => cancelled,
      GenerationErrorCode.emptyResponse => emptyResponse,
      GenerationErrorCode.truncated => truncated,
      GenerationErrorCode.refused => refusal,
      GenerationErrorCode.invalidResponse => providerResponse,
      GenerationErrorCode.storageUnavailable => storage,
    };
  }

  /// Причина из строки (для повторного разбора `generation_jobs.error_code`).
  static GenerationFailureReason? tryParse(String value) {
    for (final reason in values) {
      if (reason.code == value) return reason;
    }
    return null;
  }
}
