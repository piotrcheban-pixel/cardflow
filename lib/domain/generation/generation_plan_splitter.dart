/// Дробление фрагмента плана при восстановлении после ошибки (раздел F аудита
/// TASK 01).
///
/// Делится **только проблемная часть плана**: переполнение контекста, слишком
/// большое тело запроса или обрезанный ответ модели. Материалы при этом не
/// теряются: `unitIds`, порядок единиц, привязка изображений к файлам и
/// страницам сохраняются, а лимиты карточек делятся между детьми (сумма равна
/// лимиту родителя, каждый ≥ 1).
///
/// Дробление ограничено [maxSplitDepth] (последний предохранитель от
/// бесконечного деления). Prompt-only фрагменты не делятся: у них нет
/// материалов. Домен не зависит от Flutter.
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// Делит фрагмент плана на две части для восстановления.
class GenerationPlanSplitter {
  /// Создаёт делитель.
  const GenerationPlanSplitter({
    this.estimator = const HeuristicContentTokenEstimator(),
    this.imageTokenModel,
    this.maxSplitDepth = 3,
    this.minTextLength = 40,
    this.bodyOverheadBytes = 512,
  }) : assert(maxSplitDepth >= 0),
       assert(minTextLength > 0);

  /// Оценщик токенов (для пересчёта детей).
  final ContentTokenEstimator estimator;

  /// Оценщик токенов изображений модели (если известен).
  final ImageTokenModel? imageTokenModel;

  /// Максимальная глубина дробления (0 — делить нельзя).
  final int maxSplitDepth;

  /// Минимальная длина текста, ниже которой дробление не даёт пользы.
  final int minTextLength;

  /// Служебный запас тела запроса, байт (оценка).
  final int bodyOverheadBytes;

  /// Копия с оценщиком/моделью изображений планировщика (TASK 03).
  ///
  /// Production-пайплайн не должен считать детей другим оценщиком, чем родителя
  /// (L129): перед дроблением он передаёт сюда оценщик плана и
  /// `capabilities.imageTokens`. `imageTokenModel` передаётся как есть: `null`
  /// означает «формулы модели нет», а не «оставить прежнюю».
  GenerationPlanSplitter withContext({
    ContentTokenEstimator? estimator,
    ImageTokenModel? imageTokenModel,
    int? maxSplitDepth,
  }) {
    return GenerationPlanSplitter(
      estimator: estimator ?? this.estimator,
      imageTokenModel: imageTokenModel,
      maxSplitDepth: maxSplitDepth ?? this.maxSplitDepth,
      minTextLength: minTextLength,
      bodyOverheadBytes: bodyOverheadBytes,
    );
  }

  /// Делит [chunk] на две части; `null` — деление невозможно/бесполезно.
  ///
  /// [allowLimitOverflow] — последняя попытка восстановления (context overflow,
  /// 413, повторная обрезка): если у фрагмента `limit == 1`, дети получают по 1
  /// карточке. Сумма лимитов тогда больше родителя — это осознанное исключение
  /// только для восстановления, а не правило планирования; заказ пользователя
  /// при этом не меняется (`requestedCards` остаётся прежним).
  List<PlannedChunk>? split(
    PlannedChunk chunk, {
    bool allowLimitOverflow = false,
  }) {
    if (chunk.isPromptOnly) return null;
    if (chunk.splitDepth >= maxSplitDepth) return null;
    if (chunk.limit < 2 && !allowLimitOverflow) return null;
    final List<int>? limits = _limits(chunk.limit, allowLimitOverflow);
    if (limits == null) return null;
    if (chunk.units.length >= 2) return _splitByUnits(chunk, limits);
    if (chunk.attachments.length >= 2 && chunk.units.isEmpty) {
      return _splitAttachments(chunk, limits);
    }
    if (chunk.units.length == 1 &&
        chunk.materialsText.trim().length >= minTextLength) {
      return _splitSingleUnit(chunk, limits);
    }
    return null;
  }

