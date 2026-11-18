/// Адаптивный планировщик фрагментов генерации (разделы D.4–D.7 аудита
/// TASK 01, `docs/adaptive-generation-architecture.md`).
///
/// Планировщик получает перечень единиц содержимого ([ContentInventory]),
/// возможности модели ([ModelCapabilities]) и фиксированную обвязку запроса
/// (системный промпт, схема ответа, обёртка) и строит [GenerationPlan] **до**
/// первого API-запроса:
///
/// - бюджет входа считается по формуле D.1 через [GenerationBudget] (окно
///   контекста − резерв вывода − фиксированная обвязка − запас безопасности);
///   клампинга «всё равно 2 000» нет — при нехватке план невалиден;
/// - текст упаковывается жадно по смысловым границам (раздел → абзац →
///   предложение → строка → руна); предложение режется только если само
///   больше бюджета;
/// - изображения — полноценные единицы: они сохраняют `image_id`, привязку к
///   разделу/странице и каталог документа; не вошедшие в image-части остаются
///   в каталоге (`catalogOnly`) или уходят отдельным фрагментом-каталогом;
/// - количество карточек не берётся из «универсального 20»: потолок считается
///   из бюджета вывода модели и `maxCardsPerRequest`, а заказ пользователя
///   распределяется по фрагментам без молчаливого уменьшения;
/// - у каждой единицы содержимого есть состояние: во фрагменте (units/
///   imageParts/attachments), в каталоге (`catalogOnly`) или в
///   [GenerationPlan.omitted] с причиной. Проверка покрытия —
///   [GenerationPlanCoverage.check].
///
/// Технические предохранители (все — явные поля
/// [GenerationChunkPlannerConfig], не «магические» числа модели): максимальное
/// число фрагментов, глубина дробления, допущения по лимитам запроса, когда
/// возможности модели неизвестны. Домен не зависит от Flutter.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/generation_request_limits.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// Префикс строки-заголовка файла в `<materials>` (SPEC A8.1: «Файл: <имя>»).
///
/// Константа продублирована здесь, чтобы планировщик не зависел от
/// `generation_chunker.dart` (фасад сам зависит от планировщика).
const String _fileHeaderPrefix = 'Файл: ';

/// Строка каталога `<images>` для изображения [image] с порядковым номером
/// [index] (0 — первое изображение документа).
///
/// Реальный формат строки (`id | файл | подпись | окружающий текст`) живёт в
/// API-слое (`imageCatalogLine`); планировщик получает построитель извне,
/// чтобы не дублировать форматирование. `null` — используется приближение по
/// полям изображения (для автономных тестов/вызовов).
typedef ImageCatalogLineBuilder = String Function(ImageRef image, int index);

/// Допущения и технические предохранители планировщика.
///
/// Значения — конфигурация приложения, а **не** характеристики моделей:
/// они применяются, только когда у аккаунта нет подтверждённого значения, и
/// попадают в `GenerationPlan.unknownFields`/предупреждения.
class GenerationChunkPlannerConfig {
  /// Создаёт конфигурацию.
  const GenerationChunkPlannerConfig({
    this.softTargetMaterialTokensPerCard = 6000,
    this.minSoftTargetMaterialTokens = 512,
    this.assumedMaxImagesPerChunk = 8,
    this.assumedMaxImageBytesPerImage = 10 * 1024 * 1024,
    this.assumedMaxImageBytesPerChunk = 24 * 1024 * 1024,
    this.assumedMaxRequestBytes = 32 * 1024 * 1024,
    this.jsonBodyOverheadBytes = 1024,
    this.maxChunks = 512,
    this.maxSplitDepth = 3,
    this.retryAllowanceRequests = 0,
  }) : assert(softTargetMaterialTokensPerCard > 0),
       assert(minSoftTargetMaterialTokens > 0),
       assert(assumedMaxImagesPerChunk > 0),
       assert(assumedMaxImageBytesPerImage > 0),
       assert(assumedMaxImageBytesPerChunk > 0),
       assert(assumedMaxRequestBytes > 0),
       assert(jsonBodyOverheadBytes >= 0),
       assert(maxChunks > 0, 'Предохранитель числа фрагментов должен быть > 0'),
       assert(maxSplitDepth >= 0);

  /// Сколько токенов материала ориентировочно нужно на одну карточку (D.3).
  ///
  /// Мягкая цель заполнения: не платить за 1M контекста ради нескольких
  /// карточек. Значение подлежит калибровке (не метаданные провайдера).
  final int softTargetMaterialTokensPerCard;

  /// Минимальная мягкая цель фрагмента при подстройке под заказ.
  ///
  /// Не даём создавать крошечные фрагменты из маленького материала: если
  /// материала на все запросы не хватает, деление не увеличит число карточек,
  /// а только добавит запросов. Значение — конфигурация приложения.
  final int minSoftTargetMaterialTokens;

  /// Сколько image-частей допускается в одном запросе, если модель не сообщает
  /// лимит (существующая политика приложения, L-29).
  final int assumedMaxImagesPerChunk;

  /// Максимальный размер одного изображения, если модель его не сообщает
  /// (существующая политика приложения, L-28).
  final int assumedMaxImageBytesPerImage;

  /// Максимальный суммарный размер изображений запроса, если модель его не
  /// сообщает (существующая политика приложения, L-30).
  final int assumedMaxImageBytesPerChunk;

  /// Защитный потолок тела HTTP-запроса, если возможности модели его не дают
  /// (E.5). Допущение, а не факт провайдера.
  final int assumedMaxRequestBytes;

  /// Служебный запас JSON-обёртки тела запроса (байт).
  final int jsonBodyOverheadBytes;

  /// Технический предохранитель от runaway-дробления (класс D).
  final int maxChunks;

  /// Максимальная глубина дробления текста (D.6/F.3): после неё — жёсткое
  /// деление по рунам.
  final int maxSplitDepth;

  /// Сколько запросов заложено на повторы (F.2); в оценку попадает отдельно.
  final int retryAllowanceRequests;
}

/// Фиксированная обвязка запроса, не зависящая от материалов.
///
/// Системный промпт, JSON-схема ответа и обёртка пользовательского сообщения
/// отправляются в каждом запросе, поэтому вычитаются из окна контекста.
class GenerationOverheadTokens {
  /// Создаёт обвязку.
  const GenerationOverheadTokens({
    this.systemPromptTokens = 0,
    this.schemaTokens = 0,
    this.wrapperTokens = 0,
  }) : assert(systemPromptTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(schemaTokens >= 0, 'Токены не могут быть отрицательными'),
       assert(wrapperTokens >= 0, 'Токены не могут быть отрицательными');

  /// Нулевая обвязка (для тестов/автономного планирования).
  static const GenerationOverheadTokens none = GenerationOverheadTokens();

  /// Токены системного промпта.
  final int systemPromptTokens;

  /// Токены проекции JSON-схемы ответа.
  final int schemaTokens;

  /// Токены обёртки `<materials>/<wishes>/<limit>/<images>`.
  final int wrapperTokens;

  /// Суммарная фиксированная обвязка.
  int get fixedTokens => systemPromptTokens + schemaTokens + wrapperTokens;

  @override
  String toString() =>
      'GenerationOverheadTokens($systemPromptTokens + $schemaTokens + '
      '$wrapperTokens)';
}

/// Планировщик фрагментов: бюджет, упаковка, изображения, лимиты карточек.
class GenerationChunkPlanner {
  /// Создаёт планировщик.
  const GenerationChunkPlanner({
    this.estimator = const HeuristicContentTokenEstimator(),
    this.config = const GenerationChunkPlannerConfig(),
    this.catalogLineBuilder,
  });

  /// Единый оценщик единиц содержимого (заменяется `GenerationEstimator`).
  final ContentTokenEstimator estimator;

  /// Допущения и предохранители.
  final GenerationChunkPlannerConfig config;

  /// Построитель строк каталога `<images>`; `null` — приближение по полям.
  final ImageCatalogLineBuilder? catalogLineBuilder;

  /// Строит план по перечню содержимого и возможностям модели.
  ///
  /// [requestedCards] — сколько карточек запросил пользователь (`null` — не
  /// задавал). Значение не уменьшается молча: если план не может его выдать,
  /// в плане появляется предупреждение `requestedAbovePlan`; если фрагментов
  /// больше, чем карточек, — `cardsAboveRequested`.
  GenerationPlan plan({
    required ContentInventory inventory,
    required ModelCapabilities capabilities,
    GenerationOverheadTokens overhead = GenerationOverheadTokens.none,
    int? requestedCards,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
    ImageCatalogLineBuilder? catalogLineBuilder,
  }) {
    assert(
      requestedCards == null || requestedCards > 0,
      'Заказ карточек должен быть положительным или null',
    );
    final _PlanRun run = _PlanRun(
      estimator: estimator,
      config: config,
      capabilities: capabilities,
      overhead: overhead,
      budgetConfig: budgetConfig,
      catalogLineBuilder: catalogLineBuilder ?? this.catalogLineBuilder,
      requestedCards: requestedCards,
    );
    return run.execute(inventory);
  }
}

/// Проверка покрытия плана: все исходные единицы учтены (задание 3.6).
///
/// Используется тестами и диагностикой: планировщик обязан либо включить
/// единицу во фрагмент (в том числе строкой каталога), либо записать её в
/// [GenerationPlan.omitted] с причиной. Помогает ловить регрессии «молча
/// потеряли изображение/абзац/страницу вложения».
class GenerationPlanCoverage {
  const GenerationPlanCoverage._({
    required this.missingUnits,
    required this.duplicatedUnits,
    required this.uncoveredImages,
  });

