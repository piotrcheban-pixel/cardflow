/// Нарезка материалов генерации на фрагменты по бюджету модели (SPEC A8.5 шаг 5,
/// ADR-015). Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/token_estimator.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Максимальное число карточек в одном запросе (`<limit>`).
const int kMaxCardsPerChunk = 20;

/// Оценка стоимости одного изображения/PDF-скана в токенах (для UI/оценки).
const int kImageTokenEstimate = 1000;

/// Префикс строки-заголовка файла в `<materials>` (SPEC A8.1: «Файл: <имя>»).
const String kMaterialsFileHeaderPrefix = 'Файл: ';

/// Один фрагмент материалов для вызова модели.
class GenerationChunk {
  /// Создаёт фрагмент.
  const GenerationChunk({
    required this.index,
    required this.materialsText,
    required this.sourceFiles,
    required this.limit,
    this.splitAttempted = false,
    this.images = const <GenerationAttachment>[],
    this.documentImages = const <DocumentImage>[],
    this.unitIds = const <String>[],
    this.splitDepth = 0,
    this.imageParts = const <DocumentImage>[],
    this.catalogOnly = const <DocumentImage>[],
  });

  /// Порядковый номер фрагмента (с 1) для прогресса «фрагмент K из M».
  final int index;

  /// Текст материалов фрагмента. Пустой у фрагмента-вложения.
  final String materialsText;

  /// Имена файлов, из которых собран фрагмент.
  final List<String> sourceFiles;

  /// Максимальное число карточек в ответе.
  final int limit;

  /// Фрагмент уже дробился после `truncated` (дробить можно только раз).
  final bool splitAttempted;

  /// Вложения фрагмента (не больше одного файла на MVP-запрос).
  final List<GenerationAttachment> images;

  /// Изображения из прикреплённых файлов этого фрагмента (fix-gen, Д3).
  final List<DocumentImage> documentImages;

  /// Стабильные id единиц содержимого фрагмента (новый путь-план, TASK 02B).
  ///
  /// У фрагментов старого пути (`chunkDocuments`/`chunkAll`) список пуст.
  final List<String> unitIds;

  /// Глубина дробления по плану (0 — исходный фрагмент).
  final int splitDepth;

  /// Изображения, выбранные планом как image-части (новый путь).
  ///
  /// [documentImages] у фрагмента плана содержит и части, и строки каталога
  /// (`catalogOnly`), чтобы модель видела `image_id` всех изображений; список
  /// байтов, которые нужно отправить, — здесь.
  final List<DocumentImage> imageParts;

  /// Изображения, которые у плана остались только строками каталога.
  final List<DocumentImage> catalogOnly;

  /// true, если фрагмент несёт вложение.
  bool get hasImages => images.isNotEmpty;

  /// true, если у фрагмента есть каталог `<images>` из документов.
  bool get hasDocumentImages => documentImages.isNotEmpty;

  /// Оценка токенов фрагмента (для тестов и отладочного вывода).
  int estimatedTokens([TokenEstimator estimator = const TokenEstimator()]) =>
      estimator.estimate(materialsText) +
      images.length * kImageTokenEstimate +
      documentImages.length * kImageTokenEstimate;

  /// Копия с изменёнными полями.
  GenerationChunk copyWith({
    int? index,
    String? materialsText,
    List<String>? sourceFiles,
    int? limit,
    bool? splitAttempted,
    List<GenerationAttachment>? images,
    List<DocumentImage>? documentImages,
    List<String>? unitIds,
    int? splitDepth,
    List<DocumentImage>? imageParts,
    List<DocumentImage>? catalogOnly,
  }) {
    return GenerationChunk(
      index: index ?? this.index,
      materialsText: materialsText ?? this.materialsText,
      sourceFiles: sourceFiles ?? this.sourceFiles,
      limit: limit ?? this.limit,
      splitAttempted: splitAttempted ?? this.splitAttempted,
      images: images ?? this.images,
      documentImages: documentImages ?? this.documentImages,
      unitIds: unitIds ?? this.unitIds,
      splitDepth: splitDepth ?? this.splitDepth,
      imageParts: imageParts ?? this.imageParts,
      catalogOnly: catalogOnly ?? this.catalogOnly,
    );
  }

