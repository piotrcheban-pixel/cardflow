/// Сообщения об ошибках генерации для UI — только строки ARB (SPEC A8.6).
///
/// Коды ошибок маппятся в русские сообщения; сырые исключения, ответы
/// провайдеров и `GenerationException.details` пользователю не показываются.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Сообщение для кода ошибки генерации.
///
/// [retryAfter] используется для кода `rateLimited` («Повтор через N секунд»).
/// [providerReason] — безопасная причина HTTP 400 от провайдера (ADR-022).
String generationErrorCodeMessage(
  AppLocalizations l10n,
  GenerationErrorCode code, {
  Duration? retryAfter,
  String? providerReason,
}) {
  return switch (code) {
    GenerationErrorCode.missingApiKey => l10n.generationErrorMissingApiKey,
    GenerationErrorCode.providerNotConfigured =>
      l10n.generationErrorProviderNotConfigured,
    GenerationErrorCode.invalidApiKey => l10n.generationErrorInvalidApiKey,
    GenerationErrorCode.badRequest =>
      providerReason == null || providerReason.trim().isEmpty
          ? l10n.generationErrorBadRequest
          : l10n.generationErrorBadRequestReason(providerReason.trim()),
    GenerationErrorCode.rateLimited =>
      retryAfter == null
          ? l10n.generationErrorRateLimitedNoDelay
          : l10n.generationErrorRateLimited(math.max(0, retryAfter.inSeconds)),
    GenerationErrorCode.serverUnavailable =>
      l10n.generationErrorServerUnavailable,
    GenerationErrorCode.timeout ||
    GenerationErrorCode.network => l10n.generationErrorNoConnection,
    GenerationErrorCode.cancelled => l10n.generationErrorCancelled,
    GenerationErrorCode.emptyResponse => l10n.generationErrorEmptyResponse,
    GenerationErrorCode.truncated ||
    GenerationErrorCode.refused ||
    GenerationErrorCode.invalidResponse =>
      l10n.generationErrorUnexpectedResponse,
    GenerationErrorCode.noMaterials => l10n.generationErrorNoMaterials,
    GenerationErrorCode.visionUnsupported =>
      l10n.generationErrorVisionUnsupported,
    GenerationErrorCode.fileWithoutTextAndVision =>
      l10n.generationErrorFileWithoutTextAndVision,
    GenerationErrorCode.pdfScanUnsupported =>
      l10n.generationErrorPdfScanUnsupported,
    GenerationErrorCode.pdfScanVisionRequired =>
      l10n.generationErrorPdfScanVisionRequired,
    GenerationErrorCode.attachmentTooLarge =>
      l10n.generationErrorAttachmentTooLarge,
  };
}

/// Сообщение для произвольной ошибки генерации (код или общая строка ARB).
String generationErrorMessage(AppLocalizations l10n, Object error) {
  if (error is GenerationException) {
    return generationErrorCodeMessage(
      l10n,
      error.code,
      retryAfter: error.retryAfter,
      providerReason: error.providerReason,
    );
  }
  return l10n.generationErrorGeneric;
}
