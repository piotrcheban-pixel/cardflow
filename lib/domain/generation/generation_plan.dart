/// План генерации, его валидность и оценка работы (разделы D.8/G.6 аудита
/// TASK 01).
///
/// План строится **до** первого API-запроса: он фиксирует фрагменты,
/// единицы контента, изображения-части и «только каталог», лимит карточек
/// каждого фрагмента, отброшенные единицы с причиной, бюджет и оценку.
/// Ни одна единица не исчезает молча: всё, что не попало во фрагмент,
/// обязано оказаться в [GenerationPlan.omitted] (D.4.10).
///
/// План не сериализуется в БД: `plan_json` в `generation_jobs` не добавляется
/// (K.2), а материалы в БД не пишутся (SPEC 3.4). Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';

/// Режим плана: по материалам или только по теме пользователя (ADR-024).
enum GenerationMode {
  /// План по документам/вложениям пользователя.
  materials,

  /// Генерация без материалов: тема и пожелания в пользовательском запросе.
  ///
  /// Такой план не содержит единиц содержимого и изображений: материалы
  /// (`<materials>`) пусты, тема уходит в `<wishes>`. Пустой документ,
  /// `TextPiece` или фиктивная `ContentUnit` для этого не создаются.
  promptOnly,
}

/// Вид фрагмента плана.
enum ChunkKind {
  /// Только текст.
  text,

  /// Текст и изображения.
  mixed,

  /// Только изображения (каталог + части).
  images,

  /// Только строки каталога `<images>` (без image-частей).
  catalog,

  /// Фрагмент без материалов: модель генерирует по теме из `<wishes>`.
  promptOnly,
}

/// Ссылка на единицу контента внутри фрагмента (ids + смещения/токены).
class UnitSpan {
  /// Создаёт ссылку на единицу.
  const UnitSpan({
    required this.unitId,
    required this.start,
    required this.end,
    required this.tokens,
  }) : assert(unitId != '', 'У ссылки обязан быть id единицы'),
       assert(start >= 0),
       assert(end >= start),
       assert(tokens >= 0, 'Токены не могут быть отрицательными');

  /// Стабильный id единицы (`doc:…`, `img:…`, `att:…`).
  final String unitId;

  /// Начало в тексте фрагмента.
  final int start;

  /// Конец в тексте фрагмента (исключительно).
  final int end;

  /// Оценка токенов единицы.
  final int tokens;

  @override
  String toString() => 'UnitSpan($unitId, $start..$end, $tokens)';
}

/// Причина, по которой единица не попала во фрагмент (D.4.10).
enum OmittedReason {
  /// Не помещается в бюджет.
  budget,

  /// Превышен лимит изображений провайдера.
  providerImageCap,

  /// Не помещается в лимит тела запроса.
  payload,

  /// Формат/модальность не поддерживается.
  unsupported,
}

/// Единица контента, оставшаяся вне фрагментов, с явной причиной.
class OmittedUnit {
  /// Создаёт запись об отброшенной единице.
  const OmittedUnit({
    required this.unitId,
    required this.reason,
    required this.tokens,
    this.documentId,
  }) : assert(unitId != ''),
       assert(tokens >= 0, 'Токены не могут быть отрицательными');

  /// Стабильный id единицы.
  final String unitId;

  /// Причина (для предупреждения в UI).
  final OmittedReason reason;

  /// Оценка токенов единицы.
  final int tokens;

  /// id документа-источника, если применимо.
  final String? documentId;

  @override
  String toString() => 'OmittedUnit($unitId, ${reason.name}, $tokens)';
}

/// Код предупреждения плана (строки для пользователя — ARB, раздел H.4).
enum PlanWarningCode {
  /// Есть неизвестные возможности модели (окно/лимиты/цены).
  unknownCapabilities,

  /// Часть изображений уходит только в каталоге, без байтов.
  catalogOnlyImages,

  /// Сумма лимитов карточек превышает заказ пользователя.
  cardsAboveRequested,

  /// Заказ пользователя больше, чем план может выдать.
  requestedAbovePlan,

  /// Часть единиц содержимого не попала в план — см. [GenerationPlan.omitted].
  omittedUnits,
}

/// Вид валидности плана.
enum PlanValidityKind {
  /// План выполним без предупреждений.
  valid,

