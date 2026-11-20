/// Input Planner: сначала весь документ, потом минимальное число частей
/// (ADR-040 §3–4).
///
/// Планировщик решает **только** вопрос «отправлять материал целиком или
/// частями» и зависит исключительно от бюджета входа и резерва вывода
/// (`R`, который не зависит от числа запрошенных карточек). Количества
/// карточек в его интерфейсе нет — независимость от заказа структурная.
/// Домен не зависит от Flutter.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:cardflow/domain/generation/document_image.dart' show documentImageDigest;
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_request_budget.dart';
import 'package:cardflow/domain/generation/model_limits.dart';

/// Стратегия входа.
enum InputStrategy {
  /// Без материалов: тема/пожелания пользователя (ADR-024).
  promptOnly,

  /// Весь материал помещается в один запрос (после уменьшения резерва вывода).
  wholeDocument,

  /// Материал делится на минимальное число смысловых частей.
  fragmented,
}

/// Тип раздела для планирования и распределения карточек.
enum SectionKind {
  /// Содержательный раздел (может получать карточки).
  content,

  /// Служебный раздел (оглавление, литература, колонтитулы): 0 карточек.
  service,
}

/// Изображение, участвующее в запросе.
final class InputImage {
  /// Создаёт изображение плана.
  const InputImage({
    required this.id,
    required this.fileName,
    required this.bytes,
    this.tokens = 0,
    this.page,
    this.sectionId,
  }) : assert(id != ''),
       assert(fileName != '');

  /// Стабильный id (`img1…` или `doc:<файл>#<n>`).
  final String id;

  /// Имя файла-источника.
  final String fileName;

  /// Байты (до base64).
  final Uint8List bytes;

  /// Оценка токенов изображения.
  final int tokens;

  /// Номер страницы, если известен.
  final int? page;

  /// Раздел-владелец (`null` — изображение вне текста).
  final String? sectionId;
}

/// Раздел материала для Input Planner.
final class InputSection {
  /// Создаёт раздел с готовой оценкой токенов.
  const InputSection({
    required this.id,
    required this.tokens,
    this.title = '',
    this.text = '',
    this.kind = SectionKind.content,
    this.shortId,
    this.documentName = '',
    this.images = const <InputImage>[],
    this.unitIds = const <String>[],
  }) : assert(id != ''),
       assert(tokens >= 0);

  /// Полный стабильный id раздела (`doc:<файл>#<индекс>`).
  final String id;

  /// Заголовок раздела (может быть пустым).
  final String title;

  /// Текст раздела (для `<materials>` и упаковки).
  final String text;

  /// Оценка токенов текста.
  final int tokens;

  /// Служебный или содержательный раздел.
  final SectionKind kind;

  /// Короткий стабильный id для модели (`s3`).
  final String? shortId;

  /// Имя документа-источника (для строки `Файл: …`).
  final String documentName;

  /// Изображения раздела (в порядке следования).
  final List<InputImage> images;

  /// Идентификаторы единиц содержимого (для покрытия).
  final List<String> unitIds;

  /// Короткий id для `<materials>`/`<focus>`.
  String get promptId => shortId ?? id;
}

/// Часть материала (входная единица запросов).
final class InputPart {
  /// Создаёт часть.
  const InputPart({
    required this.index,
    required this.sections,
    required this.materialsText,
    required this.tokens,
    required this.bytes,
    this.outlineText = '',
    this.images = const <InputImage>[],
    this.catalogImages = const <InputImage>[],
    this.contextOnlyText = '',
  }) : assert(index >= 0),
       assert(tokens >= 0),
       assert(bytes >= 0);

  /// Номер части (с нуля).
  final int index;

  /// Разделы части в порядке документа.
  final List<InputSection> sections;

  /// Текст `<materials>` части (с заголовками файлов и разделов).
  final String materialsText;

  /// Оценка токенов материалов части (текст).
  final int tokens;