  /// Проверяет покрытие [plan] для [inventory].
  static GenerationPlanCoverage check({
    required ContentInventory inventory,
    required GenerationPlan plan,
  }) {
    final List<String> expectedPieces = <String>[
      for (final DocumentUnit document in inventory.documents)
        for (final SectionUnit section in document.sections)
          for (final TextPiece piece in section.pieces) piece.id,
    ];
    final Set<String> expectedPieceSet = expectedPieces.toSet();
    final Map<String, int> spanCounts = <String, int>{};
    final Set<String> coveredPieces = <String>{};
    for (final PlannedChunk chunk in plan.chunks) {
      for (final UnitSpan span in chunk.units) {
        spanCounts.update(
          span.unitId,
          (int value) => value + 1,
          ifAbsent: () => 1,
        );
        final String? root = _rootPieceId(span.unitId, expectedPieceSet);
        if (root != null) coveredPieces.add(root);
      }
    }
    final List<String> missingText = <String>[
      for (final String id in expectedPieces)
        if (!coveredPieces.contains(id)) id,
    ];
    final List<String> duplicatedUnits = <String>[
      for (final MapEntry<String, int> entry in spanCounts.entries)
        if (entry.value > 1) entry.key,
    ];

    final List<String> expectedImages = <String>[
      for (final ImageRef image in inventory.allImages) image.id,
    ];
    final Set<String> plannedImages = <String>{
      for (final PlannedChunk chunk in plan.chunks) ...chunk.imagePartIds,
      for (final PlannedChunk chunk in plan.chunks) ...chunk.catalogOnlyIds,
      for (final OmittedUnit omitted in plan.omitted) omitted.unitId,
    };
    final List<String> uncoveredImages = <String>[
      for (final String id in expectedImages)
        if (!plannedImages.contains(id)) id,
    ];

    final Map<String, int> expectedPages = <String, int>{};
    for (final AttachmentUnit unit in inventory.attachments) {
      for (final PageUnit page in unit.pages) {
        expectedPages.update(
          page.id,
          (int value) => value + 1,
          ifAbsent: () => 1,
        );
      }
    }
    final Map<String, int> plannedPages = <String, int>{};
    for (final PlannedChunk chunk in plan.chunks) {
      for (final GenerationAttachment attachment in chunk.attachments) {
        final String id = _attachmentPageId(attachment);
        plannedPages.update(id, (int value) => value + 1, ifAbsent: () => 1);
      }
    }
    final List<String> missingPages = <String>[
      for (final MapEntry<String, int> entry in expectedPages.entries)
        if ((plannedPages[entry.key] ?? 0) < entry.value) entry.key,
    ];
    final List<String> duplicatedPages = <String>[
      for (final MapEntry<String, int> entry in plannedPages.entries)
        if (entry.value > (expectedPages[entry.key] ?? 0)) entry.key,
    ];

    return GenerationPlanCoverage._(
      missingUnits: List<String>.unmodifiable(<String>[
        ...missingText,
        ...missingPages,
      ]),
      duplicatedUnits: List<String>.unmodifiable(<String>[
        ...duplicatedUnits,
        ...duplicatedPages,
      ]),
      uncoveredImages: List<String>.unmodifiable(uncoveredImages),
    );
  }

  /// Единицы текста/страницы вложений, которых нет ни в одном фрагменте.
  final List<String> missingUnits;

  /// Единицы, попавшие больше одного раза (полные id, включая под-фрагменты).
  final List<String> duplicatedUnits;

  /// Изображения, не попавшие ни в части, ни в каталог, ни в `omitted`.
  final List<String> uncoveredImages;

  /// true, если потери нет.
  bool get isComplete =>
      missingUnits.isEmpty &&
      duplicatedUnits.isEmpty &&
      uncoveredImages.isEmpty;

  @override
  String toString() =>
      'GenerationPlanCoverage(missing: ${missingUnits.length}, '
      'duplicated: ${duplicatedUnits.length}, '
      'uncoveredImages: ${uncoveredImages.length})';
}

String? _rootPieceId(String spanId, Set<String> expectedPieces) {
  if (expectedPieces.contains(spanId)) return spanId;
  for (
    int index = spanId.indexOf('~');
    index >= 0;
    index = spanId.indexOf('~', index + 1)
  ) {
    final String prefix = spanId.substring(0, index);
    if (expectedPieces.contains(prefix)) return prefix;
  }
  return null;
}

String _attachmentPageId(GenerationAttachment attachment) {
  final String unitId = contentAttachmentId(
    attachment.fileName,
    groupKey: attachment.groupKey,
  );
  return contentPageId(unitId, attachment.pageNumber);
}

// ---------------------------------------------------------------------------
// Реализация
// ---------------------------------------------------------------------------

/// Состояние одного фрагмента во время упаковки.
class _ChunkDraft {
  final List<_FragmentRecord> fragments = <_FragmentRecord>[];
  final StringBuffer text = StringBuffer();
  final List<String> documentIds = <String>[];
  final List<String> sectionIds = <String>[];
  final List<_ImageEntry> parts = <_ImageEntry>[];
  final List<_ImageEntry> extraCatalog = <_ImageEntry>[];
  final List<_PlannedAttachment> attachments = <_PlannedAttachment>[];
  final Set<String> partIds = <String>{};

  int textTokens = 0;
  int textBytes = 0;
  int labelTokens = 0;
  int labelBytes = 0;
  String? lastDocumentId;
  String? lastSectionId;
  int splitDepth = 0;

  bool get isEmpty =>
      fragments.isEmpty &&
      parts.isEmpty &&
      extraCatalog.isEmpty &&
      attachments.isEmpty;

  bool get isNotEmpty => !isEmpty;

  int get imageTokens => parts.fold<int>(
    0,
    (int total, _ImageEntry part) => total + part.image.tokens,
  );

  int get imageBytes => parts.fold<int>(
    0,
    (int total, _ImageEntry part) => total + part.image.image.bytes.length,
  );

  int get attachmentTokens => attachments.fold<int>(
    0,
    (int total, _PlannedAttachment attachment) => total + attachment.tokens,
  );

  int get attachmentBytes => attachments.fold<int>(
    0,
    (int total, _PlannedAttachment attachment) => total + attachment.bytes,
  );

  int get imagePartCount => parts.length + attachments.length;

  int get totalImageBytes => imageBytes + attachmentBytes;
}

/// Запись о размещённом фрагменте текста: id единицы и границы в тексте
/// фрагмента (для [UnitSpan]).
class _FragmentRecord {
  const _FragmentRecord({
    required this.unitId,
    required this.tokens,
    required this.start,
    required this.end,
  });

  final String unitId;
  final int tokens;
  final int start;
  final int end;
}

/// Фрагмент текста после дробления (может быть частью [TextPiece]).
class _TextFragment {
  const _TextFragment({
    required this.unitId,
    required this.text,
    required this.kind,
    required this.tokens,
    required this.splitDepth,
  });

  /// id единицы плана (исходный или производный `…~N`).
  final String unitId;

  /// Текст фрагмента (конкатенация даёт исходный текст единицы).
  final String text;

  /// Вид границы.
  final TextPieceKind kind;

  /// Оценка токенов.
  final int tokens;

  /// Глубина дробления.
  final int splitDepth;
}

/// Строка каталога изображения с посчитанными токенами и байтами.
class _ImageEntry {
  const _ImageEntry({
    required this.image,
    required this.line,
    required this.tokens,
    required this.bytes,
  });

  final ImageRef image;
  final String line;
  final int tokens;
  final int bytes;

  String get id => image.id;
}

/// Данные документа: каталог и изображения разделов.
class _DocumentPlanData {
  _DocumentPlanData({required this.document, required this.catalog}) {
    for (final _ImageEntry entry in catalog) {
      byId[entry.id] = entry;
    }
  }

  final DocumentUnit document;
  final List<_ImageEntry> catalog;
  final Map<String, _ImageEntry> byId = <String, _ImageEntry>{};
  final Map<String, List<_ImageEntry>> bySection =
      <String, List<_ImageEntry>>{};
}

/// Вложение, разложенное по страницам для упаковки.
class _PlannedAttachment {
  const _PlannedAttachment({
    required this.unit,
    required this.page,
    required this.tokens,
    required this.bytes,
  });

  final AttachmentUnit unit;
  final PageUnit page;
  final int tokens;
  final int bytes;

  int get labelTokens => 0;

  int get labelBytes => 0;
}

/// Кандидат на добавление во фрагмент (без мутации текущего состояния).
class _Candidate {
  const _Candidate({
    required this.textTokens,
    required this.textBytes,
    required this.labelTokens,
    required this.labelBytes,
    required this.parts,
    required this.partIds,
    required this.extraCatalog,
    required this.attachments,
    required this.documentIds,
  });

  final int textTokens;
  final int textBytes;
  final int labelTokens;
  final int labelBytes;
  final List<_ImageEntry> parts;
  final Set<String> partIds;
  final List<_ImageEntry> extraCatalog;
  final List<_PlannedAttachment> attachments;
  final List<String> documentIds;

  int get imageTokens => parts.fold<int>(
    0,
    (int total, _ImageEntry part) => total + part.image.tokens,
  );

  int get imageBytes => parts.fold<int>(
    0,
    (int total, _ImageEntry part) => total + part.image.image.bytes.length,
  );

  int get attachmentTokens => attachments.fold<int>(
    0,
    (int total, _PlannedAttachment attachment) => total + attachment.tokens,
  );

  int get attachmentBytes => attachments.fold<int>(
    0,
    (int total, _PlannedAttachment attachment) => total + attachment.bytes,
  );

  int get imagePartCount => parts.length + attachments.length;
}

/// Подобранный каталог и размеры тела.
class _Fit {
  const _Fit({
    required this.catalog,
    required this.catalogTokens,
    required this.catalogBytes,
    required this.bodyBytes,
  });

  final List<_ImageEntry> catalog;
  final int catalogTokens;
  final int catalogBytes;
  final int bodyBytes;
}

/// Результат попытки разместить единицу.
enum _PlaceResult {
  /// Размещено в текущем фрагменте.
  placed,

  /// Содержимое не влезло, но текущий фрагмент непуст: закрыть и повторить.
  needsNewChunk,

  /// Даже в пустом фрагменте не влезло — нужно дробить текст.
  split,
}

/// Внутренний сигнал о невыполнимости плана.
class _PlanAbort implements Exception {
  const _PlanAbort(this.reason, {this.neededTokens, this.availableTokens});

  final PlanInvalidReason reason;
  final int? neededTokens;
  final int? availableTokens;
}

/// Один прогон планирования.
class _PlanRun {
  _PlanRun({
    required this.estimator,
    required this.config,
    required this.capabilities,
    required this.overhead,
    required this.budgetConfig,
    required this.requestedCards,
    this.catalogLineBuilder,
  });

  final ContentTokenEstimator estimator;
  final GenerationChunkPlannerConfig config;
  final ModelCapabilities capabilities;
  final GenerationOverheadTokens overhead;
  final GenerationBudgetConfig budgetConfig;
  final int? requestedCards;
  final ImageCatalogLineBuilder? catalogLineBuilder;

  final List<_DocumentPlanData> _documents = <_DocumentPlanData>[];
  final Map<String, _DocumentPlanData> _documentById =
      <String, _DocumentPlanData>{};
  final List<_PlannedAttachment> _attachments = <_PlannedAttachment>[];
  final List<_ImageEntry> _orphanImages = <_ImageEntry>[];
  final Map<String, _ImageEntry> _allImageEntries = <String, _ImageEntry>{};
  final List<PageUnit> _inventoryPages = <PageUnit>[];

  final List<_ChunkDraft> _drafts = <_ChunkDraft>[];
  final List<OmittedUnit> _omitted = <OmittedUnit>[];
  final Set<String> _omittedIds = <String>{};
  final Set<String> _placedPartIds = <String>{};
  final Map<String, int> _splitCounters = <String, int>{};

