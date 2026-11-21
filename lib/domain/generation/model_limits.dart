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
    this.maxCardsPerRequest = const Sourced<int>.absent(),
    this.maxRequestBytes = const Sourced<int>.absent(),
    this.maxImagesPerRequest = const Sourced<int>.absent(),
    this.maxImageBytesPerImage = const Sourced<int>.absent(),
    this.maxImageBytesPerRequest = const Sourced<int>.absent(),
    this.supportsImageInput = const Sourced<bool>.absent(),
    this.supportsPdfInput = const Sourced<bool>.absent(),
    this.isReasoningModel = const Sourced<bool>.absent(),
    this.pricing = const Sourced<GenerationPricing>.absent(),
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

  /// Потолок карточек в одном запросе (структурированный вывод).
  final Sourced<int> maxCardsPerRequest;

  /// Технический предел размера тела запроса протокола.
  final Sourced<int> maxRequestBytes;

  /// Максимум image-частей в одном запросе.
  final Sourced<int> maxImagesPerRequest;

  /// Максимум байт одного изображения.
  final Sourced<int> maxImageBytesPerImage;

  /// Максимум байт изображений одного запроса.
  final Sourced<int> maxImageBytesPerRequest;

  /// Принимает ли модель изображения.
  final Sourced<bool> supportsImageInput;

  /// Принимает ли протокол PDF как документ.
  final Sourced<bool> supportsPdfInput;

  /// Включает ли `max_tokens` токены рассуждений.
  final Sourced<bool> isReasoningModel;

  /// Цены за 1M токенов, если известны.
  final Sourced<GenerationPricing> pricing;

  /// Значение окна или `null`.
  int? get contextTokensValue => contextTokens.value;

  /// Значение лимита вывода или `null`.
  int? get maxOutputTokensValue => maxOutputTokens.value;

  /// Значение лимита входа или `null`.
  int? get maxInputTokensValue => maxInputTokens.value;

  /// true, если окно контекста известно.
  bool get hasContext => contextTokens.isKnown;

  /// true, если семантика окна известна.
  bool get hasContextSemantics => contextSemantics != ContextSemantics.unknown;

  /// Поля, значения которых неизвестны (для предупреждений/диагностики).
  List<String> get unknownFields => List<String>.unmodifiable(<String>[
    if (!contextTokens.isKnown) 'context_window',
    if (!maxOutputTokens.isKnown) 'max_output_tokens',
    if (!supportsImageInput.isKnown) 'supports_image_input',
    // 32 МБ — консервативное допущение приложения, а не лимит провайдера:
    // пока провайдер не подтвердил значение, оно остаётся неизвестным (§5).
    if (!maxRequestBytes.isKnown) 'max_request_bytes',
    if (!pricing.isKnown) 'pricing',
  ]);

  /// Трёхзначная поддержка изображений (7.18.3 §4).
  ImageInputSupport get imageInputSupport =>
      imageInputSupportOf(supportsImageInput);

  /// Копия с изменениями полей (для слоёв пользователя/API).
  ModelLimits copyWith({
    Sourced<int>? contextTokens,
    ContextSemantics? contextSemantics,
    Sourced<int>? maxInputTokens,
    Sourced<int>? maxOutputTokens,
    Sourced<int>? maxCardsPerRequest,
    Sourced<int>? maxRequestBytes,
    Sourced<int>? maxImagesPerRequest,
    Sourced<int>? maxImageBytesPerImage,
    Sourced<int>? maxImageBytesPerRequest,
    Sourced<bool>? supportsImageInput,
    Sourced<bool>? supportsPdfInput,
    Sourced<bool>? isReasoningModel,
    Sourced<GenerationPricing>? pricing,
  }) => ModelLimits(
    contextTokens: contextTokens ?? this.contextTokens,
    contextSemantics: contextSemantics ?? this.contextSemantics,
    maxInputTokens: maxInputTokens ?? this.maxInputTokens,
    maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
    maxCardsPerRequest: maxCardsPerRequest ?? this.maxCardsPerRequest,
    maxRequestBytes: maxRequestBytes ?? this.maxRequestBytes,
    maxImagesPerRequest: maxImagesPerRequest ?? this.maxImagesPerRequest,
    maxImageBytesPerImage: maxImageBytesPerImage ?? this.maxImageBytesPerImage,
    maxImageBytesPerRequest:
        maxImageBytesPerRequest ?? this.maxImageBytesPerRequest,
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

/// Трёхзначная поддержка изображений моделью (7.18.3 §4).
///
/// Неизвестность — отдельное состояние: её нельзя ни выдавать за
/// подтверждённое «поддерживает», ни превращать в подтверждённое «нет».
enum ImageInputSupport {
  /// Поддержка подтверждена (пользователь, API провайдера или каталог).
  supported,

  /// Поддержка подтверждённо отсутствует.
  unsupported,

  /// Подтверждённых данных нет (в том числе допущение приложения).
  unknown,
}

/// Восстанавливает трёхзначное состояние из значения с источником.
///
/// `assumption` — допущение приложения, а не характеристика провайдера:
/// «нет изображений» по допущению не блокирует запуск (состояние
/// `unknown`), «есть изображения» по допущению считается попыткой отправки
/// (`supported`): это направление безопасно, провайдер отклонит запрос сам.
ImageInputSupport imageInputSupportOf(Sourced<bool> value) {
  final bool? known = value.value;
  if (known == null || !value.isKnown) return ImageInputSupport.unknown;
  if (value.source == CapabilitySource.assumption) {
    return known ? ImageInputSupport.supported : ImageInputSupport.unknown;
  }
  return known ? ImageInputSupport.supported : ImageInputSupport.unsupported;
}

/// Слияние слоёв **по каждому полю**: побеждает известное значение с
/// наибольшим рангом источника; при равенстве — более ранний слой.
///
/// [layers] передаются в порядке приоритета (пользователь первым); функция не
/// зависит от порядка и всё равно сравнивает ранги.
ModelLimits mergeModelLimits(Iterable<ModelLimits> layers) {
  final List<ModelLimits> list = layers.toList(growable: false);
  Sourced<T> pick<T>(Sourced<T> Function(ModelLimits) field) {
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
    maxCardsPerRequest: pick<int>((ModelLimits l) => l.maxCardsPerRequest),
    maxRequestBytes: pick<int>((ModelLimits l) => l.maxRequestBytes),
    maxImagesPerRequest: pick<int>((ModelLimits l) => l.maxImagesPerRequest),
    maxImageBytesPerImage: pick<int>(
      (ModelLimits l) => l.maxImageBytesPerImage,
    ),
    maxImageBytesPerRequest: pick<int>(
      (ModelLimits l) => l.maxImageBytesPerRequest,
    ),
    supportsImageInput: pick<bool>((ModelLimits l) => l.supportsImageInput),
    supportsPdfInput: pick<bool>((ModelLimits l) => l.supportsPdfInput),
    isReasoningModel: pick<bool>((ModelLimits l) => l.isReasoningModel),
    pricing: pick<GenerationPricing>((ModelLimits l) => l.pricing),
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
    maxCardsPerRequest: intField(
      capabilities.maxCardsPerRequest,
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
    maxImagesPerRequest: intField(
      capabilities.maxImagesPerRequest,
      imageSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : imageSource,
    ),
    maxImageBytesPerImage: intField(
      capabilities.maxImageBytesPerImage,
      imageSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : imageSource,
    ),
    maxImageBytesPerRequest: intField(
      capabilities.maxImageBytesPerRequest,
      imageSource == CapabilitySource.unknown
          ? CapabilitySource.assumption
          : imageSource,
    ),
    supportsImageInput: boolField(
      capabilities.supportsVision,
      // Плоский API `ModelCapabilities` без источника означает явно заданную
      // возможность (каталог приложения), а не неизвестность: неизвестность
      // передаётся как `supportsVision == null` из проекции лимитов.
      capabilities.visionSource == CapabilitySource.unknown
          ? CapabilitySource.officialCatalog
          : capabilities.visionSource,
    ),
    supportsPdfInput: Sourced<bool>(
      capabilities.supportsPdfDocumentPart,
      source: CapabilitySource.officialCatalog,
      sourceRef: 'provider_protocol',
    ),
    isReasoningModel: capabilities.isReasoningModel == null
        ? const Sourced<bool>.absent()
        : Sourced<bool>(
            capabilities.isReasoningModel,
            source: outputSource == CapabilitySource.unknown
                ? CapabilitySource.assumption
                : outputSource,
            sourceRef: 'model_capabilities',
          ),
    pricing: capabilities.pricing == null
        ? const Sourced<GenerationPricing>.absent()
        : Sourced<GenerationPricing>(
            capabilities.pricing,
            source: pricingSource == CapabilitySource.unknown
                ? CapabilitySource.assumption
                : pricingSource,
          ),
  );
}

/// JSON-представление `Sourced` (кэш характеристик, ADR-039 §4).
Map<String, Object?> sourcedToJson<T>(
  Sourced<T> sourced,
  Object? Function(T value) encode,
) => <String, Object?>{
  'value': sourced.value == null ? null : encode(sourced.value as T),
  'source': sourced.source.wireName,
  if (sourced.observedAt != null)
    'observed_at': sourced.observedAt!.toUtc().toIso8601String(),
  if (sourced.sourceRef != null) 'source_ref': sourced.sourceRef,
};

Sourced<T> sourcedFromJson<T>(Object? json, T? Function(Object? value) decode) {
  if (json is! Map) return Sourced<T>.absent();
  final CapabilitySource source = CapabilitySource.fromWire(json['source']);
  final Object? raw = json['value'];
  final T? value = raw == null ? null : decode(raw);
  final Object? observed = json['observed_at'];
  return Sourced<T>(
    value,
    source: source,
    observedAt: observed is String
        ? DateTime.tryParse(observed)?.toUtc()
        : null,
    sourceRef: json['source_ref'] is String
        ? json['source_ref']! as String
        : null,
  );
}

/// JSON-представление лимитов модели для кэша `generation.model_capabilities`.
Map<String, Object?> modelLimitsToJson(ModelLimits limits) => <String, Object?>{
  'context_window': sourcedToJson<int>(limits.contextTokens, (int v) => v),
  'context_semantics': limits.contextSemantics.name,
  'max_input_tokens': sourcedToJson<int>(limits.maxInputTokens, (int v) => v),
  'max_output_tokens': sourcedToJson<int>(limits.maxOutputTokens, (int v) => v),
  'max_cards_per_request': sourcedToJson<int>(
    limits.maxCardsPerRequest,
    (int v) => v,
  ),
  'max_request_bytes': sourcedToJson<int>(limits.maxRequestBytes, (int v) => v),
  'max_images_per_request': sourcedToJson<int>(
    limits.maxImagesPerRequest,
    (int v) => v,
  ),
  'max_image_bytes_per_image': sourcedToJson<int>(
    limits.maxImageBytesPerImage,
    (int v) => v,
  ),
  'max_image_bytes_per_request': sourcedToJson<int>(
    limits.maxImageBytesPerRequest,
    (int v) => v,
  ),
  'supports_image_input': sourcedToJson<bool>(
    limits.supportsImageInput,
    (bool v) => v,
  ),
  'supports_pdf_input': sourcedToJson<bool>(
    limits.supportsPdfInput,
    (bool v) => v,
  ),
  'is_reasoning_model': sourcedToJson<bool>(
    limits.isReasoningModel,
    (bool v) => v,
  ),
  'pricing': sourcedToJson<GenerationPricing>(
    limits.pricing,
    (GenerationPricing v) => v.toJson(),
  ),
};

/// Разбор лимитов из JSON кэша; битые поля — неизвестны (не 0).
ModelLimits modelLimitsFromJson(Object? json) {
  if (json is! Map) return const ModelLimits.absent();
  int? intOf(Object? value) =>
      value is num && value.isFinite && value >= 0 ? value.toInt() : null;
  bool? boolOf(Object? value) => value is bool ? value : null;
  ContextSemantics semantics = ContextSemantics.unknown;
  for (final ContextSemantics value in ContextSemantics.values) {
    if (value.name == json['context_semantics']) semantics = value;
  }
  final Sourced<GenerationPricing> pricing = sourcedFromJson<GenerationPricing>(
    json['pricing'],
    (Object? value) => GenerationPricing.fromJson(value),
  );
  return ModelLimits(
    contextTokens: sourcedFromJson<int>(json['context_window'], intOf),
    contextSemantics: semantics,
    maxInputTokens: sourcedFromJson<int>(json['max_input_tokens'], intOf),
    maxOutputTokens: sourcedFromJson<int>(json['max_output_tokens'], intOf),
    maxCardsPerRequest: sourcedFromJson<int>(
      json['max_cards_per_request'],
      intOf,
    ),
    maxRequestBytes: sourcedFromJson<int>(json['max_request_bytes'], intOf),
    maxImagesPerRequest: sourcedFromJson<int>(
      json['max_images_per_request'],
      intOf,
    ),
    maxImageBytesPerImage: sourcedFromJson<int>(
      json['max_image_bytes_per_image'],
      intOf,
    ),
    maxImageBytesPerRequest: sourcedFromJson<int>(
      json['max_image_bytes_per_request'],
      intOf,
    ),
    supportsImageInput: sourcedFromJson<bool>(
      json['supports_image_input'],
      boolOf,
    ),
    supportsPdfInput: sourcedFromJson<bool>(json['supports_pdf_input'], boolOf),
    isReasoningModel: sourcedFromJson<bool>(json['is_reasoning_model'], boolOf),
    pricing: pricing,
  );
}