  /// Байты тела части (текст + base64 изображений + запас JSON).
  final int bytes;

  /// Компактное оглавление части (только при fragmented).
  final String outlineText;

  /// Изображения, байты которых отправляются с этой частью.
  final List<InputImage> images;

  /// Изображения части, которые остаются только в каталоге `<images>`
  /// (модель без Vision, лимит байт изображения, дубль байтов).
  final List<InputImage> catalogImages;

  /// Перекрытие с предыдущей частью (`<context_only>`).
  final String contextOnlyText;

  /// Номер части для текста «часть k из n» (с 1).
  int get partNumber => index + 1;

  /// Короткие id разделов части.
  List<String> get sectionPromptIds =>
      List<String>.unmodifiable(sections.map((InputSection s) => s.promptId));
}

/// План входа: стратегия, части, бюджет и статусы вложений.
final class InputPlan {
  /// Создаёт план входа.
  const InputPlan({
    required this.strategy,
    required this.parts,
    required this.fixedTokens,
    required this.inputTokens,
    required this.maxTokens,
    required this.accuracy,
    required this.budget,
    required this.materialTokens,
    this.materialBudgetPerPart,
    this.outlineReserveTokens = 0,
    this.warnings = const <PlanWarningCode>[],
    this.images = const <PlannedImage>[],
    this.contextTokens,
  });

  /// Стратегия входа.
  final InputStrategy strategy;

  /// Части материала (пусто для prompt-only).
  final List<InputPart> parts;

  /// Служебная часть запроса `P`, токенов.
  final int fixedTokens;

  /// Оценка входа: общая для whole, максимальная по части для fragmented.
  final int inputTokens;

  /// Резерв вывода на запрос: `maxTokens` для whole, `R` для fragmented.
  final int maxTokens;

  /// Точность подсчёта входа.
  final InputAccuracy accuracy;

  /// Бюджет (whole — всего запроса, fragmented — максимальной части).
  final RequestBudget budget;

  /// Сумма токенов фактически отправленных материалов.
  final int materialTokens;

  /// Максимальный объём материалов части (fragmented), токенов.
  final int? materialBudgetPerPart;

  /// Резерв на оглавление в каждой части, токенов.
  final int outlineReserveTokens;

  /// Предупреждения плана.
  final List<PlanWarningCode> warnings;

  /// Статусы изображений: передано модели / только каталог / исключено.
  final List<PlannedImage> images;

  /// Окно контекста модели (`null` — неизвестно).
  final int? contextTokens;

  /// Число частей материала.
  int get partCount => parts.length;

  /// true, если весь документ отправляется целиком.
  bool get isWholeDocument => strategy == InputStrategy.wholeDocument;

  /// true, если материал разделён.
  bool get isFragmented => strategy == InputStrategy.fragmented;

  /// true, если материалы отсутствуют.
  bool get isPromptOnly => strategy == InputStrategy.promptOnly;

  @override
  String toString() =>
      'InputPlan(${strategy.name}, parts: ${parts.length}, '
      'input: $inputTokens, max: $maxTokens)';
}

/// Итог рендера `<materials>`: текст и начала разделов внутри него.
final class RenderedMaterials {
  /// Создаёт результат рендера.
  const RenderedMaterials({required this.text, required this.sectionStarts});

  /// Текст `<materials>`.
  final String text;

  /// Начало текста раздела в [text] (`sectionId → offset`).
  final Map<String, int> sectionStarts;
}