  late final int _cardsByOutputCap;
  late final int _limitTarget;
  late final int _contentAllowance;
  int _softTarget = 1;
  late final int _maxImagesPerChunk;
  late final int _maxImageBytesPerImage;
  late final int _maxImageBytesPerRequest;
  late final int _payloadLimit;
  late final int _outputCap;
  late final GenerationRequestLimits _limits;

  /// SHA-256 байтов изображений, уже отправленных частями в этом плане.
  ///
  /// Одинаковые байты не отправляются дважды (L126): второе изображение
  /// остаётся в каталоге, а не молча выкидывается сервисом (TASK 03, D11).
  final Set<String> _placedPartDigests = <String>{};

  _ChunkDraft? _current;
  int _startedChunks = 0;
  bool _imageEstimateAssumed = false;

  /// Строит план.
  GenerationPlan execute(ContentInventory inventory) {
    try {
      _prepareBudget();
    } on _PlanAbort catch (abort) {
      return _invalid(
        abort.reason,
        neededTokens: abort.neededTokens,
        availableTokens: abort.availableTokens,
      );
    }
    _collectInventory(inventory);
    if (_documents.isEmpty && _attachments.isEmpty && _orphanImages.isEmpty) {
      return _emptyPlan();
    }
    if (!capabilities.supportsVision && _attachments.isNotEmpty) {
      return _invalid(PlanInvalidReason.imagesWithoutVision);
    }
    _tuneSoftTarget();
    try {
      _pack();
      return _finalize();
    } on _PlanAbort catch (abort) {
      return _invalid(
        abort.reason,
        neededTokens: abort.neededTokens,
        availableTokens: abort.availableTokens,
      );
    }
  }

  // -- Подготовка -----------------------------------------------------------

  void _prepareBudget() {
    _outputCap = budgetOutputCapTokens(capabilities, budgetConfig);
    _cardsByOutputCap = budgetCardsPerRequestCap(capabilities, budgetConfig);
    final int requested = requestedCards ?? _cardsByOutputCap;
    _limitTarget = math.max(1, math.min(requested, _cardsByOutputCap));
    // Лимиты запроса нужны и для невалидного плана (диагностика допущений),
    // поэтому резолвятся до проверки бюджета.
    _limits = resolveGenerationRequestLimits(
      capabilities,
      assumedMaxImagesPerRequest: config.assumedMaxImagesPerChunk,
      assumedMaxImageBytesPerImage: config.assumedMaxImageBytesPerImage,
      assumedMaxImageBytesPerChunk: config.assumedMaxImageBytesPerChunk,
      assumedMaxRequestBytes: config.assumedMaxRequestBytes,
    );
    _maxImagesPerChunk = _limits.maxImagesPerRequest;
    _maxImageBytesPerImage = _limits.maxImageBytesPerImage;
    _maxImageBytesPerRequest = _limits.maxImageBytesPerRequest;
    _payloadLimit = _limits.maxRequestBytes;

    final GenerationBudget base = GenerationBudget.compute(
      capabilities: capabilities,
      limit: _limitTarget,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      catalogTokens: 0,
      imageTokens: 0,
      config: budgetConfig,
    );
    _contentAllowance = base.inputBudget;
    if (!base.isWorkable) {
      throw _PlanAbort(
        PlanInvalidReason.contextWindowTooSmall,
        neededTokens: budgetConfig.minWorkableInputTokens,
        availableTokens: _contentAllowance,
      );
    }
    final int soft = math.max(
      1,
      _limitTarget * config.softTargetMaterialTokensPerCard,
    );
    _softTarget = math.min(_contentAllowance, soft);
  }

  /// Уточняет мягкую цель заполнения по заказу карточек (TASK 03, D20).
  ///
  /// `_limitTarget × softTargetMaterialTokensPerCard` — цель «не платить за
  /// 1M контекста ради нескольких карточек». Но при большом заказе и малом
  /// `outputCap` она упаковывает материал в слишком мало фрагментов: план
  /// выдаёт `cap × N` карточек, хотя материала хватает на весь заказ, и
  /// пользователь видит «достижимо меньше запрошенного» без реальной причины.
  ///
  /// Нужное число фрагментов: `ceil(requested / cap)` (если заказ ≤ cap —
  /// одного фрагмента достаточно, D.5 сам укрупнит лишние). Ограничиваем
  /// мягкую цель сверху текущей (не раздуваем запросы без нужды) и снизу —
  /// одним токеном, чтобы прогресс упаковки был гарантирован.
  void _tuneSoftTarget() {
    final int? requested = requestedCards;
    if (requested == null || requested <= 0) return;
    final int cap = math.max(1, _cardsByOutputCap);
    final int targetChunks = requested <= cap
        ? 1
        : ((requested - 1) ~/ cap) + 1;
    var totalTextTokens = 0;
    for (final _DocumentPlanData data in _documents) {
      for (final SectionUnit section in data.document.sections) {
        totalTextTokens += section.tokens;
      }
    }
    if (totalTextTokens <= 0 || targetChunks <= 1) return;
    // Берём 80 % среднего: упаковка идёт по границам разделов и может
    // перешагнуть мягкую цель на один раздел. Без запаса план иногда получает
    // на один фрагмент меньше и занижает achievableCards.
    final int average = (totalTextTokens / targetChunks).ceil();
    final int perChunk = math.max(
      config.minSoftTargetMaterialTokens,
      (average * 4) ~/ 5,
    );
    if (perChunk < _softTarget) {
      _softTarget = perChunk;
    }
  }

  void _collectInventory(ContentInventory inventory) {
    final Set<String> sectionImageIds = <String>{};
    for (final DocumentUnit document in inventory.documents) {
      final List<_ImageEntry> catalog = <_ImageEntry>[];
      for (var index = 0; index < document.images.length; index++) {
        final _ImageEntry entry = _entryFor(document.images[index], index);
        catalog.add(entry);
        _allImageEntries[entry.id] = entry;
      }
      final _DocumentPlanData data = _DocumentPlanData(
        document: document,
        catalog: catalog,
      );
      for (final SectionUnit section in document.sections) {
        final List<_ImageEntry> entries = <_ImageEntry>[];
        for (final ImageRef image in section.images) {
          sectionImageIds.add(image.id);
          final _ImageEntry? existing = data.byId[image.id];
          final _ImageEntry entry =
              existing ?? _entryFor(image, catalog.length + entries.length);
          data.byId[image.id] = entry;
          _allImageEntries[entry.id] = entry;
          entries.add(entry);
        }
        data.bySection[section.id] = entries;
      }
      _documents.add(data);
      _documentById[document.id] = data;
    }
    for (final AttachmentUnit attachment in inventory.attachments) {
      for (final PageUnit page in attachment.pages) {
        _inventoryPages.add(page);
        final ImageTokenEstimate estimate = estimator.estimateImage(
          bytes: page.bytes.length,
          model: capabilities.imageTokens,
        );
        _trackImageEstimate(estimate);
        _attachments.add(
          _PlannedAttachment(
            unit: attachment,
            page: page,
            tokens: estimate.tokens,
            bytes: page.bytes.length,
          ),
        );
      }
    }
    for (final OrphanImageUnit orphan in inventory.orphanImages) {
      if (sectionImageIds.contains(orphan.id)) continue;
      final _ImageEntry? existing = _allImageEntries[orphan.id];
      final _ImageEntry entry =
          existing ?? _entryFor(orphan.image, _allImageEntries.length);
      _allImageEntries[entry.id] = entry;
      _orphanImages.add(entry);
    }
    for (final _DocumentPlanData data in _documents) {
      for (final ImageRef image in data.document.images) {
        if (sectionImageIds.contains(image.id)) continue;
        if (_orphanImages.any((_ImageEntry entry) => entry.id == image.id)) {
          continue;
        }
        final _ImageEntry? entry = data.byId[image.id];
        if (entry == null) continue;
        _orphanImages.add(entry);
      }
    }
  }

  _ImageEntry _entryFor(ImageRef image, int index) {
    final String line = (catalogLineBuilder ?? _approximateCatalogLine)(
      image,
      index,
    );
    final ImageTokenEstimate estimate = estimator.estimateImage(
      width: image.image.width,
      height: image.image.height,
      bytes: image.image.bytes.length,
      model: capabilities.imageTokens,
    );
    _trackImageEstimate(estimate);
    return _ImageEntry(
      image: ImageRef(
        id: image.id,
        image: image.image,
        tokens: estimate.tokens,
        sectionId: image.sectionId,
      ),
      line: line,
      tokens: estimator.estimateText(line),
      bytes: utf8.encode(line).length,
    );
  }

  void _trackImageEstimate(ImageTokenEstimate estimate) {
    if (estimate.isAssumption) _imageEstimateAssumed = true;
  }

  String _approximateCatalogLine(ImageRef image, int index) {
    final String caption = image.caption ?? '';
    final String context = image.context ?? '';
    final String page = image.page == null ? '' : 'стр. ${image.page}';
    final String merged = page.isEmpty
        ? context
        : context.isEmpty
        ? page
        : '$page. $context';
    return 'img${index + 1} | ${image.image.fileName} | $caption | $merged';
  }

  // -- Упаковка -------------------------------------------------------------

  void _pack() {
    for (final _DocumentPlanData data in _documents) {
      for (final SectionUnit section in data.document.sections) {
        _placeSection(data, section);
      }
    }
    for (final _PlannedAttachment attachment in _attachments) {
      _placeAttachment(attachment);
    }
    if (_orphanImages.isNotEmpty) {
      final List<String> documentIds = <String>[
        for (final _ImageEntry entry in _orphanImages)
          if (_documentById.containsKey(
            contentDocumentId(entry.image.image.fileName),
          ))
            contentDocumentId(entry.image.image.fileName),
      ];
      _placeImageBlock(
        _orphanImages,
        documentIds: documentIds.toSet().toList(growable: false),
      );
    }
    _close();
  }

