/// Лимиты и возможности модели с происхождением каждого поля (ADR-039).
///
/// `ModelLimits` — слоистый ответ на вопрос «что мы знаем о модели»: значение
/// пользователя, ответ API провайдера, официальный каталог, допущение или
/// неизвестность. Слияние — **по каждому полю отдельно** (ADR-039 §2).
/// Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/sourced.dart';
export 'package:cardflow/domain/generation/sourced.dart'
    show CapabilitySource, ContextSemantics, Sourced;

/// Возможности модели: каждое поле — [Sourced], «неизвестно» — `null`.
final class ModelLimits {
  /// Создаёт лимиты; отсутствующие поля неизвестны.
  const ModelLimits({
    this.contextTokens = const Sourced<int>.absent(),
    this.contextSemantics = ContextSemantics.unknown,
    this.maxInputTokens = const Sourced<int>.absent(),
    this.maxOutputTokens = const Sourced<int>.absent(),
    this.maxRequestBytes = const Sourced<int>.absent(),
    this.supportsImageInput = const Sourced<bool>.absent(),
    this.supportsPdfInput = const Sourced<bool>.absent(),
    this.isReasoningModel = const Sourced<bool>.absent(),
    this.pricing = const Sourced<ModelPricing>.absent(),
  });

  /// Всё неизвестно.
  const ModelLimits.absent() : this();

  /// Окно контекста модели.
  final Sourced<int> contextTokens;

  /// Семантика окна (total/inputOnly/unknown).
  final ContextSemantics contextSemantics;

  /// Отдельный лимит входа, если документирован.
  final Sourced<int> maxInputTokens;

  /// Лимит вывода модели.
  final Sourced<int> maxOutputTokens;

  /// Технический предел размера тела запроса протокола.
  final Sourced<int> maxRequestBytes;

  /// Принимает ли модель изображения.
  final Sourced<bool> supportsImageInput;

  /// Принимает ли протокол PDF как документ.
  final Sourced<bool> supportsPdfInput;

  /// Включает ли `max_tokens` токены рассуждений.
  final Sourced<bool> isReasoningModel;

  /// Цены за 1M токенов, если известны.
  final Sourced<ModelPricing> pricing;

  /// Значение окна или `null`.
  int? get contextTokensValue => contextTokens.value;

  /// Значение лимита вывода или `null`.
  int? get maxOutputTokensValue => maxOutputTokens.value;

  /// Значение лимита входа или `null`.
  int? get maxInputTokensValue => maxInputTokens.value;

  /// true, если окно контекста известно.
  bool get hasContext => contextTokens.isKnown;

  /// true, если семантика окна известна.
  bool get hasContextSemantics =>
      contextSemantics != ContextSemantics.unknown;

  /// Поля, значения которых неизвестны (для предупреждений/диагностики).
  List<String> get unknownFields => List<String>.unmodifiable(<String>[
    if (!contextTokens.isKnown) 'context_window',
    if (!maxOutputTokens.isKnown) 'max_output_tokens',
    if (!supportsImageInput.isKnown) 'supports_image_input',
    if (!pricing.isKnown) 'pricing',
  ]);

  /// Копия с изменениями полей (для слоёв пользователя/API).
  ModelLimits copyWith({
    Sourced<int>? contextTokens,
    ContextSemantics? contextSemantics,
    Sourced<int>? maxInputTokens,
    Sourced<int>? maxOutputTokens,
    Sourced<int>? maxRequestBytes,
    Sourced<bool>? supportsImageInput,
    Sourced<bool>? supportsPdfInput,
    Sourced<bool>? isReasoningModel,
    Sourced<ModelPricing>? pricing,
  }) => ModelLimits(
    contextTokens: contextTokens ?? this.contextTokens,
    contextSemantics: contextSemantics ?? this.contextSemantics,
    maxInputTokens: maxInputTokens ?? this.maxInputTokens,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    maxRequestBytes: maxRequestBytes ?? this.maxRequestBytes,
    supportsImageInput: supportsImageInput ?? this.supportsImageInput,
    supportsPdfInput: supportsPdfInput ?? this.supportsPdfInput,
    isReasoningModel: isReasoningModel ?? this.isReasoningModel,
    pricing: pricing ?? this.pricing,
  );

