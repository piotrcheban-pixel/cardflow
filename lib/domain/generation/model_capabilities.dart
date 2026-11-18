/// Возможности провайдера и модели (раздел C аудита TASK 01).
///
/// Главное правило: у возможности есть значение **и** источник. Неизвестное
/// значение — `null` (или [CapabilitySource.unknown]), а не 0 и не «типовое»
/// число семейства моделей. Каталог пресетов (`provider_preset.dart`) остаётся
/// источником [CapabilitySource.preset]; цены, лимиты вывода и изображений в
/// каталоге не подтверждены документацией и потому не подставляются.
/// Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';

/// Источник значения возможности.
enum CapabilitySource {
  /// Подтверждено документацией провайдера; в репозитории таких значений нет.
  verified('verified'),

  /// Значение из статического каталога пресетов приложения (не подтверждено).
  preset('preset'),

  /// Значение, введённое пользователем в настройках аккаунта.
  user('user'),

  /// Выведено из имени модели или протокола (эвристика).
  inferred('inferred'),

  /// Значение неизвестно — использовать консервативное допущение.
  unknown('unknown');

  const CapabilitySource(this.wireName);

  /// Имя в JSON (`capabilities_source` в разделе K.1 аудита).
  final String wireName;

  /// true, если источник известен (не [CapabilitySource.unknown]).
  bool get isKnown => this != CapabilitySource.unknown;

  /// Разбирает источник из JSON; неизвестная/битая строка — `unknown`.
  static CapabilitySource fromWire(Object? value) {
    if (value is String) {
      for (final CapabilitySource source in values) {
        if (source.wireName == value) return source;
      }
    }
    return CapabilitySource.unknown;
  }
}

/// Вид токенизатора модели.
enum TokenizerKind {
  /// Точный локальный токенизатор модели (в репозитории отсутствует).
  exact,

  /// Известная консервативная эвристика.
  heuristic,

  /// Токенизатор неизвестен — оценка обязана быть консервативной.
  unknown,
}

/// Оценка токенов изображения (раздел E.4 аудита).
///
/// Интерфейс живёт здесь, потому что является частью возможностей модели.
/// Реализации (dimension/byte heuristic, conservative default) появляются
/// вместе с оценщиком; в фундаменте `ModelCapabilities.imageTokens == null`,
/// а универсальный `kImageTokenEstimate = 1000` не подставляется.
abstract interface class ImageTokenModel {
  /// Оценка токенов изображения; неизвестные размеры — допустимы.
  int estimate({int? width, int? height, required int bytes});

  /// Источник оценки (`provider_formula`, `dimension_heuristic`, …).
  String get source;
}

/// Возможности модели: nullable-значения с источником, без «магических» чисел.
class ModelCapabilities {
  /// Создаёт возможности модели; неизвестное значение — `null`.
  const ModelCapabilities({
    this.contextWindowTokens,
    this.maxInputTokens,
    this.maxOutputTokens,
    this.maxCardsPerRequest,
    this.maxImagesPerRequest,
    this.maxImageBytesPerImage,
    this.maxImageBytesPerRequest,
    this.maxImageSidePx,
    this.maxRequestBytes,
    this.supportsVision = false,
    this.supportsPdfDocumentPart = false,
    this.supportsStrictJsonSchema,
    this.tokenizer = TokenizerKind.unknown,
    this.imageTokens,
    this.pricing,
    this.contextSource = CapabilitySource.unknown,
    this.outputSource = CapabilitySource.unknown,
    this.imageSource = CapabilitySource.unknown,
    this.pricingSource = CapabilitySource.unknown,
  }) : assert(
         contextWindowTokens == null || contextWindowTokens > 0,
         'Неизвестное окно — null, а не 0',
       ),
       assert(maxInputTokens == null || maxInputTokens > 0),
       assert(maxOutputTokens == null || maxOutputTokens > 0),
       assert(maxCardsPerRequest == null || maxCardsPerRequest > 0),
       assert(maxImagesPerRequest == null || maxImagesPerRequest > 0),
       assert(maxImageBytesPerImage == null || maxImageBytesPerImage > 0),
       assert(maxImageBytesPerRequest == null || maxImageBytesPerRequest > 0),
       assert(maxImageSidePx == null || maxImageSidePx > 0),
       assert(maxRequestBytes == null || maxRequestBytes > 0),
       assert(
         contextWindowTokens == null ||
             contextSource != CapabilitySource.unknown,
         'У известного значения обязан быть источник',
       );

  /// Ключи [unknownFields]: окно контекста неизвестно.
  static const String unknownContextWindow = 'context_window';

  /// Ключ [unknownFields]: лимит вывода модели неизвестен.
  static const String unknownOutputTokens = 'max_output_tokens';

  /// Ключ [unknownFields]: лимиты изображений неизвестны.
  static const String unknownImageLimits = 'image_limits';

  /// Ключ [unknownFields]: цены неизвестны (полностью или частично).
  static const String unknownPricing = 'pricing';

  /// Окно контекста (вход + выход), токенов; `null` — неизвестно.
  final int? contextWindowTokens;

  /// Отдельный лимит входа, если провайдер его публикует; `null` — неизвестно.
  final int? maxInputTokens;

  /// Жёсткий лимит вывода модели; `null` — неизвестно.
  final int? maxOutputTokens;

  /// Потолок карточек в одном запросе (структурированный вывод); `null` — нет
  /// подтверждённых данных.
  final int? maxCardsPerRequest;

  /// Максимум image-частей в одном запросе; `null` — неизвестно.
  final int? maxImagesPerRequest;