  void _placeSection(_DocumentPlanData data, SectionUnit section) {
    final List<_ImageEntry> sectionImages =
        data.bySection[section.id] ?? const <_ImageEntry>[];
    if (section.pieces.isEmpty) {
      if (sectionImages.isNotEmpty) {
        _placeImageBlock(
          sectionImages,
          documentIds: <String>[data.document.id],
        );
      }
      return;
    }
    bool imagesAttempted = false;
    for (var pieceIndex = 0; pieceIndex < section.pieces.length; pieceIndex++) {
      List<_TextFragment> fragments = <_TextFragment>[
        _fragmentOf(section.pieces[pieceIndex]),
      ];
      while (fragments.isNotEmpty) {
        final _TextFragment fragment = fragments.first;
        final List<_ImageEntry> images = (pieceIndex == 0 && !imagesAttempted)
            ? sectionImages
            : const <_ImageEntry>[];
        final _PlaceResult result = _tryPlaceText(
          data,
          section.id,
          fragment,
          images,
        );
        switch (result) {
          case _PlaceResult.placed:
            fragments = fragments.sublist(1);
            if (pieceIndex == 0) imagesAttempted = true;
          case _PlaceResult.needsNewChunk:
            _close();
          case _PlaceResult.split:
            final List<_TextFragment> split = _splitFragment(fragment, data);
            if (split.length == 1 && split.first.text == fragment.text) {
              throw _PlanAbort(
                PlanInvalidReason.unitTooLarge,
                neededTokens: fragment.tokens,
                availableTokens: _contentAllowance,
              );
            }
            fragments = split;
        }
      }
    }
    final List<_ImageEntry> remaining = <_ImageEntry>[
      for (final _ImageEntry entry in sectionImages)
        if (!_placedPartIds.contains(entry.id)) entry,
    ];
    if (remaining.isNotEmpty) {
      _placeImageBlock(remaining, documentIds: <String>[data.document.id]);
    }
  }

  _TextFragment _fragmentOf(TextPiece piece) {
    return _TextFragment(
      unitId: piece.id,
      text: piece.text,
      kind: piece.kind,
      tokens: piece.tokens,
      splitDepth: 0,
    );
  }

  _PlaceResult _tryPlaceText(
    _DocumentPlanData data,
    String sectionId,
    _TextFragment fragment,
    List<_ImageEntry> images,
  ) {
    if (_current == null) _startChunk();
    final _ChunkDraft current = _current!;
    if (current.isNotEmpty && current.textTokens >= _softTarget) {
      return _PlaceResult.needsNewChunk;
    }
    final _Candidate base = _candidateForText(
      current,
      data,
      sectionId,
      fragment,
    );
    if (_evaluate(base) == null) {
      return current.isNotEmpty
          ? _PlaceResult.needsNewChunk
          : _PlaceResult.split;
    }
    final List<_ImageEntry> selected = _selectFittingImages(
      current,
      data,
      sectionId,
      fragment,
      images,
    );
    if (current.isNotEmpty && images.isNotEmpty && selected.isEmpty) {
      final List<_ImageEntry> inEmptyChunk = _selectFittingImages(
        _ChunkDraft(),
        data,
        sectionId,
        fragment,
        images,
      );
      if (inEmptyChunk.isNotEmpty) return _PlaceResult.needsNewChunk;
    }
    final _Candidate chosen = selected.isEmpty
        ? base
        : _candidateForText(
            current,
            data,
            sectionId,
            fragment,
            newParts: selected,
          );
    if (_evaluate(chosen) == null) {
      // Каталог/части не влезли при жадном подборе — размещаем текст отдельно.
      _commitText(current, data, sectionId, fragment, base);
      return _PlaceResult.placed;
    }
    _commitText(current, data, sectionId, fragment, chosen);
    return _PlaceResult.placed;
  }

  List<_ImageEntry> _selectFittingImages(
    _ChunkDraft current,
    _DocumentPlanData data,
    String sectionId,
    _TextFragment fragment,
    List<_ImageEntry> images,
  ) {
    if (!capabilities.supportsVision) return const <_ImageEntry>[];
    final List<_ImageEntry> selected = <_ImageEntry>[];
    final Set<String> selectedDigests = <String>{};
    for (final _ImageEntry image in images) {
      if (current.partIds.contains(image.id)) continue;
      if (current.parts.any((_ImageEntry part) => part.id == image.id)) {
        continue;
      }
      if (selected.any((_ImageEntry part) => part.id == image.id)) continue;
      if (image.image.image.bytes.length > _maxImageBytesPerImage) continue;
      final String digest = documentImageDigest(image.image.image.bytes);
      // Одинаковые байты не отправляем дважды: второе изображение остаётся в
      // каталоге и разрешается по image_id (TASK 03, D11/L126).
      if (_placedPartDigests.contains(digest) ||
          selectedDigests.contains(digest)) {
        continue;
      }
      final _Candidate attempt = _candidateForText(
        current,
        data,
        sectionId,
        fragment,
        newParts: <_ImageEntry>[...selected, image],
      );
      if (_evaluate(attempt) != null) {
        selected.add(image);
        selectedDigests.add(digest);
      }
    }
    return selected;
  }

  _Candidate _candidateForText(
    _ChunkDraft current,
    _DocumentPlanData data,
    String sectionId,
    _TextFragment fragment, {
    List<_ImageEntry> newParts = const <_ImageEntry>[],
  }) {
    final bool newDocument = current.lastDocumentId != data.document.id;
    final bool newSection = !newDocument && current.lastSectionId != sectionId;
    final String header = '$_fileHeaderPrefix${data.document.fileName}\n';
    final int separatorTokens = newDocument
        ? (current.text.isEmpty ? 0 : estimator.estimateText('\n\n'))
        : newSection
        ? estimator.estimateText('\n\n')
        : 0;
    final int extraTokens = newDocument
        ? estimator.estimateText(header) + separatorTokens
        : separatorTokens;
    final int extraBytes = newDocument
        ? utf8.encode(header).length + (current.text.isEmpty ? 0 : 2)
        : newSection
        ? 2
        : 0;
    final List<_ImageEntry> parts = <_ImageEntry>[...current.parts];
    final Set<String> partIds = <String>{...current.partIds};
    for (final _ImageEntry image in newParts) {
      if (!partIds.add(image.id)) continue;
      parts.add(image);
    }
    final List<String> documentIds = newDocument
        ? <String>[...current.documentIds, data.document.id]
        : current.documentIds;
    return _Candidate(
      textTokens: current.textTokens + fragment.tokens + extraTokens,
      textBytes:
          current.textBytes + extraBytes + utf8.encode(fragment.text).length,
      labelTokens: current.labelTokens,
      labelBytes: current.labelBytes,
      parts: parts,
      partIds: partIds,
      extraCatalog: current.extraCatalog,
      attachments: current.attachments,
      documentIds: documentIds,
    );
  }

  _Candidate _candidateForAttachment(
    _ChunkDraft current,
    _PlannedAttachment attachment,
  ) {
    return _Candidate(
      textTokens: current.textTokens,
      textBytes: current.textBytes,
      labelTokens: current.labelTokens + attachment.labelTokens,
      labelBytes: current.labelBytes + attachment.labelBytes,
      parts: current.parts,
      partIds: current.partIds,
      extraCatalog: current.extraCatalog,
      attachments: <_PlannedAttachment>[...current.attachments, attachment],
      documentIds: current.documentIds,
    );
  }

  _Candidate _candidateForBlock(
    _ChunkDraft current,
    _ImageEntry entry, {
    required bool asPart,
    required List<String> documentIds,
  }) {
    final List<_ImageEntry> parts = <_ImageEntry>[...current.parts];
    final Set<String> partIds = <String>{...current.partIds};
    if (asPart && partIds.add(entry.id)) parts.add(entry);
    final List<String> mergedDocuments = <String>[...current.documentIds];
    for (final String id in documentIds) {
      if (!mergedDocuments.contains(id)) mergedDocuments.add(id);
    }
    final List<_ImageEntry> extraCatalog = <_ImageEntry>[
      ...current.extraCatalog,
    ];
    if (!extraCatalog.any((_ImageEntry item) => item.id == entry.id)) {
      extraCatalog.add(entry);
    }
    return _Candidate(
      textTokens: current.textTokens,
      textBytes: current.textBytes,
      labelTokens: current.labelTokens,
      labelBytes: current.labelBytes,
      parts: parts,
      partIds: partIds,
      extraCatalog: extraCatalog,
      attachments: current.attachments,
      documentIds: mergedDocuments,
    );
  }

  _Fit? _evaluate(_Candidate candidate) {
    if (candidate.imagePartCount > _maxImagesPerChunk) return null;
    for (final _ImageEntry part in candidate.parts) {
      if (part.image.image.bytes.length > _maxImageBytesPerImage) return null;
    }
    for (final _PlannedAttachment attachment in candidate.attachments) {
      if (attachment.bytes > _maxImageBytesPerImage) return null;
    }
    final int totalImageBytes =
        candidate.imageBytes + candidate.attachmentBytes;
    if (totalImageBytes > _maxImageBytesPerRequest) return null;
    final int required =
        candidate.textTokens +
        candidate.labelTokens +
        candidate.imageTokens +
        candidate.attachmentTokens;
    if (required > _contentAllowance) return null;
    final int allowance = _contentAllowance - required;
    final Set<String> requiredIds = <String>{
      ...candidate.partIds,
      for (final _ImageEntry entry in candidate.extraCatalog) entry.id,
    };
    final _CatalogSelection? selection = _selectCatalog(
      entries: _catalogEntriesForCandidate(candidate),
      requiredIds: requiredIds,
      allowance: allowance,
    );
    if (selection == null) return null;
    final GenerationBudget budget = GenerationBudget.compute(
      capabilities: capabilities,
      limit: _limitTarget,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      catalogTokens: selection.tokens,
      imageTokens: candidate.imageTokens + candidate.attachmentTokens,
      imagePartBytes: totalImageBytes,
      config: budgetConfig,
    );
    if (budget.inputBudget < candidate.textTokens) return null;
    final int bodyBytes =
        candidate.textBytes +
        selection.bytes +
        base64EncodedByteLength(totalImageBytes) +
        candidate.labelBytes +
        config.jsonBodyOverheadBytes;
    if (bodyBytes > _payloadLimit) return null;
    return _Fit(
      catalog: selection.entries,
      catalogTokens: selection.tokens,
      catalogBytes: selection.bytes,
      bodyBytes: bodyBytes,
    );
  }

  List<_ImageEntry> _catalogEntriesForCandidate(_Candidate candidate) {
    final List<_ImageEntry> entries = <_ImageEntry>[
      ..._catalogEntriesFor(candidate.documentIds),
      ...candidate.extraCatalog,
    ];
    final Map<String, _ImageEntry> unique = <String, _ImageEntry>{};
    for (final _ImageEntry entry in entries) {
      unique.putIfAbsent(entry.id, () => entry);
    }
    return unique.values.toList(growable: false);
  }

  List<_ImageEntry> _catalogEntriesFor(List<String> documentIds) {
    final Set<String> ids = documentIds.toSet();
    final List<_ImageEntry> entries = <_ImageEntry>[];
    for (final _DocumentPlanData data in _documents) {
      if (!ids.contains(data.document.id)) continue;
      entries.addAll(data.catalog);
    }
    return entries;
  }