  /// План выполним, но есть предупреждения.
  warnings,

  /// План невыполним — запуск блокируется.
  invalid,
}

/// Причина невыполнимости плана.
enum PlanInvalidReason {
  /// Бюджета входа меньше минимально рабочего (окно/обвязка/вывод).
  contextWindowTooSmall,

  /// Единица не помещается даже после исчерпания глубины дробления.
  unitTooLarge,

  /// Тело запроса не помещается после сокращения image-частей.
  payloadTooLarge,

  /// В материалах есть изображения, а у модели нет Vision.
  imagesWithoutVision,

  /// План потребовал больше фрагментов, чем допускает технический предохранитель
  /// (`GenerationChunkPlannerConfig.maxChunks`): содержимое не дробится дальше.
  tooManyChunks,
}

/// Результат проверки плана: valid/warnings/invalid(+причина).
class PlanValidity {
  const PlanValidity._({
    required this.kind,
    this.warnings = const <PlanWarningCode>[],
    this.reason,
    this.neededTokens,
    this.availableTokens,
  });

  /// План выполним без предупреждений.
  const PlanValidity.valid() : this._(kind: PlanValidityKind.valid);

  /// План выполним с предупреждениями.
  const PlanValidity.warnings(List<PlanWarningCode> warnings)
    : this._(kind: PlanValidityKind.warnings, warnings: warnings);

  /// План невыполним: [reason], при нехватке бюджета — сколько нужно/есть.
  const PlanValidity.invalid(
    PlanInvalidReason reason, {
    int? neededTokens,
    int? availableTokens,
  }) : this._(
         kind: PlanValidityKind.invalid,
         reason: reason,
         neededTokens: neededTokens,
         availableTokens: availableTokens,
       );

  /// Вид валидности.
  final PlanValidityKind kind;

  /// Предупреждения (для [PlanValidityKind.warnings]).
  final List<PlanWarningCode> warnings;

  /// Причина (для [PlanValidityKind.invalid]).
  final PlanInvalidReason? reason;

  /// Сколько токенов нужно (для нехватки бюджета).
  final int? neededTokens;

  /// Сколько токенов доступно (для нехватки бюджета).
  final int? availableTokens;

  /// true, если план можно запускать (warnings не блокируют).
  bool get isValid => kind != PlanValidityKind.invalid;

  /// true, если план заблокирован.
  bool get isInvalid => kind == PlanValidityKind.invalid;

  /// true, если есть предупреждения.
  bool get hasWarnings => warnings.isNotEmpty;

  @override
  String toString() => switch (kind) {
    PlanValidityKind.valid => 'PlanValidity.valid',
    PlanValidityKind.warnings =>
      'PlanValidity.warnings(${warnings.map((e) => e.name).join(',')})',
    PlanValidityKind.invalid => 'PlanValidity.invalid(${reason?.name})',
  };
}