/// Рендерит `<materials>`: строки `Файл: …` и `## [sN] Заголовок`, затем текст.
///
/// Один рендерер для Input Planner и сборки `PlannedChunk.units`: смещения
/// единиц обязаны совпадать с фактическим текстом запроса.
RenderedMaterials renderInputMaterials(List<InputSection> sections) {
  final StringBuffer buffer = StringBuffer();
  final Map<String, int> starts = <String, int>{};
  String? lastDocument;
  for (final InputSection section in sections) {
    final String document = section.documentName;
    if (document.isNotEmpty && document != lastDocument) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      buffer.write('Файл: $document\n');
      lastDocument = document;
    } else if (buffer.isNotEmpty) {
      buffer.write('\n');
    }
    final String title = section.title.trim().isEmpty
        ? ''
        : ' ${section.title.trim()}';
    buffer
      ..write('## [${section.promptId}]$title\n')
      ..write(section.text);
    starts[section.id] = buffer.length - section.text.length;
  }
  return RenderedMaterials(
    text: buffer.toString(),
    sectionStarts: Map<String, int>.unmodifiable(starts),
  );
}

/// Итог раздачи изображений по бюджету байтов.
final class _ImagePlacement {  const _ImagePlacement({
    required this.sent,
    required this.statuses,
    required this.bytes,
    required this.tokens,
    required this.payloadLimited,
  });

  final List<InputImage> sent;
  final List<PlannedImage> statuses;
  final int bytes;
  final int tokens;
  final bool payloadLimited;
}

/// Строит план входа (ADR-040 §3–4).
final class InputPlanner {
  /// Создаёт планировщик.
  const InputPlanner({this.config = const GenerationPlanningConfig()});

  /// Коэффициенты бюджета/вывода.
  final GenerationPlanningConfig config;

  /// Строит план входа.
  ///
  /// Ни [requestedCards], ни распределение карточек здесь не участвуют:
  /// разбиение зависит только от бюджета входа и резерва вывода `R`.
  InputPlan plan({
    required List<InputSection> sections,
    required ModelLimits limits,
    required int fixedTokens,
    required int desiredOutputTokens,
    InputAccuracy accuracy = InputAccuracy.estimated,
    int outlineReserveTokens = 0,
    List<InputImage> orphanImages = const <InputImage>[],
  }) {
    final double marginRate = config.margin(
      exact: accuracy == InputAccuracy.exact,
    );
    final Set<PlanWarningCode> warnings = <PlanWarningCode>{};
    final bool supportsImages = limits.supportsImageInput.value ?? true;
    final int? maxRequestBytes = limits.maxRequestBytes.value;
    final int textTokens = sections.fold<int>(
      0,
      (int sum, InputSection section) => sum + section.tokens,
    );
    final List<InputImage> allImages = <InputImage>[
      for (final InputSection section in sections) ...section.images,
      ...orphanImages,
    ];
    if (allImages.isNotEmpty && !supportsImages) {
      warnings.add(PlanWarningCode.imagesWithoutVision);
    }
    final int imageTokens = supportsImages
        ? allImages.fold<int>(0, (int sum, InputImage image) => sum + image.tokens)
        : 0;

    // -- prompt-only ---------------------------------------------------------
    if (sections.isEmpty) {
      final RequestBudget budget = RequestBudget.compute(
        limits: limits,
        fixedTokens: fixedTokens,
        materialTokens: 0,
        desiredOutputTokens: desiredOutputTokens,
        accuracy: accuracy,
        config: config,
      );
      return InputPlan(
        strategy: InputStrategy.promptOnly,
        parts: const <InputPart>[],
        fixedTokens: fixedTokens,
        inputTokens: budget.inputTokens,
        maxTokens: budget.maxTokens,
        accuracy: accuracy,
        budget: budget,
        materialTokens: 0,
        contextTokens: limits.contextTokens.value,
        warnings: List<PlanWarningCode>.unmodifiable(warnings),
      );
    }

    // -- предварительная проверка всего запроса ------------------------------
    final int? contextTokens = limits.contextTokens.value;
    RequestBudget budget = RequestBudget.compute(
      limits: limits,
      fixedTokens: fixedTokens,
      materialTokens: textTokens + imageTokens,
      desiredOutputTokens: desiredOutputTokens,
      accuracy: accuracy,
      config: config,
    );
    bool imagesOmittedByBudget = false;
    if (budget.contextExceeded && imageTokens > 0) {
      final RequestBudget withoutImages = RequestBudget.compute(
        limits: limits,
        fixedTokens: fixedTokens,
        materialTokens: textTokens,
        desiredOutputTokens: desiredOutputTokens,
        accuracy: accuracy,
        config: config,
      );
      if (!withoutImages.contextExceeded) {
        budget = withoutImages;
        imagesOmittedByBudget = true;
      }
    }
    final int materialTokens = textTokens +
        (imagesOmittedByBudget || !supportsImages ? 0 : imageTokens);
    final int minBatchTokens = config.tokensFor(config.minBatchCards);
    final bool withinConservativeBudget =
        contextTokens != null ||
        materialTokens <= config.unknownContextMaterialTokens;
    final bool wholeCapable = !budget.contextExceeded &&
        withinConservativeBudget &&
        budget.maxTokens >= minBatchTokens;

    if (contextTokens == null) {
      // Окно не подтверждено: предупреждаем всегда, когда оно влияет на план.
      warnings.add(PlanWarningCode.contextUnconfirmed);
    }

    if (wholeCapable) {
      return _buildWhole(
        sections: sections,
        limits: limits,
        fixedTokens: fixedTokens,
        desiredOutputTokens: desiredOutputTokens,
        accuracy: accuracy,
        allImages: allImages,
        supportsImages: supportsImages,
        imagesOmittedByBudget: imagesOmittedByBudget,
        maxRequestBytes: maxRequestBytes,
        textTokens: textTokens,
        warnings: warnings,
      );
    }

    return _buildFragmented(
      sections: sections,
      limits: limits,
      fixedTokens: fixedTokens,
      desiredOutputTokens: desiredOutputTokens,
      accuracy: accuracy,
      allImages: allImages,
      orphanImages: orphanImages,
      supportsImages: supportsImages,
      imagesOmittedByBudget: imagesOmittedByBudget,
      maxRequestBytes: maxRequestBytes,
      outlineReserveTokens: outlineReserveTokens,
      warnings: warnings,
      contextTokens: contextTokens,
      marginRate: marginRate,
    );
  }

