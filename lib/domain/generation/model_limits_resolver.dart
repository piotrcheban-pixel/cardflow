/// Слоистое разрешение `ModelLimits` по аккаунту, каталогу и кэшу (ADR-039 §2/§5).
///
/// Приоритет по каждому полю: `userConfigured` → `providerApi` →
/// `officialCatalog` → `assumption` → `unknown`. «Неизвестно» — `null`:
/// значение не выдумывается.
/// Домен не зависит от Flutter и сети.
library;

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Семантика окна по умолчанию для пресета (по протоколу).
ContextSemantics defaultSemanticsForAccount(ProviderAccount account) {
  final String? preset = account.presetId;
  if (preset == 'deepseek' || preset == 'openrouter') {
    return ContextSemantics.totalInputPlusOutput;
  }
  if (preset == 'ollama') {
    // `<arch>.context_length` документирован без семантики total/input-only,
    // а рабочий num_ctx может быть меньше: не выдаём догадку за факт.
    return ContextSemantics.unknown;
  }
  if (preset == 'groq' || preset == 'moonshot' || preset == 'minimax') {
    return ContextSemantics.unknown;
  }
  return switch (account.protocol) {
    ProviderProtocol.anthropicMessages ||
    ProviderProtocol.geminiGenerateContent => ContextSemantics.inputOnly,
    ProviderProtocol.openai => ContextSemantics.totalInputPlusOutput,
    ProviderProtocol.openaiCompletions => ContextSemantics.unknown,
  };
}