/// Один фрагмент плана: что уйдёт в одном запросе.
///
/// Обычный фрагмент обязан содержать хотя бы одну единицу содержимого
/// (D.4.9); исключение — [ChunkKind.promptOnly], где материалов нет по
/// определению (тема передаётся в `<wishes>`).
class PlannedChunk {
  /// Создаёт фрагмент; пустой фрагмент запрещён (D.4.9), `limit` ≥ 1 (D.7.3).
  PlannedChunk({
    required this.index,
    required this.kind,
    required this.textTokens,
    required this.imageTokens,
    required this.bodyBytes,
    required this.limit,
    List<UnitSpan> units = const <UnitSpan>[],
    List<DocumentImage> imageParts = const <DocumentImage>[],
    List<DocumentImage> catalogOnly = const <DocumentImage>[],
    List<String> imagePartIds = const <String>[],
    List<String> catalogOnlyIds = const <String>[],
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
    this.splitDepth = 0,
    this.materialsText = '',
  }) : assert(index >= 1, 'Фрагменты нумеруются с 1'),
       assert(limit >= 1, 'Лимит карточек запланированного фрагмента ≥ 1'),
       assert(textTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(imageTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(bodyBytes >= 0),
       assert(splitDepth >= 0),
       assert(
         kind == ChunkKind.promptOnly
             ? units.isEmpty &&
                   imageParts.isEmpty &&
                   catalogOnly.isEmpty &&
                   attachments.isEmpty
             : units.isNotEmpty ||
                   imageParts.isNotEmpty ||
                   catalogOnly.isNotEmpty ||
                   attachments.isNotEmpty,
         kind == ChunkKind.promptOnly
             ? 'Фрагмент по теме не содержит единиц материалов'
             : 'Пустой фрагмент запрещён (D.4.9)',
       ),
       units = List<UnitSpan>.unmodifiable(units),
       imageParts = List<DocumentImage>.unmodifiable(imageParts),
       catalogOnly = List<DocumentImage>.unmodifiable(catalogOnly),
       imagePartIds = List<String>.unmodifiable(imagePartIds),
       catalogOnlyIds = List<String>.unmodifiable(catalogOnlyIds),
       attachments = List<GenerationAttachment>.unmodifiable(attachments);

  /// Фрагмент «по теме»: без материалов, только `<wishes>`.
  factory PlannedChunk.promptOnly({
    required int index,
    required int limit,
    int bodyBytes = 0,
    int splitDepth = 0,
  }) {
    return PlannedChunk(
      index: index,
      kind: ChunkKind.promptOnly,
      textTokens: 0,
      imageTokens: 0,
      bodyBytes: bodyBytes,
      limit: limit,
      splitDepth: splitDepth,
    );
  }

  /// Номер фрагмента (с 1) для прогресса «фрагмент K из M».
  final int index;

  /// Вид фрагмента.
  final ChunkKind kind;

  /// Единицы содержимого фрагмента.
  final List<UnitSpan> units;

  /// Изображения, которые уходят image-частями (байты).
  final List<DocumentImage> imageParts;

  /// Изображения, которые остаются только в каталоге `<images>`.
  final List<DocumentImage> catalogOnly;

  /// Стабильные id изображений-частей (`img:<файл>#<n>`, раздел E.1).
  ///
  /// Нужны для проверяемого инварианта «каждая единица учтена»
  /// (`GenerationPlanCoverage`) и для разрешения `image_id` без повторной
  /// сборки каталога; соответствуют [imageParts] по порядку.
  final List<String> imagePartIds;

  /// Стабильные id изображений, оставшихся только в каталоге; соответствуют
  /// [catalogOnly] по порядку.
  final List<String> catalogOnlyIds;

  /// Вложения пользователя (страницы скана/изображения).
  final List<GenerationAttachment> attachments;

  /// Токены текста.
  final int textTokens;

  /// Токены изображений и меток.
  final int imageTokens;

  /// Оценка размера тела запроса, байт (текст + base64 + JSON).
  final int bodyBytes;

  /// Максимальное число карточек в ответе на фрагмент.
  final int limit;

  /// Глубина дробления (0 — исходный фрагмент).
  final int splitDepth;

  /// Текст материалов фрагмента **в памяти** (`Файл: <имя>` + разделы, D.5).
  ///
  /// План не сериализуется в БД (K.2) и материалы в БД не пишутся (SPEC 3.4):
  /// строка живёт только внутри запуска и нужна пайплайну, чтобы отправить
  /// запрос без повторной сборки текста. У фрагмента без текста (только
  /// изображения/вложения или prompt-only) — пустая строка.
  final String materialsText;

  /// true, если фрагмент генерирует по теме без материалов.
  bool get isPromptOnly => kind == ChunkKind.promptOnly;

  /// Копия с изменёнными полями (восстановление: дробление, лимит вывода).
  PlannedChunk copyWith({
    int? index,
    ChunkKind? kind,
    List<UnitSpan>? units,
    List<DocumentImage>? imageParts,
    List<DocumentImage>? catalogOnly,
    List<String>? imagePartIds,
    List<String>? catalogOnlyIds,
    List<GenerationAttachment>? attachments,
    int? textTokens,
    int? imageTokens,
    int? bodyBytes,
    int? limit,
    int? splitDepth,
    String? materialsText,
  }) {
    return PlannedChunk(
      index: index ?? this.index,
      kind: kind ?? this.kind,
      units: units ?? this.units,
      imageParts: imageParts ?? this.imageParts,
      catalogOnly: catalogOnly ?? this.catalogOnly,
      imagePartIds: imagePartIds ?? this.imagePartIds,
      catalogOnlyIds: catalogOnlyIds ?? this.catalogOnlyIds,
      attachments: attachments ?? this.attachments,
      textTokens: textTokens ?? this.textTokens,
      imageTokens: imageTokens ?? this.imageTokens,
      bodyBytes: bodyBytes ?? this.bodyBytes,
      limit: limit ?? this.limit,
      splitDepth: splitDepth ?? this.splitDepth,
      materialsText: materialsText ?? this.materialsText,
    );
  }

  /// Суммарные токены фрагмента (текст + изображения).
  int get totalTokens => textTokens + imageTokens;

  /// Суммарные байты image-частей и вложений (до base64).
  int get imagePartBytes {
    int total = 0;
    for (final DocumentImage image in imageParts) {
      total += image.bytes.length;
    }
    for (final GenerationAttachment attachment in attachments) {
      total += attachment.bytes.length;
    }
    return total;
  }

  @override
  String toString() =>
      'PlannedChunk($index, ${kind.name}, text: $textTokens, '
      'images: $imageTokens, limit: $limit, depth: $splitDepth)';
}

/// Оценка работы до первого запроса (G.6).
///
/// Стоимость — nullable: неизвестная цена даёт `null`, а не 0.
class GenerationEstimate {
  /// Создаёт оценку.
  const GenerationEstimate({
    required this.inputTextTokens,
    required this.imageTokens,
    required this.fixedPromptTokens,
    required this.wrapperTokens,
    required this.schemaTokens,
    required this.catalogTokens,
    required this.reservedOutputTokens,
    required this.expectedOutputTokens,
    required this.totalTokens,
    required this.plannedChunks,
    required this.plannedRequests,
    required this.retryAllowanceRequests,
    required this.pricingState,
    required this.estimatorVersion,
    this.inputCost,
    this.outputCost,
    this.totalCost,
    this.currency,
    this.unknownFields = const <String>[],
    this.confidence = 0,
  }) : assert(inputTextTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(imageTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(fixedPromptTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(wrapperTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(schemaTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(catalogTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(reservedOutputTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(expectedOutputTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(totalTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(plannedChunks >= 0),
       assert(plannedRequests >= 0),
       assert(retryAllowanceRequests >= 0),
       assert(estimatorVersion != '', 'У оценки обязана быть версия'),
       assert(
         confidence >= 0 && confidence <= 1,
         'Уверенность оценки — доля 0..1',
       ),
       assert(
         pricingState != PricingState.complete ||
             (inputCost != null &&
                 outputCost != null &&
                 totalCost != null &&
                 currency != null),
         'При полных ценах стоимость обязана быть посчитана',
       );

  /// Токены текста материалов.
  final int inputTextTokens;

  /// Токены изображений (image-части + каталог).
  final int imageTokens;

  /// Токены системного промпта.
  final int fixedPromptTokens;

  /// Токены обёртки пользовательского сообщения.
  final int wrapperTokens;

  /// Токены схемы ответа.
  final int schemaTokens;

  /// Токены каталога `<images>` и подписей частей.
  final int catalogTokens;

  /// Резерв вывода.
  final int reservedOutputTokens;

  /// Ожидаемый вывод.
  final int expectedOutputTokens;

  /// Итог оценки.
  final int totalTokens;

  /// Число фрагментов плана.
  final int plannedChunks;

  /// Число запросов плана.
  final int plannedRequests;

  /// Допуск на повторы.
  final int retryAllowanceRequests;

  /// Стоимость входа; `null` — неизвестно.
  final double? inputCost;

  /// Стоимость выхода; `null` — неизвестно.
  final double? outputCost;

  /// Суммарная стоимость; `null` — неизвестно (никогда не 0 как заглушка).
  final double? totalCost;

  /// Валюта стоимости; `null` — неизвестна.
  final String? currency;

  /// Состояние цен.
  final PricingState pricingState;

  /// Поля, значения которых неизвестны.
  final List<String> unknownFields;

  /// Уверенность оценки (0..1; 0 — неизвестна).
  final double confidence;

  /// Версия оценки (для калибровки).
  final String estimatorVersion;

  /// true, если стоимость посчитана полностью.
  bool get hasKnownCost =>
      pricingState == PricingState.complete && totalCost != null;

  @override
  String toString() =>
      'GenerationEstimate(total: $totalTokens, chunks: $plannedChunks, '
      'cost: ${totalCost ?? 'unknown'}, pricing: ${pricingState.name})';
}

/// План генерации: фрагменты, потери, бюджет и оценка (D.8).
class GenerationPlan {
  /// Создаёт план; списки становятся неизменяемыми.
  GenerationPlan({
    required this.validity,
    required this.estimate,
    required this.budget,
    List<PlannedChunk> chunks = const <PlannedChunk>[],
    List<OmittedUnit> omitted = const <OmittedUnit>[],
    this.requestedCards = 0,
    this.retryAllowanceRequests = 0,
    List<String> unknownFields = const <String>[],
    this.mode = GenerationMode.materials,
    this.promptOnlyPrompt,
  }) : assert(requestedCards >= 0),
       assert(retryAllowanceRequests >= 0),
       assert(
         mode == GenerationMode.materials ||
             (promptOnlyPrompt != null && promptOnlyPrompt.trim().isNotEmpty),
         'Плану по теме нужен пользовательский запрос',
       ),
       assert(
         mode == GenerationMode.promptOnly ||
             !chunks.any((PlannedChunk chunk) => chunk.isPromptOnly),
         'Фрагмент по теме допустим только в prompt-only плане',
       ),
       chunks = List<PlannedChunk>.unmodifiable(chunks),
       omitted = List<OmittedUnit>.unmodifiable(omitted),
       unknownFields = List<String>.unmodifiable(unknownFields);

  /// Фрагменты плана в порядке отправки.
  final List<PlannedChunk> chunks;

  /// Единицы, не попавшие во фрагменты, с причиной.
  final List<OmittedUnit> omitted;

  /// Заказ карточек от пользователя (0 — не задан).
  final int requestedCards;

  /// Допуск на повторы (отдельно от плановых запросов).
  final int retryAllowanceRequests;

  /// Оценка работы (G.6).
  final GenerationEstimate estimate;

  /// Трассировка бюджета (D.1).
  final BudgetTrace budget;

  /// Поля, значения которых неизвестны.
  final List<String> unknownFields;

  /// Валидность плана.
  final PlanValidity validity;

  /// Режим плана: материалы или генерация по теме.
  final GenerationMode mode;

  /// Пользовательский запрос (тема + пожелания) prompt-only плана.
  final String? promptOnlyPrompt;

  /// Сумма лимитов карточек по фрагментам (вычисляется из [chunks]).
  int get plannedCards {
    int total = 0;
    for (final PlannedChunk chunk in chunks) {
      total += chunk.limit;
    }
    return total;
  }

  /// Сколько карточек план реально может выдать (D.7: без молчаливого среза).
  ///
  /// Равно [plannedCards]; отдельное имя фиксирует контракт «заказ vs план»
  /// для UI: пользователь видит [requestedCards] и [achievableCards], а не
  /// подменённое число.
  int get achievableCards => plannedCards;

  /// Число запросов плана (вычисляется из [chunks]).
  int get plannedRequests => chunks.length;

  /// true, если план не содержит фрагментов.
  bool get isEmpty => chunks.isEmpty;

  /// true, если план можно запускать: он валиден и содержит фрагменты.
  bool get isExecutable => validity.isValid && chunks.isNotEmpty;

  /// true, если были отброшенные единицы (потери не скрыты).
  bool get hasOmittedUnits => omitted.isNotEmpty;

  /// true, если запрошено больше карточек, чем план может выдать.
  bool get requestedAboveAchievable =>
      requestedCards > 0 && achievableCards < requestedCards;

  /// true, если сумма лимитов превышает заказ (D.5 невозможно — предупреждение).
  bool get achievableAboveRequested =>
      requestedCards > 0 && achievableCards > requestedCards;

  /// true, если план генерирует без материалов, по теме.
  bool get isPromptOnly => mode == GenerationMode.promptOnly;

  @override
  String toString() =>
      'GenerationPlan(${mode.name}, chunks: ${chunks.length}, '
      'omitted: ${omitted.length}, cards: $plannedCards/$requestedCards, '
      '${validity.kind.name})';
}