  @override
  String toString() =>
      'ModelLimits(context: ${contextTokens.value ?? 'unknown'} '
      '${contextTokens.source.wireName}, output: '
      '${maxOutputTokens.value ?? 'unknown'}, '
      'semantics: ${contextSemantics.name})';
}

/// Ранг источника для слияния (ADR-039 §2).
int capabilitySourceRank(CapabilitySource source) => source.priority;

/// Слияние слоёв **по каждому полю**: побеждает известное значение с
/// наибольшим рангом источника; при равенстве — более ранний слой.
///
/// [layers] передаются в порядке приоритета (пользователь первым); функция не
/// зависит от порядка и всё равно сравнивает ранги.
ModelLimits mergeModelLimits(Iterable<ModelLimits> layers) {
  final List<ModelLimits> list = layers.toList(growable: false);
  T pick<T>(Sourced<T> Function(ModelLimits) field) {
    Sourced<T> best = field(const ModelLimits.absent());
    for (final ModelLimits layer in list) {
      final Sourced<T> candidate = field(layer);
      if (!candidate.isKnown) continue;
      if (!best.isKnown ||
          capabilitySourceRank(candidate.source) >
              capabilitySourceRank(best.source)) {
        best = candidate;
      }
    }
    return best;
  }

  ContextSemantics semantics = ContextSemantics.unknown;
  for (final ModelLimits layer in list) {
    if (layer.contextSemantics != ContextSemantics.unknown) {
      semantics = layer.contextSemantics;
      break;
    }
  }
  return ModelLimits(
    contextTokens: pick<int>((ModelLimits l) => l.contextTokens),
    contextSemantics: semantics,
    maxInputTokens: pick<int>((ModelLimits l) => l.maxInputTokens),
    maxOutputTokens: pick<int>((ModelLimits l) => l.maxOutputTokens),
    maxRequestBytes: pick<int>((ModelLimits l) => l.maxRequestBytes),
    supportsImageInput: pick<bool>((ModelLimits l) => l.supportsImageInput),
    supportsPdfInput: pick<bool>((ModelLimits l) => l.supportsPdfInput),
    isReasoningModel: pick<bool>((ModelLimits l) => l.isReasoningModel),
    pricing: pick<ModelPricing>((ModelLimits l) => l.pricing),
  );
}

/// Проекция существующих `ModelCapabilities` в слоистые `ModelLimits`.
///
/// Источники `ModelCapabilities` уже отражают происхождение (user/preset/api/
/// assumption); конверсия сохраняет их и добавляет дату отсутствующей (старые
/// данные дат не несут).
ModelLimits modelLimitsFromCapabilities(ModelCapabilities capabilities) {
  Sourced<int> intField(int? value, CapabilitySource source) => value == null
      ? const Sourced<int>.absent()
      : Sourced<int>(value, source: source, sourceRef: 'model_capabilities');
  Sourced<bool> boolField(bool? value, CapabilitySource source) => value == null
      ? const Sourced<bool>.absent()
      : Sourced<bool>(value, source: source, sourceRef: 'model_capabilities');
  final CapabilitySource contextSource = capabilities.contextSource;
  final CapabilitySource outputSource = capabilities.outputSource;
  final CapabilitySource imageSource = capabilities.imageSource;
  final CapabilitySource pricingSource = capabilities.pricingSource;
  return ModelLimits(
    contextTokens: intField(
      capabilities.contextWindowTokens,
      contextSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : contextSource,
    ),
    contextSemantics: capabilities.contextSemantics,
    maxInputTokens: intField(
      capabilities.maxInputTokens,
      contextSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : contextSource,
    ),
    maxOutputTokens: intField(
      capabilities.maxOutputTokens,
      outputSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : outputSource,
    ),
    maxRequestBytes: intField(
      capabilities.maxRequestBytes,
      imageSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : imageSource,
    ),
    supportsImageInput: boolField(
      capabilities.supportsVision,
      imageSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : imageSource,
    ),
    supportsPdfInput: Sourced<bool>(
      capabilities.supportsPdfDocumentPart,
      source: CapabilitySource.officialCatalog,
      sourceRef: 'provider_protocol',
    ),
    pricing: capabilities.pricing == null
        ? const Sourced<ModelPricing>.absent()
        : Sourced<ModelPricing>(
            capabilities.pricing,
            source: pricingSource == CapabilitySource.unknown
                ? CapabilitySource.assumption
                : pricingSource,
          ),
  );
}