  List<PlannedChunk>? _splitByUnits(PlannedChunk chunk, List<int> limits) {
    final List<UnitSpan> units = chunk.units;
    final int total = units.fold<int>(
      0,
      (int sum, UnitSpan span) => sum + span.tokens,
    );
    var splitIndex = units.length ~/ 2;
    if (total > 0) {
      var cumulative = 0;
      for (var index = 0; index < units.length - 1; index++) {
        cumulative += units[index].tokens;
        if (cumulative >= total ~/ 2) {
          splitIndex = index + 1;
          break;
        }
      }
    }
    splitIndex = splitIndex.clamp(1, units.length - 1);
    final int boundary = units[splitIndex].start;
    if (boundary <= 0 || boundary >= chunk.materialsText.length) return null;
    final String leftText = chunk.materialsText.substring(0, boundary);
    final String rightText = chunk.materialsText.substring(boundary);
    if (leftText.trim().isEmpty || rightText.trim().isEmpty) return null;
    final List<UnitSpan> leftUnits = units.sublist(0, splitIndex);
    final List<UnitSpan> rightUnits = <UnitSpan>[
      for (final UnitSpan span in units.sublist(splitIndex))
        UnitSpan(
          unitId: span.unitId,
          start: span.start - boundary,
          end: span.end - boundary,
          tokens: span.tokens,
        ),
    ];
    final Set<String> leftSections = _sectionIdsOf(leftUnits);
    final _ImageSplit leftImages = _imagesForSection(
      chunk,
      leftSections,
      takeWhenMatching: true,
    );
    final _ImageSplit rightImages = _imagesForSection(
      chunk,
      leftSections,
      takeWhenMatching: false,
    );
    final int depth = chunk.splitDepth + 1;
    return <PlannedChunk>[
      _build(
        text: leftText,
        units: leftUnits,
        imageParts: leftImages.parts,
        imagePartIds: leftImages.partIds,
        catalogOnly: leftImages.catalogOnly,
        catalogOnlyIds: leftImages.catalogOnlyIds,
        attachments: chunk.attachments,
        limit: limits[0],
        splitDepth: depth,
      ),
      _build(
        text: rightText,
        units: rightUnits,
        imageParts: rightImages.parts,
        imagePartIds: rightImages.partIds,
        catalogOnly: rightImages.catalogOnly,
        catalogOnlyIds: rightImages.catalogOnlyIds,
        attachments: const <GenerationAttachment>[],
        limit: limits[1],
        splitDepth: depth,
      ),
    ];
  }

  List<PlannedChunk>? _splitAttachments(PlannedChunk chunk, List<int> limits) {
    final List<GenerationAttachment> attachments = chunk.attachments;
    final int middle = (attachments.length / 2).ceil();
    final List<GenerationAttachment> leftAttachments = attachments.sublist(
      0,
      middle,
    );
    final List<GenerationAttachment> rightAttachments = attachments.sublist(
      middle,
    );
    final Set<String> leftFiles = <String>{
      for (final GenerationAttachment attachment in leftAttachments)
        attachment.fileName,
    };
    final _ImageSplit leftImages = _imagesForFiles(chunk, leftFiles, true);
    final _ImageSplit rightImages = _imagesForFiles(chunk, leftFiles, false);
    final int depth = chunk.splitDepth + 1;
    return <PlannedChunk>[
      _build(
        text: '',
        units: const <UnitSpan>[],
        imageParts: leftImages.parts,
        imagePartIds: leftImages.partIds,
        catalogOnly: leftImages.catalogOnly,
        catalogOnlyIds: leftImages.catalogOnlyIds,
        attachments: leftAttachments,
        limit: limits[0],
        splitDepth: depth,
      ),
      _build(
        text: '',
        units: const <UnitSpan>[],
        imageParts: rightImages.parts,
        imagePartIds: rightImages.partIds,
        catalogOnly: rightImages.catalogOnly,
        catalogOnlyIds: rightImages.catalogOnlyIds,
        attachments: rightAttachments,
        limit: limits[1],
        splitDepth: depth,
      ),
    ];
  }