  @override
  String toString() =>
      'GenerationChunk($index, ${materialsText.length} символов, '
      'images: ${images.length}, documentImages: ${documentImages.length}, '
      'limit: $limit, split: $splitAttempted)';
}

/// Делит текст на фрагменты, укладывающиеся в бюджет модели.
///
/// Старый путь (`chunkDocuments`/`chunkAll`) сохранён без изменений поведения:
/// он используется `GenerationPipeline` до интеграции планировщика. Новый путь
/// — [planChunks]/[chunksFromPlan] поверх `GenerationChunkPlanner` (D.4–D.7):
/// фрагменты планируются по единицам содержимого, изображения и лимиты
/// карточек считаются от возможностей модели.
class GenerationChunker {
  /// Создаёт чанкер.
  const GenerationChunker({
    this.estimator = const TokenEstimator(),
    this.maxCardsPerChunk = kMaxCardsPerChunk,
    this.planner = const GenerationChunkPlanner(),
  });

  /// Оценщик токенов (старый путь).
  final TokenEstimator estimator;

  /// Максимум карточек на фрагмент (старый путь).
  final int maxCardsPerChunk;

  /// Планировщик нового пути (в плане лимит карточек от бюджета вывода).
  final GenerationChunkPlanner planner;

  /// Строит план генерации по единицам содержимого (новый путь).
  GenerationPlan planChunks(
    ContentInventory inventory, {
    required ModelCapabilities capabilities,
    GenerationOverheadTokens overhead = GenerationOverheadTokens.none,
    int? requestedCards,
    GenerationBudgetConfig budgetConfig = const GenerationBudgetConfig(),
  }) {
    return planner.plan(
      inventory: inventory,
      capabilities: capabilities,
      overhead: overhead,
      requestedCards: requestedCards,
      budgetConfig: budgetConfig,
    );
  }

  /// Переводит фрагменты плана в старый тип [GenerationChunk].
  ///
  /// [GenerationChunk.documentImages] заполняется частями **и** строками
  /// каталога (чтобы сервис собрал `<images>` без потери `image_id`), а
  /// выбранные планом байты — в [GenerationChunk.imageParts]. Старый путь
  /// не меняется: у его фрагментов новые поля пусты.
  List<GenerationChunk> chunksFromPlan(GenerationPlan plan) {
    return <GenerationChunk>[
      for (final PlannedChunk chunk in plan.chunks)
        GenerationChunk(
          index: chunk.index,
          materialsText: chunk.materialsText,
          sourceFiles: _planSourceFiles(chunk),
          limit: chunk.limit,
          splitAttempted: chunk.splitDepth > 0,
          images: chunk.attachments,
          documentImages: List<DocumentImage>.unmodifiable(<DocumentImage>[
            ...chunk.imageParts,
            ...chunk.catalogOnly,
          ]),
          unitIds: List<String>.unmodifiable(<String>[
            for (final UnitSpan span in chunk.units) span.unitId,
          ]),
          splitDepth: chunk.splitDepth,
          imageParts: chunk.imageParts,
          catalogOnly: chunk.catalogOnly,
        ),
    ];
  }

  List<String> _planSourceFiles(PlannedChunk chunk) {
    final List<String> names = <String>[];
    void add(String name) {
      if (name.isEmpty || names.contains(name)) return;
      names.add(name);
    }

    for (final UnitSpan span in chunk.units) {
      final String id = span.unitId;
      if (!id.startsWith('doc:')) continue;
      final int hash = id.indexOf('#');
      if (hash <= 4) continue;
      add(id.substring(4, hash));
    }
    for (final DocumentImage image in chunk.imageParts) {
      add(image.fileName);
    }
    for (final DocumentImage image in chunk.catalogOnly) {
      add(image.fileName);
    }
    for (final GenerationAttachment attachment in chunk.attachments) {
      add(attachment.fileName);
    }
    return List<String>.unmodifiable(names);
  }