  // -- whole document --------------------------------------------------------

  InputPlan _buildWhole({
    required List<InputSection> sections,
    required ModelLimits limits,
    required int fixedTokens,
    required int desiredOutputTokens,
    required InputAccuracy accuracy,
    required List<InputImage> allImages,
    required bool supportsImages,
    required bool imagesOmittedByBudget,
    required int? maxRequestBytes,
    required int textTokens,
    required Set<PlanWarningCode> warnings,
  }) {
    final String materialsText = renderMaterials(sections);
    final _ImagePlacement placement = _placeImages(
      images: allImages,
      supportsImages: supportsImages,
      omittedByTokenBudget: imagesOmittedByBudget,
      maxRequestBytes: maxRequestBytes,
      maxImageBytesPerImage: limits.maxImageBytesPerImage.value,
      textBytes: textBytes(materialsText),
    );
    if (placement.payloadLimited) {
      warnings.add(PlanWarningCode.payloadLimited);
    }
    final RequestBudget budget = RequestBudget.compute(
      limits: limits,
      fixedTokens: fixedTokens,
      materialTokens: textTokens + placement.tokens,
      desiredOutputTokens: desiredOutputTokens,
      accuracy: accuracy,
      config: config,
      requestBytes: placement.bytes,
    );
    final InputPart part = InputPart(
      index: 0,
      sections: List<InputSection>.unmodifiable(sections),
      materialsText: materialsText,
      tokens: textTokens,
      bytes: placement.bytes,
      images: List<InputImage>.unmodifiable(placement.sent),
      catalogImages: List<InputImage>.unmodifiable(<InputImage>[
        for (final InputImage image in allImages)
          if (!placement.sent.any((InputImage sent) => sent.id == image.id))
            image,
      ]),
    );
    return InputPlan(
      strategy: InputStrategy.wholeDocument,
      parts: List<InputPart>.unmodifiable(<InputPart>[part]),
      fixedTokens: fixedTokens,
      inputTokens: budget.inputTokens,
      maxTokens: budget.maxTokens,
      accuracy: accuracy,
      budget: budget,
      materialTokens: textTokens + placement.tokens,
      contextTokens: limits.contextTokens.value,
      warnings: List<PlanWarningCode>.unmodifiable(warnings),
      images: placement.statuses,
    );
  }