  List<PlannedChunk>? _splitSingleUnit(PlannedChunk chunk, List<int> limits) {
    final String text = chunk.materialsText;
    final int boundary = _textBoundary(text);
    if (boundary <= 0 || boundary >= text.length) return null;
    final String leftText = text.substring(0, boundary);
    final String rightText = text.substring(boundary);
    if (leftText.trim().isEmpty || rightText.trim().isEmpty) return null;
    final UnitSpan original = chunk.units.single;
    final int depth = chunk.splitDepth + 1;
    final UnitSpan leftSpan = UnitSpan(
      unitId: original.unitId,
      start: original.start,
      end: original.start + boundary,
      tokens: estimator.estimateText(leftText),
    );
    final UnitSpan rightSpan = UnitSpan(
      unitId: '${original.unitId}~r$depth',
      start: 0,
      end: rightText.length,
      tokens: estimator.estimateText(rightText),
    );
    return <PlannedChunk>[
      _build(
        text: leftText,
        units: <UnitSpan>[leftSpan],
        imageParts: chunk.imageParts,
        imagePartIds: chunk.imagePartIds,
        catalogOnly: chunk.catalogOnly,
        catalogOnlyIds: chunk.catalogOnlyIds,
        attachments: chunk.attachments,
        limit: limits[0],
        splitDepth: depth,
      ),
      _build(
        text: rightText,
        units: <UnitSpan>[rightSpan],
        imageParts: const <DocumentImage>[],
        imagePartIds: const <String>[],
        catalogOnly: const <DocumentImage>[],
        catalogOnlyIds: const <String>[],
        attachments: const <GenerationAttachment>[],
        limit: limits[1],
        splitDepth: depth,
      ),
    ];
  }

  /// Граница деления текста: конец предложения/строки ближе к середине.
  int _textBoundary(String text) {
    final int middle = text.length ~/ 2;
    final int minBoundary = (text.length * 0.3).round();
    final int maxBoundary = (text.length * 0.7).round();
    for (var distance = 0; distance < middle; distance++) {
      for (final int candidate in <int>[middle + distance, middle - distance]) {
        if (candidate <= minBoundary || candidate >= maxBoundary) continue;
        if (candidate <= 0 || candidate >= text.length) continue;
        final String before = text.substring(candidate - 1, candidate);
        if (before == '\n' ||
            before == '.' ||
            before == '!' ||
            before == '?' ||
            before == ' ') {
          return candidate;
        }
      }
    }
    // Середина может разрезать суррогатную пару — сдвигаем на руну назад.
    var safe = middle;
    if (safe > 0 &&
        _isLowSurrogate(text.codeUnitAt(safe)) &&
        _isHighSurrogate(text.codeUnitAt(safe - 1))) {
      safe--;
    }
    return safe;
  }

  _ImageSplit _imagesForSection(
    PlannedChunk chunk,
    Set<String> sections, {
    required bool takeWhenMatching,
  }) {
    return _imagesFor(chunk, (DocumentImage image) {
      final bool matching = sections.contains(
        _sectionKeyOf(image.fileName, image.sectionIndex),
      );
      return matching == takeWhenMatching;
    });
  }

  _ImageSplit _imagesForFiles(
    PlannedChunk chunk,
    Set<String> files,
    bool takeWhenMatching,
  ) {
    return _imagesFor(chunk, (DocumentImage image) {
      final bool matching = files.contains(image.fileName);
      return matching == takeWhenMatching;
    });
  }

  /// Раскладывает части и строки каталога по предикату (без дублей).
  _ImageSplit _imagesFor(
    PlannedChunk chunk,
    bool Function(DocumentImage image) belongs,
  ) {
    final List<DocumentImage> parts = <DocumentImage>[];
    final List<String> partIds = <String>[];
    final List<DocumentImage> catalog = <DocumentImage>[];
    final List<String> catalogIds = <String>[];
    final Set<String> partIdSet = <String>{};
    final Set<String> catalogIdSet = <String>{};
    // Списки id и изображений обязаны соответствовать по порядку, но защищаемся
    // от легаси-фрагментов без id: изображение не должно потеряться при
    // дроблении (требование «сохранять исходные идентификаторы единиц»).
    for (var index = 0; index < chunk.imageParts.length; index++) {
      final DocumentImage image = chunk.imageParts[index];
      final String id = index < chunk.imagePartIds.length
          ? chunk.imagePartIds[index]
          : 'img:${image.fileName}#p$index';
      if (!belongs(image)) continue;
      if (!partIdSet.add(id)) continue;
      partIds.add(id);
      parts.add(image);
    }
    for (var index = 0; index < chunk.catalogOnly.length; index++) {
      final DocumentImage image = chunk.catalogOnly[index];
      final String id = index < chunk.catalogOnlyIds.length
          ? chunk.catalogOnlyIds[index]
          : 'img:${image.fileName}#c$index';
      if (!belongs(image)) continue;
      if (partIdSet.contains(id) || !catalogIdSet.add(id)) continue;
      catalogIds.add(id);
      catalog.add(image);
    }
    return _ImageSplit(
      parts: parts,
      partIds: partIds,
      catalogOnly: catalog,
      catalogOnlyIds: catalogIds,
    );
  }