  _CatalogSelection? _selectCatalog({
    required List<_ImageEntry> entries,
    required Set<String> requiredIds,
    required int allowance,
  }) {
    if (allowance < 0) return null;
    final Set<String> selectedIds = <String>{};
    var used = 0;
    for (final _ImageEntry entry in entries) {
      if (!requiredIds.contains(entry.id)) continue;
      if (selectedIds.add(entry.id)) used += entry.tokens;
    }
    if (selectedIds.length < requiredIds.length) return null;
    if (used > allowance) return null;
    for (final _ImageEntry entry in entries) {
      if (selectedIds.contains(entry.id)) continue;
      if (used + entry.tokens > allowance) continue;
      selectedIds.add(entry.id);
      used += entry.tokens;
    }
    final List<_ImageEntry> selected = <_ImageEntry>[
      for (final _ImageEntry entry in entries)
        if (selectedIds.contains(entry.id)) entry,
    ];
    final int bytes = selected.fold<int>(
      0,
      (int total, _ImageEntry entry) => total + entry.bytes,
    );
    return _CatalogSelection(entries: selected, tokens: used, bytes: bytes);
  }

  void _commitText(
    _ChunkDraft draft,
    _DocumentPlanData data,
    String sectionId,
    _TextFragment fragment,
    _Candidate candidate,
  ) {
    final bool newDocument = draft.lastDocumentId != data.document.id;
    final bool newSection = !newDocument && draft.lastSectionId != sectionId;
    if (newDocument) {
      if (draft.text.isNotEmpty) draft.text.write('\n\n');
      draft.text
        ..write(_fileHeaderPrefix)
        ..write(data.document.fileName)
        ..write('\n');
    } else if (newSection) {
      draft.text.write('\n\n');
    }
    final int start = draft.text.length;
    draft.text.write(fragment.text);
    final int end = draft.text.length;
    draft.fragments.add(
      _FragmentRecord(
        unitId: fragment.unitId,
        tokens: fragment.tokens,
        start: start,
        end: end,
      ),
    );
    draft
      ..textTokens = candidate.textTokens
      ..textBytes = candidate.textBytes
      ..labelTokens = candidate.labelTokens
      ..labelBytes = candidate.labelBytes;
    if (newDocument && !draft.documentIds.contains(data.document.id)) {
      draft.documentIds.add(data.document.id);
    }
    if (newSection && !draft.sectionIds.contains(sectionId)) {
      draft.sectionIds.add(sectionId);
    }
    draft.lastDocumentId = data.document.id;
    draft.lastSectionId = sectionId;
    draft.splitDepth = math.max(draft.splitDepth, fragment.splitDepth);
    _applyParts(draft, candidate);
  }

  void _applyParts(_ChunkDraft draft, _Candidate candidate) {
    for (final _ImageEntry part in candidate.parts) {
      if (!draft.partIds.add(part.id)) continue;
      final String digest = documentImageDigest(part.image.image.bytes);
      if (!_placedPartDigests.add(digest)) {
        // Байты уже отправлены другой единицей: оставляем это изображение
        // каталогу, а не дублируем image-часть.
        draft.partIds.remove(part.id);
        continue;
      }
      draft.parts.add(part);
      _placedPartIds.add(part.id);
    }
  }

  void _placeAttachment(_PlannedAttachment attachment) {
    while (true) {
      if (_current == null) _startChunk();
      final _ChunkDraft current = _current!;
      if (current.isNotEmpty && current.textTokens >= _softTarget) {
        _close();
        continue;
      }
      final _Candidate candidate = _candidateForAttachment(current, attachment);
      if (_evaluate(candidate) != null) {
        current.attachments.add(attachment);
        current
          ..labelTokens = candidate.labelTokens
          ..labelBytes = candidate.labelBytes;
        return;
      }
      if (current.isNotEmpty) {
        _close();
        continue;
      }
      final bool payloadTooLarge =
          attachment.bytes > _maxImageBytesPerImage ||
          attachment.bytes > _payloadLimit;
      throw _PlanAbort(
        payloadTooLarge
            ? PlanInvalidReason.payloadTooLarge
            : PlanInvalidReason.unitTooLarge,
        neededTokens: payloadTooLarge ? attachment.bytes : attachment.tokens,
        availableTokens: payloadTooLarge
            ? math.min(_maxImageBytesPerImage, _payloadLimit)
            : math.max(0, _contentAllowance),
      );
    }
  }

  void _placeImageBlock(
    List<_ImageEntry> entries, {
    List<String> documentIds = const <String>[],
  }) {
    if (entries.isEmpty) return;
    _close();
    for (final _ImageEntry entry in entries) {
      while (true) {
        if (_current == null) _startChunk();
        final _ChunkDraft current = _current!;
        final bool canBePart =
            capabilities.supportsVision &&
            !_placedPartDigests.contains(
              documentImageDigest(entry.image.image.bytes),
            ) &&
            entry.image.image.bytes.length <= _maxImageBytesPerImage &&
            entry.image.image.bytes.length <= _maxImageBytesPerRequest;
        if (canBePart) {
          final bool capsExceeded =
              current.imagePartCount >= _maxImagesPerChunk ||
              current.totalImageBytes + entry.image.image.bytes.length >
                  _maxImageBytesPerRequest;
          if (!capsExceeded) {
            final _Candidate part = _candidateForBlock(
              current,
              entry,
              asPart: true,
              documentIds: documentIds,
            );
            if (_evaluate(part) != null) {
              _commitBlock(
                current,
                entry,
                asPart: true,
                documentIds: documentIds,
              );
              break;
            }
          }
          // Другая подгруппа: изображение ещё может уйти image-частью.
          if (current.isNotEmpty) {
            _close();
            continue;
          }
        }
        final _Candidate catalog = _candidateForBlock(
          current,
          entry,
          asPart: false,
          documentIds: documentIds,
        );
        if (_evaluate(catalog) != null) {
          _commitBlock(current, entry, asPart: false, documentIds: documentIds);
          break;
        }
        if (current.isNotEmpty) {
          _close();
          continue;
        }
        _omit(
          OmittedUnit(
            unitId: entry.id,
            reason: entry.image.image.bytes.length > _payloadLimit
                ? OmittedReason.payload
                : OmittedReason.budget,
            tokens: entry.image.tokens,
            documentId: entry.image.image.fileName,
          ),
        );
        break;
      }
    }
    _close();
  }

  void _commitBlock(
    _ChunkDraft draft,
    _ImageEntry entry, {
    required bool asPart,
    required List<String> documentIds,
  }) {
    for (final String id in documentIds) {
      if (!draft.documentIds.contains(id)) draft.documentIds.add(id);
    }
    if (!draft.extraCatalog.any((_ImageEntry item) => item.id == entry.id)) {
      draft.extraCatalog.add(entry);
    }
    if (asPart && draft.partIds.add(entry.id)) {
      final String digest = documentImageDigest(entry.image.image.bytes);
      if (_placedPartDigests.add(digest)) {
        draft.parts.add(entry);
        _placedPartIds.add(entry.id);
      } else {
        draft.partIds.remove(entry.id);
      }
    }
  }

  void _omit(OmittedUnit unit) {
    if (!_omittedIds.add(unit.unitId)) return;
    _omitted.add(unit);
  }

  // -- Дробление ------------------------------------------------------------

  List<_TextFragment> _splitFragment(
    _TextFragment fragment,
    _DocumentPlanData data,
  ) {
    // В пустом фрагменте текст начинается строкой «Файл: <имя>» — её токены
    // тоже занимают бюджет, иначе деление зациклится на фрагменте, который
    // чуть больше бюджета.
    final int headerTokens = estimator.estimateText(
      '$_fileHeaderPrefix${data.document.fileName}\n',
    );
    final int budget = math.max(1, _contentAllowance - headerTokens);
    return _splitToBudget(
      text: fragment.text,
      kind: fragment.kind,
      rootId: fragment.unitId,
      budget: budget,
      depth: fragment.splitDepth + 1,
    );
  }

  List<_TextFragment> _splitToBudget({
    required String text,
    required TextPieceKind kind,
    required String rootId,
    required int budget,
    required int depth,
  }) {
    final int tokens = estimator.estimateText(text);
    if (tokens <= budget) {
      return <_TextFragment>[
        _derivedFragment(text, kind, rootId, tokens, depth),
      ];
    }
    if (depth >= config.maxSplitDepth) {
      return _hardSplit(text, kind, rootId, budget);
    }
    final List<String> sentences = _splitAfter(text, _sentenceBoundary);
    if (sentences.length > 1) {
      return _packParts(
        sentences,
        TextPieceKind.sentence,
        rootId,
        budget,
        depth,
      );
    }
    final List<String> lines = _splitAfter(text, _lineBoundary);
    if (lines.length > 1) {
      return _packParts(lines, TextPieceKind.line, rootId, budget, depth);
    }
    return _hardSplit(text, kind, rootId, budget);
  }

  List<_TextFragment> _packParts(
    List<String> parts,
    TextPieceKind kind,
    String rootId,
    int budget,
    int depth,
  ) {
    final List<_TextFragment> result = <_TextFragment>[];
    final List<String> buffer = <String>[];
    var bufferRunes = 0;
    void flush() {
      if (buffer.isEmpty) return;
      final String text = buffer.join();
      buffer.clear();
      bufferRunes = 0;
      result.add(
        _derivedFragment(
          text,
          kind,
          rootId,
          estimator.estimateText(text),
          depth,
        ),
      );
    }

    for (final String part in parts) {
      final int partRunes = part.runes.length;
      if (_tokensForRunes(partRunes) > budget) {
        flush();
        result.addAll(
          _splitToBudget(
            text: part,
            kind: kind,
            rootId: rootId,
            budget: budget,
            depth: depth + 1,
          ),
        );
        continue;
      }
      if (buffer.isNotEmpty &&
          _tokensForRunes(bufferRunes + partRunes) > budget) {
        flush();
      }
      buffer.add(part);
      bufferRunes += partRunes;
    }
    flush();
    if (result.isEmpty) {
      final String joined = parts.join();
      result.add(
        _derivedFragment(
          joined,
          kind,
          rootId,
          estimator.estimateText(joined),
          depth,
        ),
      );
    }
    return result;
  }

  /// Оценка токенов по числу рун (консервативная линейная аппроксимация для
  /// упаковки; финальные токены фрагмента считает [ContentTokenEstimator]).
  int _tokensForRunes(int runes) {
    if (runes <= 0) return 0;
    return (runes / estimator.charsPerToken).ceil();
  }

  List<_TextFragment> _hardSplit(
    String text,
    TextPieceKind kind,
    String rootId,
    int budget,
  ) {
    final int targetChars = math.max(
      1,
      (budget * estimator.charsPerToken * 0.8).floor(),
    );
    final List<_TextFragment> result = <_TextFragment>[];
    var start = 0;
    while (start < text.length) {
      int end = math.min(start + targetChars, text.length);
      if (end < text.length &&
          _isHighSurrogate(text.codeUnitAt(end - 1)) &&
          _isLowSurrogate(text.codeUnitAt(end))) {
        end = math.min(end + 1, text.length);
      }
      final String part = text.substring(start, end);
      result.add(
        _derivedFragment(
          part,
          kind,
          rootId,
          estimator.estimateText(part),
          config.maxSplitDepth,
        ),
      );
      start = end;
    }
    return result;
  }

