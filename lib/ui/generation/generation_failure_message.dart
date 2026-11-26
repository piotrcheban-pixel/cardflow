/// Сообщение о причине падения фрагмента генерации — только строки ARB.
library;

import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/l10n/app_localizations.dart';

/// Понятная пользователю причина сбоя фрагмента (fix-gen, Д6).
String generationFailureReasonMessage(
  AppLocalizations l10n,
  GenerationFailureReason reason,
) {
  return switch (reason) {
    GenerationFailureReason.truncated => l10n.generationReasonTruncated,
    GenerationFailureReason.refusal => l10n.generationReasonRefusal,
    GenerationFailureReason.safety => l10n.generationReasonSafety,
    GenerationFailureReason.jsonParse => l10n.generationReasonJsonParse,
    GenerationFailureReason.contextOverflow =>
      l10n.generationReasonContextOverflow,
    GenerationFailureReason.payloadTooLarge =>
      l10n.generationReasonPayloadTooLarge,
    GenerationFailureReason.unsupportedModality =>
      l10n.generationReasonUnsupportedModality,
    GenerationFailureReason.schemaInvalid => l10n.generationReasonSchemaInvalid,
    GenerationFailureReason.validatorRejected =>
      l10n.generationReasonValidatorRejected,
    GenerationFailureReason.network => l10n.generationReasonNetwork,
    GenerationFailureReason.httpClientError =>
      l10n.generationReasonHttpClientError,
    GenerationFailureReason.httpServerError =>
      l10n.generationReasonHttpServerError,
    GenerationFailureReason.emptyResponse => l10n.generationReasonEmptyResponse,
    GenerationFailureReason.providerResponse =>
      l10n.generationReasonProviderResponse,
    GenerationFailureReason.cancelled => l10n.generationReasonCancelled,
    GenerationFailureReason.unknown => l10n.generationReasonUnknown,
    GenerationFailureReason.storage => l10n.generationReasonStorage,
  };
}