  /// Максимум байт одного изображения; `null` — неизвестно.
  final int? maxImageBytesPerImage;

  /// Максимум байт всех изображений запроса; `null` — неизвестно.
  final int? maxImageBytesPerRequest;

  /// Максимальная сторона изображения, px; `null` — неизвестно.
  final int? maxImageSidePx;

  /// Максимальный размер тела запроса, байт; `null` — неизвестно.
  final int? maxRequestBytes;

  /// Принимает ли модель изображения (настройка/пресет аккаунта).
  final bool supportsVision;

  /// Принимает ли протокол PDF как документ (факт реализации в приложении).
  final bool supportsPdfDocumentPart;

  /// Принимает ли модель strict JSON-схему; `null` — неизвестно (ADR-021).
  final bool? supportsStrictJsonSchema;

  /// Вид токенизатора модели.
  final TokenizerKind tokenizer;

  /// Оценщик токенов изображений; `null` — неизвестно.
  final ImageTokenModel? imageTokens;

  /// Цены; `null` — неизвестно.
  final GenerationPricing? pricing;

  /// Источник окна контекста.
  final CapabilitySource contextSource;

  /// Источник лимита вывода.
  final CapabilitySource outputSource;

  /// Источник лимитов изображений.
  final CapabilitySource imageSource;

  /// Источник цен.
  final CapabilitySource pricingSource;

  /// Состояние цен (через [pricing]).
  PricingState get pricingState => pricing?.state ?? PricingState.unknown;

  /// true, если окно контекста известно.
  bool get hasContextWindow => contextWindowTokens != null;

  /// Поля, значения которых неизвестны (для предупреждений и оценки).
  List<String> get unknownFields => List<String>.unmodifiable(<String>[
    if (contextWindowTokens == null) unknownContextWindow,
    if (maxOutputTokens == null) unknownOutputTokens,
    if (maxImagesPerRequest == null ||
        maxImageBytesPerImage == null ||
        maxImageBytesPerRequest == null ||
        maxImageSidePx == null)
      unknownImageLimits,
    if (pricing == null || pricing!.state != PricingState.complete)
      unknownPricing,
  ]);

  /// Источник каждого параметра возможностей (для диагностики плана).
  ///
  /// `unknown` означает «подтверждённого значения нет»; вызывающий код обязан
  /// применить консервативное допущение и пометить его, а не выдавать за факт.
  /// Карта неизменяемая; ключи стабильны.
  Map<String, CapabilitySource> get sources =>
      Map<String, CapabilitySource>.unmodifiable(<String, CapabilitySource>{
        'context_window': contextSource,
        'max_output_tokens': outputSource,
        'image_limits': imageSource,
        'pricing': pricingSource,
        // Полей для этих значений в аккаунте/каталоге нет — только unknown.
        'max_cards_per_request': CapabilitySource.unknown,
        'tokenizer': tokenizer == TokenizerKind.unknown
            ? CapabilitySource.unknown
            : CapabilitySource.inferred,
      });
}

/// Собирает возможности модели по аккаунту: аккаунт (user) → каталог (preset)
/// → протокол (inferred) → unknown.
///
/// Чего здесь **нет** намеренно:
/// - `ProviderAccount.contextTokens` не используется как окно модели: у
///   пользовательского аккаунта это константа-заглушка 16 000 (L-18), и
///   трактовать её как факт — значит выдумать окно;
/// - `maxOutputTokens` не берётся из `CardGenerationService` (8192 — это
///   резерв приложения, а не лимит модели);
/// - `pricing` и лимиты изображений не заполняются предположениями.
ModelCapabilities resolveModelCapabilities(ProviderAccount account) {
  final ProviderPreset? preset = account.presetId == null
      ? null
      : providerPresetById(account.presetId!);
  final ProviderPresetModel? presetModel = preset?.modelById(account.modelId);

  final int? contextWindowTokens = presetModel?.contextTokens;
  final CapabilitySource contextSource = contextWindowTokens == null
      ? CapabilitySource.unknown
      : CapabilitySource.preset;

  final CapabilitySource configuredSource =
      account.capabilitiesSource == CapabilitySource.unknown
      ? CapabilitySource.user
      : account.capabilitiesSource;

  CapabilitySource sourceFor(Object? value) =>
      value == null ? CapabilitySource.unknown : configuredSource;

  final int? maxImagesPerRequest = account.maxImagesPerRequest;
  final int? maxImageBytesPerImage = account.maxImageBytes;
  final int? maxRequestBytes = account.maxRequestBytes;
  final GenerationPricing? pricing = account.pricing;

  return ModelCapabilities(
    contextWindowTokens: contextWindowTokens,
    // Отдельный входной лимит, потолок карточек, лимит изображений на запрос,
    // сторона изображения нигде не хранятся: пока это неизвестно.
    maxOutputTokens: account.maxOutputTokens,
    maxImagesPerRequest: maxImagesPerRequest,
    maxImageBytesPerImage: maxImageBytesPerImage,
    maxRequestBytes: maxRequestBytes,
    supportsVision: account.supportsVision,
    supportsPdfDocumentPart: account.protocol.supportsPdfAttachments,
    // strict-схема у конкретной модели в репозитории не подтверждена:
    // OpenAI-совместимый протокол переключается по лестнице ADR-021.
    supportsStrictJsonSchema: null,
    tokenizer: TokenizerKind.unknown,
    imageTokens: null,
    pricing: pricing,
    contextSource: contextSource,
    outputSource: sourceFor(account.maxOutputTokens),
    imageSource: sourceFor(maxImagesPerRequest ?? maxImageBytesPerImage),
    pricingSource: sourceFor(pricing),
  );
}