  // -- fragmented ------------------------------------------------------------

  InputPlan _buildFragmented({
    required List<InputSection> sections,
    required ModelLimits limits,
    required int fixedTokens,
    required int desiredOutputTokens,
    required InputAccuracy accuracy,
    required List<InputImage> allImages,
    required List<InputImage> orphanImages,
    required bool supportsImages,
    required bool imagesOmittedByBudget,
    required int? maxRequestBytes,
    required int outlineReserveTokens,
    required Set<PlanWarningCode> warnings,
    required int? contextTokens,
    required double marginRate,
  }) {
    final int fixedPart = fixedTokens + outlineReserveTokens;
    final bool inputOnly =
        limits.contextSemantics == ContextSemantics.inputOnly;
    final int outputCap = _outputCapOf(limits);
    final int outputReserve = math.min(
      outputCap,
      config.tokensFor(config.batchCardsCeiling),
    );
    final int? maxInputTokens = limits.maxInputTokens.value;

    final int materialBudget;
    if (contextTokens == null) {
      materialBudget = config.unknownContextMaterialTokens;
    } else if (inputOnly) {
      final int limit = maxInputTokens ?? contextTokens;
      materialBudget = math.max(
        1,
        (limit / (1 + marginRate)).floor() - fixedPart,
      );
    } else {
      final double fromContext =
          (contextTokens - outputReserve) / (1 + marginRate) - fixedPart;
      final double fromMaxInput = maxInputTokens == null
          ? double.infinity
          : maxInputTokens / (1 + marginRate) - fixedPart;
      materialBudget = math.max(
        1,
        math.min(fromContext, fromMaxInput).floor(),
      );
    }

    final int textTokens = sections.fold<int>(
      0,
      (int sum, InputSection section) => sum + section.tokens,
    );
    var partCount = math.max(1, (textTokens / materialBudget).ceil());
    // Байтовое ограничение: тело части не больше лимита запроса.
    if (maxRequestBytes != null) {
      final int textBytesTotal = textBytes(renderMaterials(sections));
      final int availableBytes = math.max(
        1,
        maxRequestBytes - config.jsonBodyOverheadBytes,
      );
      partCount = math.max(partCount, (textBytesTotal / availableBytes).ceil());
    }

    List<List<InputSection>> packed = _packBalanced(
      sections: sections,
      partCount: partCount,
      materialBudget: materialBudget,
    );
    partCount = packed.length;

    final Set<String> seenDigests = <String>{};
    final _ImagePlacement placementAll = _placeImages(
      images: allImages,
      supportsImages: supportsImages,
      omittedByTokenBudget: imagesOmittedByBudget,
      maxRequestBytes: null,
      maxImageBytesPerImage: limits.maxImageBytesPerImage.value,
      textBytes: 0,
    );
    final Map<String, PlannedImage> statuses = <String, PlannedImage>{
      for (final PlannedImage image in placementAll.statuses)
        image.id: image,
    };
    final List<InputImage> remaining = <InputImage>[
      for (final InputImage image in allImages)
        if (!imagesOmittedByBudget &&
            supportsImages &&
            statuses[image.id]?.sentToModel == true)
          image,
    ];
    final Map<String, List<InputImage>> imagesBySection =
        <String, List<InputImage>>{};
    final List<InputImage> orphans = <InputImage>[];
    for (final InputImage image in remaining) {
      final String? owner = image.sectionId ??
          _ownerOf(image, sections) ??
          _ownerOf(image, sections);
      if (owner == null) {
        orphans.add(image);
      } else {
        (imagesBySection[owner] ??= <InputImage>[]).add(image);
      }
    }

    final List<InputPart> parts = <InputPart>[];
    final Set<String> placedImageIds = <String>{};
    for (var index = 0; index < packed.length; index++) {
      final List<InputSection> partSections = packed[index];
      final String materialsText = renderMaterials(partSections);
      final int partTextTokens = partSections.fold<int>(
        0,
        (int sum, InputSection section) => sum + section.tokens,
      );
      final List<InputImage> images = <InputImage>[
        for (final InputSection section in partSections)
          ...?imagesBySection[section.id],
        if (index == 0) ...orphans,
      ];
      final _ImagePlacement placement = _placeImages(
        images: images,
        supportsImages: supportsImages,
        omittedByTokenBudget: false,
        maxRequestBytes: maxRequestBytes,
        maxImageBytesPerImage: limits.maxImageBytesPerImage.value,
        seenDigests: seenDigests,
        textBytes: textBytes(materialsText),
        tokenBudget: materialBudget - partTextTokens,
      );
      for (final PlannedImage image in placement.statuses) {
        statuses[image.id] = image;
      }
      if (placement.payloadLimited) {
        warnings.add(PlanWarningCode.payloadLimited);
      }
      for (final InputImage image in placement.sent) {
        placedImageIds.add(image.id);
      }
      parts.add(
        InputPart(
          index: index,
          sections: List<InputSection>.unmodifiable(partSections),
          materialsText: materialsText,
          tokens: partTextTokens,
          bytes: placement.bytes,
          outlineText: outlineOf(partSections, maxTokens: outlineReserveTokens),
          images: List<InputImage>.unmodifiable(placement.sent),
          catalogImages: List<InputImage>.unmodifiable(<InputImage>[
            for (final InputImage image in images)
              if (!placement.sent.any((InputImage sent) => sent.id == image.id))
                image,
          ]),
        ),
      );
    }

    // Изображения, чьи разделы не попали ни в одну часть, помечаем явно.
    for (final InputImage image in allImages) {
      statuses.putIfAbsent(
        image.id,
        () => PlannedImage(
          id: image.id,
          fileName: image.fileName,
          status: imagesOmittedByBudget
              ? ImageParticipationStatus.omittedBudget
              : supportsImages
              ? ImageParticipationStatus.omittedPayload
              : ImageParticipationStatus.unsupportedModel,
          page: image.page,
          tokens: image.tokens,
        ),
      );
      if (!placedImageIds.contains(image.id) &&
          statuses[image.id] != null &&
          statuses[image.id]!.sentToModel) {
        statuses[image.id] = PlannedImage(
          id: image.id,
          fileName: image.fileName,
          status: ImageParticipationStatus.omittedPayload,
          page: image.page,
          tokens: image.tokens,
        );
      }
    }

    // Бюджет максимальной части — то, что видит исполнитель.
    RequestBudget maxBudget = RequestBudget.compute(
      limits: limits,
      fixedTokens: fixedPart,
      materialTokens: 0,
      desiredOutputTokens: outputReserve,
      accuracy: accuracy,
      config: config,
    );
    for (final InputPart part in parts) {
      final int partImageTokens = part.images.fold<int>(
        0,
        (int sum, InputImage image) => sum + image.tokens,
      );
      final RequestBudget partBudget = RequestBudget.compute(
        limits: limits,
        fixedTokens: fixedPart,
        materialTokens: part.tokens + partImageTokens,
        desiredOutputTokens: outputReserve,
        accuracy: accuracy,
        config: config,
        requestBytes: part.bytes,
      );
      if (partBudget.inputTokens > maxBudget.inputTokens) {
        maxBudget = partBudget;
      }
    }
    return InputPlan(
      strategy: InputStrategy.fragmented,
      parts: List<InputPart>.unmodifiable(parts),
      fixedTokens: fixedTokens,
      inputTokens: maxBudget.inputTokens,
      maxTokens: outputReserve,
      accuracy: accuracy,
      budget: maxBudget,
      materialTokens: parts.fold<int>(
        0,
        (int sum, InputPart part) =>
            sum +
            part.tokens +
            part.images.fold<int>(
              0,
              (int inner, InputImage image) => inner + image.tokens,
            ),
      ),
      materialBudgetPerPart: materialBudget,
      outlineReserveTokens: outlineReserveTokens,
      warnings: List<PlanWarningCode>.unmodifiable(warnings),
      images: List<PlannedImage>.unmodifiable(statuses.values),
      contextTokens: contextTokens,
    );
  }