  _TextFragment _derivedFragment(
    String text,
    TextPieceKind kind,
    String rootId,
    int tokens,
    int depth,
  ) {
    final int counter = (_splitCounters[rootId] ?? 0) + 1;
    _splitCounters[rootId] = counter;
    return _TextFragment(
      unitId: '$rootId~$counter',
      text: text,
      kind: kind,
      tokens: tokens,
      splitDepth: depth,
    );
  }

  // -- Завершение -----------------------------------------------------------

  void _startChunk() {
    if (_startedChunks >= config.maxChunks) {
      throw _PlanAbort(
        PlanInvalidReason.tooManyChunks,
        neededTokens: _startedChunks + 1,
        availableTokens: config.maxChunks,
      );
    }
    _startedChunks++;
    _current = _ChunkDraft();
  }

  void _close() {
    final _ChunkDraft? current = _current;
    if (current == null) return;
    _current = null;
    if (current.isEmpty) return;
    _drafts.add(current);
  }

  GenerationPlan _finalize() {
    final List<_PlannedChunkData> packed = <_PlannedChunkData>[
      for (var index = 0; index < _drafts.length; index++)
        _finalizeDraft(_drafts[index], index + 1),
    ];
    // D.5: второй проход — если фрагментов больше, чем запрошено карточек,
    // совместимые соседние фрагменты укрупняются в пределах бюджета.
    final List<_PlannedChunkData> planned = _mergeToRequested(packed);
    final List<int> limits = _distributeLimits(planned);
    final List<PlannedChunk> chunks = <PlannedChunk>[
      for (var index = 0; index < planned.length; index++)
        planned[index].toChunk(limit: limits[index], index: index + 1),
    ];
    _ensureCoverage(chunks);
    final List<String> unknown = _unknownFields();
    final bool hasInventoryImages =
        _allImageEntries.isNotEmpty || _attachments.isNotEmpty;
    final List<PlanWarningCode> warnings = <PlanWarningCode>[
      if (unknown.isNotEmpty) PlanWarningCode.unknownCapabilities,
      if (chunks.any((PlannedChunk chunk) => chunk.catalogOnly.isNotEmpty))
        PlanWarningCode.catalogOnlyImages,
      if (hasInventoryImages && !capabilities.supportsVision)
        PlanWarningCode.imagesWithoutVision,
      if (hasInventoryImages && _limits.hasAssumption)
        PlanWarningCode.assumedImageLimits,
      if (requestedCards != null &&
          chunks.isNotEmpty &&
          _plannedCards(limits) > requestedCards!)
        PlanWarningCode.cardsAboveRequested,
      if (requestedCards != null &&
          chunks.isNotEmpty &&
          _plannedCards(limits) < requestedCards!)
        PlanWarningCode.requestedAbovePlan,
      if (_omitted.isNotEmpty) PlanWarningCode.omittedUnits,
    ];
    final PlanValidity validity = warnings.isEmpty
        ? const PlanValidity.valid()
        : PlanValidity.warnings(List<PlanWarningCode>.unmodifiable(warnings));
    return _buildPlan(
      validity: validity,
      chunks: chunks,
      planned: planned,
      limits: limits,
      unknownFields: unknown,
    );
  }

  _PlannedChunkData _finalizeDraft(_ChunkDraft draft, int index) {
    final List<_ImageEntry> entries = _catalogEntriesForDraft(draft);
    final int allowance =
        _contentAllowance -
        draft.textTokens -
        draft.labelTokens -
        draft.imageTokens -
        draft.attachmentTokens;
    final _CatalogSelection? selection = _selectCatalog(
      entries: entries,
      requiredIds: <String>{
        ...draft.partIds,
        for (final _ImageEntry entry in draft.extraCatalog) entry.id,
      },
      allowance: allowance,
    );
    if (selection == null) {
      throw const _PlanAbort(
        PlanInvalidReason.unitTooLarge,
        neededTokens: 0,
        availableTokens: 0,
      );
    }
    final List<DocumentImage> catalogOnly = <DocumentImage>[
      for (final _ImageEntry entry in selection.entries)
        if (!draft.partIds.contains(entry.id)) entry.image.image,
    ];
    final List<String> catalogOnlyIds = <String>[
      for (final _ImageEntry entry in selection.entries)
        if (!draft.partIds.contains(entry.id)) entry.id,
    ];
    final bool hasText = draft.text.toString().trim().isNotEmpty;
    final bool hasParts =
        draft.parts.isNotEmpty || draft.attachments.isNotEmpty;
    final ChunkKind kind = hasText && hasParts
        ? ChunkKind.mixed
        : hasText
        ? ChunkKind.text
        : hasParts
        ? ChunkKind.images
        : ChunkKind.catalog;
    return _PlannedChunkData(
      index: index,
      kind: kind,
      materialsText: draft.text.toString(),
      units: <UnitSpan>[
        for (final _FragmentRecord fragment in draft.fragments)
          UnitSpan(
            unitId: fragment.unitId,
            start: fragment.start,
            end: fragment.end,
            tokens: fragment.tokens,
          ),
      ],
      imageParts: <DocumentImage>[
        for (final _ImageEntry entry in draft.parts) entry.image.image,
      ],
      imagePartIds: <String>[
        for (final _ImageEntry entry in draft.parts) entry.id,
      ],
      catalogOnly: catalogOnly,
      catalogOnlyIds: catalogOnlyIds,
      attachments: <GenerationAttachment>[
        for (final _PlannedAttachment attachment in draft.attachments)
          GenerationAttachment(
            fileName: attachment.unit.fileName,
            mediaType: attachment.unit.mediaType,
            bytes: attachment.page.bytes,
            pageNumber: attachment.page.pageNumber,
            groupKey: attachment.unit.groupKey,
          ),
      ],
      pureTextTokens: draft.textTokens,
      catalogTokens: selection.tokens,
      labelTokens: draft.labelTokens,
      imagePartTokens: draft.imageTokens,
      attachmentTokens: draft.attachmentTokens,
      bodyBytes:
          draft.textBytes +
          selection.bytes +
          base64EncodedByteLength(draft.totalImageBytes) +
          draft.labelBytes +
          config.jsonBodyOverheadBytes,
      splitDepth: draft.splitDepth,
    );
  }

  List<_ImageEntry> _catalogEntriesForDraft(_ChunkDraft draft) {
    final List<_ImageEntry> entries = <_ImageEntry>[
      ..._catalogEntriesFor(draft.documentIds),
      ...draft.extraCatalog,
    ];
    final Map<String, _ImageEntry> unique = <String, _ImageEntry>{};
    for (final _ImageEntry entry in entries) {
      unique.putIfAbsent(entry.id, () => entry);
    }
    return unique.values.toList(growable: false);
  }

  int _plannedCards(List<int> limits) =>
      limits.fold<int>(0, (int total, int limit) => total + limit);

  // -- D.5: второй проход (укрупнение фрагментов) ---------------------------

  /// Укрупняет фрагменты до [requestedCards], пока это позволяет бюджет.
  ///
  /// Целевое число фрагментов — желаемое, а не абсолютное: если безопасно
  /// объединить нельзя, возвращается меньшее (безопасное) укрупнение, и план
  /// получает предупреждение `cardsAboveRequested`. Порядок фрагментов и
  /// единиц сохраняется; единицы/изображения не дублируются и не теряются.
  List<_PlannedChunkData> _mergeToRequested(List<_PlannedChunkData> packed) {
    final int? target = requestedCards;
    if (target == null || packed.length <= target) return packed;
    final List<_PlannedChunkData> result = List<_PlannedChunkData>.of(packed);
    // Сначала предпочитаем соседние фрагменты одного документа, затем любые
    // соседние: «преимущественно одного документа или совместимых».
    while (result.length > target) {
      final bool shared = _mergePass(
        result,
        target: target,
        sharedDocumentOnly: true,
      );
      if (result.length <= target) break;
      final bool any = _mergePass(
        result,
        target: target,
        sharedDocumentOnly: false,
      );
      if (!shared && !any) break;
    }
    return result;
  }

  /// Один проход слева направо; возвращает true, если что-то объединено.
  bool _mergePass(
    List<_PlannedChunkData> planned, {
    required int target,
    required bool sharedDocumentOnly,
  }) {
    var mergedAny = false;
    var index = 0;
    while (index + 1 < planned.length && planned.length > target) {
      final _PlannedChunkData first = planned[index];
      final _PlannedChunkData second = planned[index + 1];
      if (sharedDocumentOnly && !_sharesDocument(first, second)) {
        index++;
        continue;
      }
      final _PlannedChunkData? merged = _mergePair(first, second);
      if (merged == null) {
        index++;
        continue;
      }
      planned.replaceRange(index, index + 2, <_PlannedChunkData>[merged]);
      mergedAny = true;
      // Не сливаем всё в первый фрагмент подряд: после объединения шагаем
      // дальше, чтобы укрупнение распределялось по документу.
      index++;
    }
    return mergedAny;
  }

  /// true, если у фрагментов есть общий документ/файл.
  bool _sharesDocument(_PlannedChunkData first, _PlannedChunkData second) {
    final Set<String> firstFiles = _fileNamesOf(first);
    if (firstFiles.isEmpty) return false;
    for (final String file in _fileNamesOf(second)) {
      if (firstFiles.contains(file)) return true;
    }
    return false;
  }

  /// Имена файлов/документов фрагмента (единицы, изображения, вложения).
  Set<String> _fileNamesOf(_PlannedChunkData chunk) {
    final Set<String> names = <String>{};
    for (final UnitSpan span in chunk.units) {
      final String id = span.unitId;
      if (!id.startsWith('doc:')) continue;
      final int hash = id.indexOf('#');
      if (hash > 4) names.add(id.substring(4, hash));
    }
    for (final DocumentImage image in chunk.imageParts) {
      names.add(image.fileName);
    }
    for (final DocumentImage image in chunk.catalogOnly) {
      names.add(image.fileName);
    }
    for (final GenerationAttachment attachment in chunk.attachments) {
      names.add(attachment.fileName);
    }
    return names;
  }