  /// Режет документы на фрагменты не больше [maxInputTokens] токенов.
  ///
  /// Границы разделов `ParsedDocument` сохраняются: раздел не смешивается с
  /// частью другого раздела, пока помещается целиком. Слишком большой раздел
  /// делится по абзацам, затем по строкам, затем жёстко по символам. Каждый
  /// файл в тексте начинается со строки `Файл: <имя>` (SPEC A8.1), изображения
  /// раздела попадают в каталог того фрагмента, где оказался раздел (Д3).
  List<GenerationChunk> chunkDocuments(
    List<ParsedDocument> documents, {
    required int maxInputTokens,
  }) {
    final int budget = maxInputTokens < 1 ? 1 : maxInputTokens;
    final List<_MaterialSegment> segments = <_MaterialSegment>[];
    final Map<String, List<DocumentImage>> imagesBySection =
        <String, List<DocumentImage>>{};
    for (final ParsedDocument document in documents) {
      final int headerTokens = estimator.estimate(
        '$kMaterialsFileHeaderPrefix${document.fileName}\n',
      );
      final int textBudget = budget - headerTokens > 0
          ? budget - headerTokens
          : 1;
      for (
        var sectionIndex = 0;
        sectionIndex < document.sections.length;
        sectionIndex++
      ) {
        final ParsedSection section = document.sections[sectionIndex];
        final String text = document.text
            .substring(section.start, section.end)
            .trim();
        final List<DocumentImage> sectionImages = document.images
            .where((DocumentImage image) => image.sectionIndex == sectionIndex)
            .toList(growable: false);
        if (sectionImages.isNotEmpty) {
          imagesBySection[_sectionKey(document.fileName, sectionIndex)] =
              sectionImages;
        }
        if (text.isEmpty) continue;
        final List<String> parts = _splitOversized(text, textBudget);
        for (var partIndex = 0; partIndex < parts.length; partIndex++) {
          segments.add(
            _MaterialSegment(
              text: parts[partIndex],
              fileName: document.fileName,
              sectionIndex: sectionIndex,
            ),
          );
        }
      }
    }
    if (segments.isEmpty) return const <GenerationChunk>[];

    // Жадно упаковываем сегменты: между разделами ровно пустая строка.
    final List<List<_MaterialSegment>> groups = <List<_MaterialSegment>>[];
    var current = <_MaterialSegment>[];
    for (final _MaterialSegment segment in segments) {
      if (current.isEmpty) {
        current.add(segment);
        continue;
      }
      final String candidate = _render(<_MaterialSegment>[...current, segment]);
      if (estimator.estimate(candidate) <= budget) {
        current.add(segment);
      } else {
        groups.add(current);
        current = <_MaterialSegment>[segment];
      }
    }
    if (current.isNotEmpty) groups.add(current);

    return <GenerationChunk>[
      for (var i = 0; i < groups.length; i++)
        GenerationChunk(
          index: i + 1,
          materialsText: _render(groups[i]),
          sourceFiles: _uniqueFiles(groups[i]),
          limit: maxCardsPerChunk,
          documentImages: _imagesOf(groups[i], imagesBySection),
        ),
    ];
  }

  /// Режет все материалы: текстовые документы, затем вложения.
  ///
  /// Изображение/PDF-скан — отдельный фрагмент: провайдер получает его как
  /// inline-часть и не смешивает с текстом другого файла (итерация 7.8).
  /// Вложения с одинаковым [GenerationAttachment.groupKey] (страницы одного
  /// PDF-скана) идут одним фрагментом — несколько image parts в одном запросе
  /// (итерация 7.9, ADR-023).
  ///
  /// [documentImages] — изображения, не привязанные к тексту документа
  /// (значимые области страниц скана, ADR-037): попадают во фрагмент того
  /// файла, страницы которого туда вошли.
  List<GenerationChunk> chunkAll(
    List<ParsedDocument> documents,
    List<GenerationAttachment> images, {
    required int maxInputTokens,
    List<DocumentImage> documentImages = const <DocumentImage>[],
  }) {
    final List<GenerationChunk> textChunks = chunkDocuments(
      documents,
      maxInputTokens: maxInputTokens,
    );
    final List<GenerationChunk> result = <GenerationChunk>[...textChunks];
    final Map<String, List<DocumentImage>> byFile =
        <String, List<DocumentImage>>{};
    for (final DocumentImage image in documentImages) {
      (byFile[image.fileName] ??= <DocumentImage>[]).add(image);
    }
    for (final List<GenerationAttachment> group in _attachmentGroups(images)) {
      final List<String> files = _uniqueAttachmentFiles(group);
      final List<DocumentImage> pageImages = <DocumentImage>[];
      for (final String file in files) {
        final List<DocumentImage>? found = byFile.remove(file);
        if (found != null) pageImages.addAll(found);
      }
      result.add(
        GenerationChunk(
          index: result.length + 1,
          materialsText: '',
          sourceFiles: files,
          limit: maxCardsPerChunk,
          images: List<GenerationAttachment>.unmodifiable(group),
          documentImages: List<DocumentImage>.unmodifiable(pageImages),
        ),
      );
    }
    // Изображения файлов без вложений (не должны теряться): отдельный
    // фрагмент-каталог без текста.
    byFile.forEach((String fileName, List<DocumentImage> fileImages) {
      result.add(
        GenerationChunk(
          index: result.length + 1,
          materialsText: '',
          sourceFiles: List<String>.unmodifiable(<String>[fileName]),
          limit: maxCardsPerChunk,
          documentImages: List<DocumentImage>.unmodifiable(fileImages),
        ),
      );
    });
    return result;
  }