  /// Потолок вывода модели с учётом допущений (как `RequestBudget`).
  int _outputCapOf(ModelLimits limits) {
    final int? maxOutput = limits.maxOutputTokens.value;
    if (maxOutput != null) return maxOutput;
    final int? context = limits.contextTokens.value;
    if (context == null) return config.unknownContextOutputTokens;
    return math.min(config.defaultOutputTokens, math.max(1, context ~/ 2));
  }

  /// Упаковка разделов в части: цель `materialTokens / partCount`, не выше
  /// [materialBudget]; порядок документа сохраняется.
  List<List<InputSection>> _packBalanced({
    required List<InputSection> sections,
    required int partCount,
    required int materialBudget,
  }) {
    if (sections.isEmpty) return const <List<InputSection>>[];
    final int total = sections.fold<int>(
      0,
      (int sum, InputSection section) => sum + section.tokens,
    );
    final int ideal = (total / partCount).ceil();
    final int target = math.max(1, math.min(ideal, materialBudget));
    final List<List<InputSection>> packed = <List<InputSection>>[];
    List<InputSection> current = <InputSection>[];
    var currentTokens = 0;
    for (final InputSection section in sections) {
      if (current.isNotEmpty && currentTokens + section.tokens > target) {
        packed.add(current);
        current = <InputSection>[];
        currentTokens = 0;
      }
      current.add(section);
      currentTokens += section.tokens;
    }
    if (current.isNotEmpty) packed.add(current);
    return packed;
  }