  /// Объединяет два соседних фрагмента или возвращает `null`, если нельзя.
  ///
  /// Повторно проверяются: бюджет входа/окно контекста (D.1), лимит image-частей
  /// и байт изображений, лимит тела запроса, выходной резерв (D.2). Объединение
  /// не создаёт дублей изображений/вложений и сохраняет `unitIds`/`UnitSpan`.
  _PlannedChunkData? _mergePair(
    _PlannedChunkData first,
    _PlannedChunkData second,
  ) {
    if (first.kind == ChunkKind.promptOnly ||
        second.kind == ChunkKind.promptOnly) {
      return null;
    }
    final String firstText = first.materialsText;
    final String secondText = second.materialsText;
    final bool firstHasText = firstText.trim().isNotEmpty;
    final bool secondHasText = secondText.trim().isNotEmpty;
    final String mergedText;
    final int shift;
    if (firstHasText && secondHasText) {
      mergedText = '$firstText\n\n$secondText';
      shift = firstText.length + 2;
    } else if (secondHasText) {
      mergedText = secondText;
      shift = 0;
    } else {
      mergedText = firstText;
      shift = 0;
    }
    final List<UnitSpan> units = <UnitSpan>[
      ...first.units,
      for (final UnitSpan span in second.units)
        UnitSpan(
          unitId: span.unitId,
          start: span.start + shift,
          end: span.end + shift,
          tokens: span.tokens,
        ),
    ];

    final Map<String, _ImageEntry> entries = <String, _ImageEntry>{};
    for (final String id in <String>[
      ...first.imagePartIds,
      ...first.catalogOnlyIds,
      ...second.imagePartIds,
      ...second.catalogOnlyIds,
    ]) {
      final _ImageEntry? entry = _allImageEntries[id];
      if (entry != null) entries[id] = entry;
    }
    final Set<String> partIds = <String>{
      ...first.imagePartIds,
      ...second.imagePartIds,
    };
    final Set<String> catalogIds = <String>{
      ...partIds,
      ...first.catalogOnlyIds,
      ...second.catalogOnlyIds,
    };
    final Set<String> catalogOnlyIds = <String>{
      for (final String id in catalogIds)
        if (!partIds.contains(id)) id,
    };
    final List<_ImageEntry> parts = <_ImageEntry>[
      for (final _ImageEntry entry in entries.values)
        if (partIds.contains(entry.id)) entry,
    ];
    final List<_ImageEntry> catalogOnly = <_ImageEntry>[
      for (final _ImageEntry entry in entries.values)
        if (catalogOnlyIds.contains(entry.id)) entry,
    ];
    if (parts.length > _maxImagesPerChunk) return null;

    final List<GenerationAttachment> attachments = _mergeAttachments(
      first.attachments,
      second.attachments,
    );
    if (parts.length + attachments.length > _maxImagesPerChunk) return null;

    var imagePartTokens = 0;
    var imageBytes = 0;
    for (final _ImageEntry entry in parts) {
      final int bytes = entry.image.image.bytes.length;
      if (bytes > _maxImageBytesPerImage) return null;
      imagePartTokens += entry.image.tokens;
      imageBytes += bytes;
    }
    var attachmentTokens = 0;
    for (final GenerationAttachment attachment in attachments) {
      if (attachment.bytes.length > _maxImageBytesPerImage) return null;
      attachmentTokens += estimator
          .estimateImage(
            bytes: attachment.bytes.length,
            model: capabilities.imageTokens,
          )
          .tokens;
      imageBytes += attachment.bytes.length;
    }
    if (imageBytes > _maxImageBytesPerRequest) return null;

    var catalogTokens = 0;
    var catalogBytes = 0;
    for (final String id in catalogIds) {
      final _ImageEntry? entry = entries[id];
      if (entry == null) continue;
      catalogTokens += entry.tokens;
      catalogBytes += entry.bytes;
    }
    final int pureTextTokens = estimator.estimateText(mergedText);
    final int labelTokens = first.labelTokens + second.labelTokens;
    final int textTokens = pureTextTokens + catalogTokens + labelTokens;
    final int imageTokens = imagePartTokens + attachmentTokens;
    if (textTokens + imageTokens > _contentAllowance) return null;

    final int bodyBytes =
        utf8.encode(mergedText).length +
        catalogBytes +
        base64EncodedByteLength(imageBytes) +
        config.jsonBodyOverheadBytes;
    if (bodyBytes > _payloadLimit) return null;

    // Повторная проверка бюджета с каталогом/изображениями и резервом вывода:
    // объединённый фрагмент должен помещаться в окно при самом большом
    // возможном для него лимите карточек.
    final GenerationBudget mergedBudget = GenerationBudget.compute(
      capabilities: capabilities,
      limit: _limitTarget,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      catalogTokens: catalogTokens,
      imageTokens: imageTokens,
      imagePartBytes: imageBytes,
      config: budgetConfig,
    );
    if (!mergedBudget.isWorkable) return null;
    if (mergedBudget.inputBudget < pureTextTokens + labelTokens) return null;

    final bool hasText = mergedText.trim().isNotEmpty;
    final bool hasParts = parts.isNotEmpty || attachments.isNotEmpty;
    final ChunkKind kind = hasText && hasParts
        ? ChunkKind.mixed
        : hasText
        ? ChunkKind.text
        : hasParts
        ? ChunkKind.images
        : ChunkKind.catalog;
    return _PlannedChunkData(
      index: first.index,
      kind: kind,
      materialsText: mergedText,
      units: units,
      imageParts: <DocumentImage>[
        for (final _ImageEntry entry in parts) entry.image.image,
      ],
      imagePartIds: <String>[for (final _ImageEntry entry in parts) entry.id],
      catalogOnly: <DocumentImage>[
        for (final _ImageEntry entry in catalogOnly) entry.image.image,
      ],
      catalogOnlyIds: <String>[
        for (final _ImageEntry entry in catalogOnly) entry.id,
      ],
      attachments: attachments,
      pureTextTokens: pureTextTokens,
      catalogTokens: catalogTokens,
      labelTokens: labelTokens,
      imagePartTokens: imagePartTokens,
      attachmentTokens: attachmentTokens,
      bodyBytes: bodyBytes,
      splitDepth: math.max(first.splitDepth, second.splitDepth),
    );
  }

  /// Уникальные вложения двух фрагментов (страница одного файла — один раз).
  List<GenerationAttachment> _mergeAttachments(
    List<GenerationAttachment> first,
    List<GenerationAttachment> second,
  ) {
    final List<GenerationAttachment> result = <GenerationAttachment>[];
    final Set<String> seen = <String>{};
    for (final GenerationAttachment attachment in <GenerationAttachment>[
      ...first,
      ...second,
    ]) {
      final String key =
          '${attachment.fileName}\u0000${attachment.pageNumber}\u0000'
          '${attachment.groupKey}';
      if (seen.add(key)) result.add(attachment);
    }
    return List<GenerationAttachment>.unmodifiable(result);
  }

  /// Распределяет потолок карточек по фрагментам (D.7) без молчаливого среза.
  List<int> _distributeLimits(List<_PlannedChunkData> planned) {
    if (planned.isEmpty) return <int>[];
    final int cap = _cardsByOutputCap;
    final int chunks = planned.length;
    final int? requested = requestedCards;
    if (requested == null) return List<int>.filled(chunks, cap);
    if (requested <= chunks) return List<int>.filled(chunks, 1);
    final int capacity = chunks * cap;
    if (requested >= capacity) return List<int>.filled(chunks, cap);
    final List<int> limits = List<int>.filled(chunks, 1);
    var remaining = requested - chunks;
    final List<int> volumes = <int>[
      for (final _PlannedChunkData chunk in planned) math.max(1, chunk.volume),
    ];
    final List<int> order = List<int>.generate(chunks, (int index) => index)
      ..sort((int a, int b) {
        final int byVolume = volumes[b].compareTo(volumes[a]);
        return byVolume != 0 ? byVolume : a.compareTo(b);
      });
    var cursor = 0;
    while (remaining > 0) {
      var progressed = false;
      for (var step = 0; step < chunks && remaining > 0; step++) {
        final int index = order[(cursor + step) % chunks];
        if (limits[index] < cap) {
          limits[index]++;
          remaining--;
          progressed = true;
        }
      }
      if (!progressed) break;
      cursor++;
    }
    return limits;
  }

  /// Состояние каждого изображения после упаковки (TASK 03, раздел 6).
  ///
  /// Различает «передано модели» и «только в каталоге»: пользователь и
  /// диагностика не должны считать изображение обработанным только потому, что
  /// оно осталось в каталоге. Для моделей без Vision части не отправляются —
  /// статус `unsupportedModel`.
  List<PlannedImage> _imageStatuses(List<PlannedChunk> chunks) {
    final Set<String> sentIds = <String>{
      for (final PlannedChunk chunk in chunks) ...chunk.imagePartIds,
    };
    final Set<String> catalogIds = <String>{
      for (final PlannedChunk chunk in chunks) ...chunk.catalogOnlyIds,
    };
    final Map<String, OmittedUnit> omitted = <String, OmittedUnit>{
      for (final OmittedUnit unit in _omitted) unit.unitId: unit,
    };
    final List<PlannedImage> statuses = <PlannedImage>[];
    for (final _ImageEntry entry in _allImageEntries.values) {
      final ImageParticipationStatus status;
      if (!capabilities.supportsVision && sentIds.contains(entry.id)) {
        // Части не отправлялись: планировщик не должен был их помечать, но
        // защищаемся от рассогласования.
        status = ImageParticipationStatus.unsupportedModel;
      } else if (sentIds.contains(entry.id)) {
        status = ImageParticipationStatus.sentToModel;
      } else if (!capabilities.supportsVision) {
        status = ImageParticipationStatus.unsupportedModel;
      } else if (catalogIds.contains(entry.id)) {
        status = ImageParticipationStatus.catalogOnly;
      } else if (omitted.containsKey(entry.id)) {
        status = omitted[entry.id]!.reason == OmittedReason.payload
            ? ImageParticipationStatus.omittedPayload
            : ImageParticipationStatus.omittedBudget;
      } else {
        status = ImageParticipationStatus.catalogOnly;
      }
      statuses.add(
        PlannedImage(
          id: entry.id,
          fileName: entry.image.image.fileName,
          status: status,
          page: entry.image.page,
          tokens: entry.image.tokens,
        ),
      );
    }
    for (final _PlannedAttachment attachment in _attachments) {
      statuses.add(
        PlannedImage(
          id: _attachmentPageId(
            GenerationAttachment(
              fileName: attachment.unit.fileName,
              mediaType: attachment.unit.mediaType,
              bytes: attachment.page.bytes,
              pageNumber: attachment.page.pageNumber,
              groupKey: attachment.unit.groupKey,
            ),
          ),
          fileName: attachment.unit.fileName,
          status: capabilities.supportsVision
              ? ImageParticipationStatus.sentToModel
              : ImageParticipationStatus.unsupportedModel,
          page: attachment.page.pageNumber,
          tokens: attachment.tokens,
        ),
      );
    }
    return statuses;
  }