/// Разрешает лимиты модели по слоям (ADR-039).
///
/// [cached] — последняя удачная запись кэша (`providerApi`), может быть
/// устаревшей: значение используется до успешного обновления.
ModelLimits resolveModelLimits({
  required ProviderAccount account,
  ModelCapabilityRecord? cached,
  ProviderPreset? preset,
  DateTime? now,
}) {
  final DateTime timestamp = now ?? DateTime.now().toUtc();
  final ProviderPresetModel? presetModel = preset?.modelById(account.modelId);
  final CapabilitySource accountSource =
      account.capabilitiesSource == CapabilitySource.unknown
      ? CapabilitySource.userConfigured
      : account.capabilitiesSource;
  // Значение контекста, скопированное из каталога factory-аккаунтом, — не
  // пользовательская настройка: его отдаёт слой каталога.
  final bool contextFromPreset =
      account.presetId != null &&
      presetModel != null &&
      account.capabilitiesConfiguredAt == null &&
      account.contextTokens == presetModel.contextTokens;
  // Дата проверки пользовательской настройки — момент сохранения, а не «сейчас»:
  // иначе UI показывал бы сегодняшнюю дату у старой настройки.
  final DateTime? userObservedAt = account.capabilitiesConfiguredAt;
  final Sourced<int> userContext =
      !contextFromPreset &&
          account.contextTokens > 0 &&
          account.contextTokens != kCustomProviderContextTokens
      ? Sourced<int>(
          account.contextTokens,
          source: accountSource,
          observedAt: userObservedAt,
        )
      : const Sourced<int>.absent();
  final Sourced<int> userInput = account.maxInputTokens == null
      ? const Sourced<int>.absent()
      : Sourced<int>(
          account.maxInputTokens,
          source: accountSource,
          observedAt: userObservedAt,
        );
  final Sourced<int> userOutput = account.maxOutputTokens == null
      ? const Sourced<int>.absent()
      : Sourced<int>(
          account.maxOutputTokens,
          source: accountSource,
          observedAt: userObservedAt,
        );
  final Sourced<int> userImages = account.maxImagesPerRequest == null
      ? const Sourced<int>.absent()
      : Sourced<int>(
          account.maxImagesPerRequest,
          source: accountSource,
          observedAt: userObservedAt,
        );
  final Sourced<int> userImageBytes = account.maxImageBytes == null
      ? const Sourced<int>.absent()
      : Sourced<int>(
          account.maxImageBytes,
          source: accountSource,
          observedAt: userObservedAt,
        );
  final Sourced<int> userRequestBytes = account.maxRequestBytes == null
      ? const Sourced<int>.absent()
      : Sourced<int>(
          account.maxRequestBytes,
          source: accountSource,
          observedAt: userObservedAt,
        );
  final GenerationPricing? pricing = account.pricing;
  final Sourced<GenerationPricing> userPricing = pricing == null
      ? const Sourced<GenerationPricing>.absent()
      : Sourced<GenerationPricing>(
          pricing,
          source: accountSource,
          observedAt: userObservedAt,
        );
  final ModelLimits userLayer = ModelLimits(
    contextTokens: userContext,
    maxInputTokens: userInput,
    maxOutputTokens: userOutput,
    maxImagesPerRequest: userImages,
    maxImageBytesPerImage: userImageBytes,
    maxRequestBytes: userRequestBytes,
    pricing: userPricing,
    supportsImageInput: account.visionConfigured
        ? Sourced<bool>(
            account.supportsVision,
            source: accountSource,
            observedAt: userObservedAt,
          )
        : const Sourced<bool>.absent(),
  );

  final bool presetVerified =
      presetModel?.sourceRef != null && presetModel?.verifiedOn != null;
  final DateTime? presetDate = presetModel?.verifiedOn == null
      ? null
      : DateTime.tryParse('${presetModel!.verifiedOn!}T00:00:00Z');
  final CapabilitySource presetSource = presetVerified
      ? CapabilitySource.officialCatalog
      : CapabilitySource.assumption;

  final String? presetRef = presetModel?.sourceRef;
  final ModelLimits catalogLayer = ModelLimits(
    contextTokens: presetModel == null
        ? const Sourced<int>.absent()
        : Sourced<int>(
            presetModel.contextTokens,
            source: presetSource,
            observedAt: presetDate,
            sourceRef: presetRef,
          ),
    contextSemantics: defaultSemanticsForAccount(account),
    supportsImageInput: presetModel == null
        ? const Sourced<bool>.absent()
        : Sourced<bool>(
            presetModel.supportsVision,
            source: presetSource,
            observedAt: presetDate,
            sourceRef: presetRef,
          ),
    supportsPdfInput: Sourced<bool>(
      account.protocol.supportsPdfAttachments,
      source: CapabilitySource.officialCatalog,
      sourceRef: 'provider_protocol',
    ),
  );

  // Эвристика ADR-022 больше не «подтверждение»: только `assumption`.
  final ModelLimits inferredLayer =
      account.supportsVision && presetModel == null && !account.visionConfigured
      ? ModelLimits(
          supportsImageInput: Sourced<bool>(
            inferSupportsVisionFromModelId(account.modelId),
            source: CapabilitySource.assumption,
            observedAt: timestamp,
          ),
        )
      : const ModelLimits.absent();

  final ModelLimits providerLayer =
      cached?.limits ?? const ModelLimits.absent();
  final ModelLimits merged = mergeModelLimits(<ModelLimits>[
    userLayer,
    providerLayer,
    catalogLayer,
    inferredLayer,
  ]);
  if (merged.contextSemantics != ContextSemantics.unknown) return merged;
  return ModelLimits(
    contextTokens: merged.contextTokens,
    contextSemantics: defaultSemanticsForAccount(account),
    maxInputTokens: merged.maxInputTokens,
    maxOutputTokens: merged.maxOutputTokens,
    maxCardsPerRequest: merged.maxCardsPerRequest,
    maxRequestBytes: merged.maxRequestBytes,
    maxImagesPerRequest: merged.maxImagesPerRequest,
    maxImageBytesPerImage: merged.maxImageBytesPerImage,
    maxImageBytesPerRequest: merged.maxImageBytesPerRequest,
    supportsImageInput: merged.supportsImageInput,
    supportsPdfInput: merged.supportsPdfInput,
    isReasoningModel: merged.isReasoningModel,
    pricing: merged.pricing,
  );
}