  /// Раздаёт изображения по байтовому и токенному бюджету.
  _ImagePlacement _placeImages({
    required List<InputImage> images,
    required bool supportsImages,
    required bool omittedByTokenBudget,
    required int? maxRequestBytes,
    int? maxImageBytesPerImage,
    Set<String>? seenDigests,
    required int textBytes,
    int? tokenBudget,
  }) {
    final List<InputImage> sent = <InputImage>[];
    final List<PlannedImage> statuses = <PlannedImage>[];
    int bytes = textBytes + config.jsonBodyOverheadBytes;
    int tokens = 0;
    var payloadLimited = false;
    final Set<String> digests = seenDigests ?? <String>{};
    for (final InputImage image in images) {
      if (!supportsImages) {
        statuses.add(
          PlannedImage(
            id: image.id,
            fileName: image.fileName,
            status: ImageParticipationStatus.unsupportedModel,
            page: image.page,
            tokens: image.tokens,
          ),
        );
        continue;
      }
      if (omittedByTokenBudget) {
        statuses.add(
          PlannedImage(
            id: image.id,
            fileName: image.fileName,
            status: ImageParticipationStatus.omittedBudget,
            page: image.page,
            tokens: image.tokens,
          ),
        );
        continue;
      }
      if (tokenBudget != null && tokens + image.tokens > tokenBudget) {
        statuses.add(
          PlannedImage(
            id: image.id,
            fileName: image.fileName,
            status: ImageParticipationStatus.omittedBudget,
            page: image.page,
            tokens: image.tokens,
          ),
        );
        continue;
      }
      if (maxImageBytesPerImage != null &&
          image.bytes.length > maxImageBytesPerImage) {
        statuses.add(
          PlannedImage(
            id: image.id,
            fileName: image.fileName,
            status: ImageParticipationStatus.catalogOnly,
            page: image.page,
            tokens: image.tokens,
          ),
        );
        continue;
      }
      final String digest = documentImageDigest(image.bytes);
      if (!digests.add(digest)) {
        statuses.add(
          PlannedImage(
            id: image.id,
            fileName: image.fileName,
            status: ImageParticipationStatus.catalogOnly,
            page: image.page,
            tokens: image.tokens,
          ),
        );
        continue;
      }
      final int encoded = base64EncodedByteLength(image.bytes.length);
      if (maxRequestBytes != null && bytes + encoded > maxRequestBytes) {
        statuses.add(
          PlannedImage(
            id: image.id,
            fileName: image.fileName,
            status: ImageParticipationStatus.omittedPayload,
            page: image.page,
            tokens: image.tokens,
          ),
        );
        payloadLimited = true;
        continue;
      }
      sent.add(image);
      bytes += encoded;
      tokens += image.tokens;
      statuses.add(
        PlannedImage(
          id: image.id,
          fileName: image.fileName,
          status: ImageParticipationStatus.sentToModel,
          page: image.page,
          tokens: image.tokens,
        ),
      );
    }
    return _ImagePlacement(
      sent: List<InputImage>.unmodifiable(sent),
      statuses: List<PlannedImage>.unmodifiable(statuses),
      bytes: bytes,
      tokens: tokens,
      payloadLimited: payloadLimited,
    );
  }