  /// Страховочная проверка: ни одно изображение/страница не потеряны.
  void _ensureCoverage(List<PlannedChunk> chunks) {
    final Set<String> coveredImages = <String>{
      for (final PlannedChunk chunk in chunks) ...chunk.imagePartIds,
      for (final PlannedChunk chunk in chunks) ...chunk.catalogOnlyIds,
    };
    for (final _ImageEntry entry in _allImageEntries.values) {
      if (coveredImages.contains(entry.id)) continue;
      if (_omittedIds.contains(entry.id)) continue;
      _omit(
        OmittedUnit(
          unitId: entry.id,
          reason: entry.image.image.bytes.length > _payloadLimit
              ? OmittedReason.payload
              : OmittedReason.budget,
          tokens: entry.image.tokens,
          documentId: entry.image.image.fileName,
        ),
      );
    }
    final Set<String> coveredPages = <String>{
      for (final PlannedChunk chunk in chunks)
        for (final GenerationAttachment attachment in chunk.attachments)
          _attachmentPageId(attachment),
    };
    for (final PageUnit page in _inventoryPages) {
      if (coveredPages.contains(page.id)) continue;
      if (_omittedIds.contains(page.id)) continue;
      _omit(
        OmittedUnit(
          unitId: page.id,
          reason: OmittedReason.budget,
          tokens: page.tokens,
        ),
      );
    }
  }

  List<String> _unknownFields() {
    final List<String> fields = <String>[...capabilities.unknownFields];
    void add(String value) {
      if (!fields.contains(value)) fields.add(value);
    }

    // Единый источник лимитов запроса (TASK 03): те же допущения, что видит
    // исполнитель, попадают в план и диагностику.
    for (final String field in _limits.assumptionFields) {
      add(field);
    }
    if ((_allImageEntries.isNotEmpty || _attachments.isNotEmpty) &&
        _imageEstimateAssumed) {
      add('image_tokens');
    }
    return List<String>.unmodifiable(fields);
  }

  GenerationPlan _emptyPlan() {
    return GenerationPlan(
      validity: const PlanValidity.valid(),
      estimate: GenerationEstimate(
        inputTextTokens: 0,
        imageTokens: 0,
        fixedPromptTokens: overhead.systemPromptTokens,
        wrapperTokens: overhead.wrapperTokens,
        schemaTokens: overhead.schemaTokens,
        catalogTokens: 0,
        reservedOutputTokens: 0,
        expectedOutputTokens: 0,
        totalTokens: overhead.fixedTokens,
        plannedChunks: 0,
        plannedRequests: 0,
        retryAllowanceRequests: config.retryAllowanceRequests,
        pricingState: capabilities.pricingState,
        estimatorVersion: '${estimator.version}/planner-1',
      ),
      budget: _planBudget(const <_PlannedChunkData>[], const <int>[]),
      chunks: const <PlannedChunk>[],
      images: _imageStatuses(const <PlannedChunk>[]),
      capabilitySources: capabilities.sources,
      requestedCards: requestedCards ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
    );
  }

  GenerationPlan _invalid(
    PlanInvalidReason reason, {
    int? neededTokens,
    int? availableTokens,
  }) {
    final List<String> unknown = _unknownFields();
    return GenerationPlan(
      validity: PlanValidity.invalid(
        reason,
        neededTokens: neededTokens,
        availableTokens: availableTokens,
      ),
      estimate: GenerationEstimate(
        inputTextTokens: 0,
        imageTokens: 0,
        fixedPromptTokens: overhead.systemPromptTokens,
        wrapperTokens: overhead.wrapperTokens,
        schemaTokens: overhead.schemaTokens,
        catalogTokens: 0,
        reservedOutputTokens: 0,
        expectedOutputTokens: 0,
        totalTokens: overhead.fixedTokens,
        plannedChunks: 0,
        plannedRequests: 0,
        retryAllowanceRequests: config.retryAllowanceRequests,
        pricingState: capabilities.pricingState,
        estimatorVersion: '${estimator.version}/planner-1',
        unknownFields: unknown,
      ),
      budget: _planBudget(const <_PlannedChunkData>[], const <int>[]),
      chunks: const <PlannedChunk>[],
      omitted: _omitted,
      images: _imageStatuses(const <PlannedChunk>[]),
      capabilitySources: capabilities.sources,
      requestedCards: requestedCards ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
      unknownFields: unknown,
    );
  }

  GenerationPlan _buildPlan({
    required PlanValidity validity,
    required List<PlannedChunk> chunks,
    required List<_PlannedChunkData> planned,
    required List<int> limits,
    required List<String> unknownFields,
  }) {
    return GenerationPlan(
      validity: validity,
      estimate: _estimate(planned, chunks),
      budget: _planBudget(planned, limits),
      chunks: chunks,
      omitted: _omitted,
      images: _imageStatuses(chunks),
      capabilitySources: capabilities.sources,
      requestedCards: requestedCards ?? 0,
      retryAllowanceRequests: config.retryAllowanceRequests,
      unknownFields: unknownFields,
    );
  }

  GenerationEstimate _estimate(
    List<_PlannedChunkData> planned,
    List<PlannedChunk> chunks,
  ) {
    var inputTextTokens = 0;
    var imageTokens = 0;
    var catalogTokens = 0;
    for (final _PlannedChunkData chunk in planned) {
      inputTextTokens += chunk.pureTextTokens;
      imageTokens += chunk.imagePartTokens + chunk.attachmentTokens;
      catalogTokens += chunk.catalogTokens + chunk.labelTokens;
    }
    var reservedOutput = 0;
    for (final PlannedChunk chunk in chunks) {
      reservedOutput += math.min(
        _outputCap,
        chunk.limit * budgetConfig.perCardOutputTokens +
            budgetConfig.jsonEnvelopeTokens,
      );
    }
    final int requests = math.max(1, chunks.length);
    // Обвязка отправляется в каждом запросе — она умножается на число
    // запросов, иначе оценка входа занижает реальную стоимость (G.1/G.6).
    final int fixedPrompt = overhead.systemPromptTokens * requests;
    final int wrapper = overhead.wrapperTokens * requests;
    final int schema = overhead.schemaTokens * requests;
    final int inputTotal =
        inputTextTokens +
        imageTokens +
        catalogTokens +
        fixedPrompt +
        wrapper +
        schema;
    final int totalTokens = inputTotal + reservedOutput;
    final GenerationCost? cost = capabilities.pricing?.costFor(
      inputTokens: inputTotal,
      outputTokens: reservedOutput,
    );
    return GenerationEstimate(
      inputTextTokens: inputTextTokens,
      imageTokens: imageTokens,
      fixedPromptTokens: fixedPrompt,
      wrapperTokens: wrapper,
      schemaTokens: schema,
      catalogTokens: catalogTokens,
      reservedOutputTokens: reservedOutput,
      expectedOutputTokens: reservedOutput,
      totalTokens: totalTokens,
      plannedChunks: chunks.length,
      plannedRequests: chunks.length,
      retryAllowanceRequests: config.retryAllowanceRequests,
      pricingState: capabilities.pricingState,
      estimatorVersion: '${estimator.version}/planner-1',
      inputCost: cost?.input,
      outputCost: cost?.output,
      totalCost: cost?.total,
      currency: cost?.currency,
      unknownFields: _unknownFields(),
      confidence: _unknownFields().isEmpty ? 1 : 0.5,
    );
  }

  BudgetTrace _planBudget(List<_PlannedChunkData> planned, List<int> limits) {
    var maxCatalog = 0;
    var maxImage = 0;
    var maxLimit = _limitTarget;
    for (final _PlannedChunkData chunk in planned) {
      maxCatalog = math.max(
        maxCatalog,
        chunk.catalogTokens + chunk.labelTokens,
      );
      maxImage = math.max(
        maxImage,
        chunk.imagePartTokens + chunk.attachmentTokens,
      );
    }
    for (final int limit in limits) {
      maxLimit = math.max(maxLimit, limit);
    }
    return GenerationBudget.compute(
      capabilities: capabilities,
      limit: maxLimit,
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      catalogTokens: maxCatalog,
      imageTokens: maxImage,
      config: budgetConfig,
    ).trace;
  }
}

/// Итоговые данные фрагмента перед созданием [PlannedChunk] (лимит карточек
/// назначается после распределения).
class _PlannedChunkData {
  _PlannedChunkData({
    required this.index,
    required this.kind,
    required this.materialsText,
    required this.units,
    required this.imageParts,
    required this.imagePartIds,
    required this.catalogOnly,
    required this.catalogOnlyIds,
    required this.attachments,
    required this.pureTextTokens,
    required this.catalogTokens,
    required this.labelTokens,
    required this.imagePartTokens,
    required this.attachmentTokens,
    required this.bodyBytes,
    required this.splitDepth,
  });

  final int index;
  final ChunkKind kind;
  final String materialsText;
  final List<UnitSpan> units;
  final List<DocumentImage> imageParts;
  final List<String> imagePartIds;
  final List<DocumentImage> catalogOnly;
  final List<String> catalogOnlyIds;
  final List<GenerationAttachment> attachments;
  final int pureTextTokens;
  final int catalogTokens;
  final int labelTokens;
  final int imagePartTokens;
  final int attachmentTokens;
  final int bodyBytes;
  final int splitDepth;

  int get textTokens => pureTextTokens + catalogTokens + labelTokens;

  int get imageTokens => imagePartTokens + attachmentTokens;

  int get volume => textTokens + imageTokens;

  PlannedChunk toChunk({required int limit, int? index}) {
    return PlannedChunk(
      index: index ?? this.index,
      kind: kind,
      units: units,
      imageParts: imageParts,
      imagePartIds: imagePartIds,
      catalogOnly: catalogOnly,
      catalogOnlyIds: catalogOnlyIds,
      attachments: attachments,
      textTokens: textTokens,
      imageTokens: imageTokens,
      bodyBytes: bodyBytes,
      limit: math.max(1, limit),
      splitDepth: splitDepth,
      materialsText: materialsText,
    );
  }
}

/// Подобранные строки каталога.
class _CatalogSelection {
  const _CatalogSelection({
    required this.entries,
    required this.tokens,
    required this.bytes,
  });

  final List<_ImageEntry> entries;
  final int tokens;
  final int bytes;
}

final RegExp _sentenceBoundary = RegExp(r'[.!?…]+[ \t\n]+');
final RegExp _lineBoundary = RegExp(r'\n');

List<String> _splitAfter(String text, RegExp boundary) {
  final List<String> parts = <String>[];
  var start = 0;
  for (final Match match in boundary.allMatches(text)) {
    final int end = match.end;
    if (end <= start) continue;
    parts.add(text.substring(start, end));
    start = end;
  }
  if (start < text.length) parts.add(text.substring(start));
  if (parts.isEmpty) parts.add(text);
  return parts;
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