  /// Изображения разделов, попавших во фрагмент, в порядке документа.
  List<DocumentImage> _imagesOf(
    List<_MaterialSegment> group,
    Map<String, List<DocumentImage>> imagesBySection,
  ) {
    final List<DocumentImage> result = <DocumentImage>[];
    final Set<String> seenSections = <String>{};
    for (final _MaterialSegment segment in group) {
      final String key = _sectionKey(segment.fileName, segment.sectionIndex);
      if (!seenSections.add(key)) continue;
      result.addAll(imagesBySection[key] ?? const <DocumentImage>[]);
    }
    return List<DocumentImage>.unmodifiable(result);
  }

  String _sectionKey(String fileName, int sectionIndex) =>
      '$fileName\u0000$sectionIndex';

  /// Группирует вложения: страницы одного PDF — вместе, остальные — по одной.
  List<List<GenerationAttachment>> _attachmentGroups(
    List<GenerationAttachment> images,
  ) {
    final List<List<GenerationAttachment>> groups =
        <List<GenerationAttachment>>[];
    final Map<String, List<GenerationAttachment>> byGroup =
        <String, List<GenerationAttachment>>{};
    for (final GenerationAttachment image in images) {
      final String? key = image.groupKey;
      if (key == null || key.isEmpty) {
        groups.add(<GenerationAttachment>[image]);
        continue;
      }
      final List<GenerationAttachment>? existing = byGroup[key];
      if (existing != null) {
        existing.add(image);
      } else {
        final List<GenerationAttachment> group = <GenerationAttachment>[image];
        byGroup[key] = group;
        groups.add(group);
      }
    }
    return groups;
  }

  /// Уникальные имена файлов группы вложений в порядке появления.
  List<String> _uniqueAttachmentFiles(List<GenerationAttachment> group) {
    final List<String> names = <String>[];
    for (final GenerationAttachment attachment in group) {
      if (!names.contains(attachment.fileName)) names.add(attachment.fileName);
    }
    return List<String>.unmodifiable(names);
  }

  /// Имена файлов группы без дублей, в порядке появления.
  List<String> _uniqueFiles(List<_MaterialSegment> group) {
    final List<String> names = <String>[];
    for (final _MaterialSegment segment in group) {
      if (!names.contains(segment.fileName)) names.add(segment.fileName);
    }
    return List<String>.unmodifiable(names);
  }