  String? _ownerOf(InputImage image, List<InputSection> sections) {
    for (final InputSection section in sections) {
      if (section.images.any((InputImage i) => i.id == image.id)) {
        return section.id;
      }
    }
    return null;
  }

  /// Компактное оглавление части: заголовки разделов (≤ [maxTokens] токенов).
  String outlineOf(List<InputSection> sections, {int maxTokens = 0}) {
    final List<String> titles = <String>[
      for (final InputSection section in sections)
        if (section.title.trim().isNotEmpty) section.title.trim(),
    ];
    if (titles.isEmpty) return '';
    final StringBuffer buffer = StringBuffer('Оглавление: ');
    for (var index = 0; index < titles.length; index++) {
      final String candidate = index == 0
          ? '$buffer${titles[index]}'
          : '$buffer · ${titles[index]}';
      if (maxTokens > 0 &&
          textBytes(candidate) / 2.5 > maxTokens) {
        break;
      }
      buffer.write(index == 0 ? titles[index] : ' · ${titles[index]}');
    }
    return buffer.toString();
  }

  /// Рендер `<materials>`: заголовки файлов и разделов со стабильными id.
  String renderMaterials(List<InputSection> sections) =>
      renderInputMaterials(sections).text;

  /// Байты текста в UTF-8.
  static int textBytes(String text) => utf8.encode(text).length;

  /// Длина тела после base64 (округление вверх до 4 байт).
  static int base64EncodedByteLength(int bytes) {
    if (bytes <= 0) return 0;
    return ((bytes + 2) ~/ 3) * 4;
  }

  /// Сумма байтов изображений после base64.
  static int imageBytes(Iterable<InputImage> images) {
    var total = 0;
    for (final InputImage image in images) {
      total += base64EncodedByteLength(image.bytes.length);
    }
    return total;
  }

  /// Бюджет материалов части: `floor((limit − R)/(1+m)) − P`.
  static int materialBudget({
    required int limit,
    required int outputReserve,
    required double margin,
    required int fixedPartTokens,
    bool subtractOutput = true,
  }) {
    final double room = subtractOutput
        ? (limit - outputReserve).toDouble()
        : limit.toDouble();
    final double available = room / (1 + margin) - fixedPartTokens;
    return math.max(1, available.floor());
  }
}