  /// Лимиты детей: сумма равна лимиту родителя; при [allowLimitOverflow] и
  /// `limit == 1` — по одной карточке каждому (только восстановление).
  List<int>? _limits(int limit, bool allowLimitOverflow) {
    if (limit < 2) {
      return allowLimitOverflow ? <int>[1, 1] : null;
    }
    final int left = limit ~/ 2;
    return <int>[math.max(1, left), math.max(1, limit - left)];
  }

  PlannedChunk _build({
    required String text,
    required List<UnitSpan> units,
    required List<DocumentImage> imageParts,
    required List<String> imagePartIds,
    required List<DocumentImage> catalogOnly,
    required List<String> catalogOnlyIds,
    required List<GenerationAttachment> attachments,
    required int limit,
    required int splitDepth,
  }) {
    final bool hasText = text.trim().isNotEmpty;
    final bool hasParts = imageParts.isNotEmpty || attachments.isNotEmpty;
    final ChunkKind kind = hasText && hasParts
        ? ChunkKind.mixed
        : hasText
        ? ChunkKind.text
        : hasParts
        ? ChunkKind.images
        : ChunkKind.catalog;
    var imageTokens = 0;
    var imageBytes = 0;
    for (final DocumentImage image in imageParts) {
      imageTokens += estimator
          .estimateImage(
            width: image.width,
            height: image.height,
            bytes: image.bytes.length,
            model: imageTokenModel,
          )
          .tokens;
      imageBytes += image.bytes.length;
    }
    for (final GenerationAttachment attachment in attachments) {
      imageTokens += estimator
          .estimateImage(bytes: attachment.bytes.length, model: imageTokenModel)
          .tokens;
      imageBytes += attachment.bytes.length;
    }
    final int bodyBytes =
        utf8.encode(text).length +
        base64EncodedByteLength(imageBytes) +
        bodyOverheadBytes;
    return PlannedChunk(
      index: 1,
      kind: kind,
      units: units,
      imageParts: imageParts,
      imagePartIds: imagePartIds,
      catalogOnly: catalogOnly,
      catalogOnlyIds: catalogOnlyIds,
      attachments: attachments,
      textTokens: estimator.estimateText(text),
      imageTokens: imageTokens,
      bodyBytes: bodyBytes,
      limit: limit,
      splitDepth: splitDepth,
      materialsText: text,
    );
  }

  Set<String> _sectionIdsOf(List<UnitSpan> units) {
    final Set<String> sections = <String>{};
    for (final UnitSpan span in units) {
      final String? section = _sectionOfUnitId(span.unitId);
      if (section != null) sections.add(section);
    }
    return sections;
  }

  /// `doc:<файл>#<раздел>#<фрагмент>` → `<файл>#<раздел>`.
  String? _sectionOfUnitId(String id) {
    if (!id.startsWith('doc:')) return null;
    final List<String> parts = id.substring(4).split('#');
    if (parts.length < 2) return null;
    return _sectionKeyOf(parts[0], int.tryParse(parts[1]) ?? -1);
  }

  String _sectionKeyOf(String fileName, int sectionIndex) =>
      '$fileName#$sectionIndex';
}

/// Изображения одной из двух частей при дроблении.
class _ImageSplit {
  _ImageSplit({
    required this.parts,
    required this.partIds,
    required this.catalogOnly,
    required this.catalogOnlyIds,
  });

  final List<DocumentImage> parts;
  final List<String> partIds;
  final List<DocumentImage> catalogOnly;
  final List<String> catalogOnlyIds;
}

bool _isHighSurrogate(int codeUnit) => codeUnit >= 0xD800 && codeUnit <= 0xDBFF;

bool _isLowSurrogate(int codeUnit) => codeUnit >= 0xDC00 && codeUnit <= 0xDFFF;