  /// Делит фрагмент пополам (для повторного `truncated`); `null` — нельзя.
  ///
  /// Точка деления выбирается у границы абзаца/строки ближе к середине;
  /// обе половины помечаются `splitAttempted`, чтобы пайплайн не дробил их
  /// повторно (A8.5 шаг 8). Фрагмент с вложениями или каталогом изображений
  /// файлов не дробится: изображения нельзя разделить по тексту.
  List<GenerationChunk>? splitInHalf(GenerationChunk chunk) {
    if (chunk.images.isNotEmpty || chunk.documentImages.isNotEmpty) return null;
    final String text = chunk.materialsText;
    final List<int> runes = text.runes.toList(growable: false);
    if (runes.length < 2) return null;
    final int middle = runes.length ~/ 2;
    final List<int> points = <int>[middle];
    for (var i = 1; i < runes.length - 1; i++) {
      if (runes[i] == 0x0A) {
        points.add(i);
        if (runes[i + 1] == 0x0A) points.add(i);
      }
    }
    points.sort();
    int splitAt = middle;
    for (final int point in points) {
      if (point <= 0 || point >= runes.length) continue;
      if ((point - middle).abs() < (splitAt - middle).abs()) splitAt = point;
    }
    final String left = String.fromCharCodes(runes.sublist(0, splitAt)).trim();
    final String right = String.fromCharCodes(runes.sublist(splitAt)).trim();
    if (left.isEmpty || right.isEmpty) return null;
    final int nextDepth = chunk.splitDepth + 1;
    return <GenerationChunk>[
      chunk.copyWith(
        index: chunk.index,
        materialsText: left,
        splitAttempted: true,
        documentImages: const <DocumentImage>[],
        unitIds: const <String>[],
        imageParts: const <DocumentImage>[],
        catalogOnly: const <DocumentImage>[],
        splitDepth: nextDepth,
      ),
      chunk.copyWith(
        index: chunk.index + 1,
        materialsText: right,
        splitAttempted: true,
        documentImages: const <DocumentImage>[],
        unitIds: const <String>[],
        imageParts: const <DocumentImage>[],
        catalogOnly: const <DocumentImage>[],
        splitDepth: nextDepth,
      ),
    ];
  }

  /// Текст группы сегментов: файлы начинаются со строки «Файл: <имя>».
  String _render(List<_MaterialSegment> group) {
    final StringBuffer buffer = StringBuffer();
    String? currentFile;
    for (final _MaterialSegment segment in group) {
      if (buffer.isNotEmpty) buffer.write('\n\n');
      if (segment.fileName != currentFile) {
        buffer
          ..write(kMaterialsFileHeaderPrefix)
          ..write(segment.fileName)
          ..write('\n');
        currentFile = segment.fileName;
      }
      buffer.write(segment.text);
    }
    return buffer.toString();
  }

  /// Режет слишком большой раздел до бюджета, не теряя текст.
  List<String> _splitOversized(String text, int budget) {
    if (estimator.estimate(text) <= budget) return <String>[text];

    final List<String> paragraphs = text
        .split(RegExp(r'\n\s*\n'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
    if (paragraphs.length > 1) {
      return _splitPieces(paragraphs, budget, separator: '\n\n');
    }

    final List<String> lines = text
        .split('\n')
        .map((part) => part.trimRight())
        .where((part) => part.isNotEmpty)
        .toList();
    if (lines.length > 1) {
      return _splitPieces(lines, budget, separator: '\n');
    }

    return _hardSplit(text, budget);
  }

  /// Упаковывает абзацы/строки в группы до бюджета; oversized-часть режется.
  List<String> _splitPieces(
    List<String> pieces,
    int budget, {
    required String separator,
  }) {
    final List<String> result = <String>[];
    var current = <String>[];
    void flush() {
      if (current.isEmpty) return;
      result.add(current.join(separator));
      current = <String>[];
    }

    for (final String piece in pieces) {
      final List<String> parts = estimator.estimate(piece) <= budget
          ? <String>[piece]
          : _hardSplit(piece, budget);
      for (final String part in parts) {
        if (current.isEmpty) {
          current.add(part);
        } else if (estimator.estimate(
              <String>[...current, part].join(separator),
            ) <=
            budget) {
          current.add(part);
        } else {
          flush();
          current.add(part);
        }
      }
    }
    flush();
    return result;
  }

  /// Жёсткое деление по символам с запасом 20 % от бюджета.
  List<String> _hardSplit(String text, int budget) {
    final int targetChars = (budget * estimator.charsPerToken * 0.8).floor();
    final int size = targetChars < 1 ? 1 : targetChars;
    final List<int> runes = text.runes.toList(growable: false);
    final List<String> result = <String>[];
    var start = 0;
    while (start < runes.length) {
      final int end = (start + size) < runes.length
          ? start + size
          : runes.length;
      result.add(String.fromCharCodes(runes.sublist(start, end)));
      start = end;
    }
    return result;
  }
}

/// Кусок материала с именем файла-источника и номером раздела.
class _MaterialSegment {
  const _MaterialSegment({
    required this.text,
    required this.fileName,
    required this.sectionIndex,
  });

  final String text;
  final String fileName;
  final int sectionIndex;
}
