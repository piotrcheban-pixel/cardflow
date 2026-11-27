/// Адаптер `ParsedDocument → ContentModel` (этап Ingestion, ADR-050).
///
/// Парсеры не переписываются (TASK «Срез 1»): модель строится по уже
/// нормализованному тексту и границам разделов `ParsedDocument`. Адаптер
/// отвечает за три решения:
/// 1. **Блок = строка.** Парсеры отдают абзац/пункт/пункт списка отдельной
///    строкой (`ParsedDocumentBuilder.addLine`), поэтому блочная нарезка
///    следует за строками источника и не выдумывает границы: строку нельзя
///    разрезать, а перенос строки в PDF — тоже строка (склейка в абзацы —
///    задача следующих этапов, а не Ingestion).
/// 2. **Мусор — флагом.** Колонтитулы, номера страниц, оглавление и подписи
///    рисунков не удаляются из текста (иначе сдвинутся offsets), а помечаются
///    `Block.isNoise`/`noiseKind`.
/// 3. **Раздел не рвёт абзац.** Блок целиком принадлежит разделу, где он
///    начинается; границы разделов модели расширяются до границ блоков,
///    поэтому ни один блок не пересекает границу раздела.
library;

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_normalizer.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Максимальная длина строки, которую считаем колонтитулом.
///
/// Бегущий заголовок/подвал — короткая служебная строка; длинный повтор
/// (например, повторяющийся абзац) мусором не объявляется.
const int _maxRunningHeaderLength = 80;

/// Страница/лист целиком: `12`, ` 12 `, `- 12 -`, `Стр. 12 из 40`.
final RegExp _pageNumber = RegExp(
  r'^(?:'
  r'(?:стр\.?|страница|с\.|page|p\.)\s*\d{1,4}'
  r'(?:\s*(?:из|of|/)\s*\d{1,4})?'
  r'|\d{1,4}\s*(?:из|of|/)\s*\d{1,4}'
  r'|[-–—\s]*\d{1,4}[-–—\s]*'
  r')$',
  caseSensitive: false,
);

/// Подпись рисунка: «Рис. 4», «Рисунок 2.1», «Fig. 3», «Figure 12».
///
/// `\b` здесь не используется: в ECMAScript-регулярках граница слова считается
/// по ASCII, поэтому после кириллического «Рис» её нет.
final RegExp _figureCaption = RegExp(
  r'^(?:рис(?:унок)?|fig(?:ure)?)\.?\s*\d+',
  caseSensitive: false,
);

/// Запись оглавления: отточие и номер страницы в конце строки.
final RegExp _tableOfContentsEntry = RegExp(
  r'\S.*(?:\.{3,}|…{2,})[\s.]*\d{1,4}\s*$',
);

/// Заголовки разделов, содержимое которых целиком считается оглавлением.
final RegExp _nonWord = RegExp(r'[^а-яa-z]');

/// Отсев мусора в тексте документа: колонтитулы, номера страниц, оглавление,
/// подписи рисунков.
///
/// Решения детерминированные и объяснимые, без модели и сети:
/// * номер страницы — строка состоит только из номера («12», «Стр. 12 из 40»);
/// * подпись рисунка — начинается с «Рис.»/«Fig.» и номера;
/// * оглавление — запись с отточием и номером страницы либо любой текст
///   раздела с заголовком «Оглавление»/«Содержание»/«Contents»;
/// * колонтитул — короткая строка, повторяющаяся в ≥ 2 разделах и стоящая
///   первой или последней строкой раздела (бегущий заголовок/подвал).
///
/// Правила намеренно консервативные: сомнительная строка остаётся
/// содержательной (лучше лишний материал, чем потеря смысла).
class ContentNoiseDetector {
  /// Создаёт детектор (без состояния).
  const ContentNoiseDetector();

  /// Классифицирует строку [line]; `null` — строка содержательная.
  ///
  /// [repeatedInSections] — в скольких разделах та же нормализованная строка
  /// стоит первой или последней (считает адаптер); [sectionTitle] — заголовок
  /// раздела, в котором находится строка.
  NoiseKind? detect(
    String line, {
    int repeatedInSections = 1,
    String? sectionTitle,
  }) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty) return null;
    if (_isTableOfContentsTitle(sectionTitle)) {
      return NoiseKind.tableOfContents;
    }
    if (_pageNumber.hasMatch(trimmed)) return NoiseKind.pageNumber;
    if (_figureCaption.hasMatch(trimmed)) return NoiseKind.figureCaption;
    if (_tableOfContentsEntry.hasMatch(trimmed)) {
      return NoiseKind.tableOfContents;
    }
    if (repeatedInSections >= 2 && trimmed.length <= _maxRunningHeaderLength) {
      return NoiseKind.runningHeaderFooter;
    }
    return null;
  }

  /// true, если заголовок раздела означает оглавление.
  static bool _isTableOfContentsTitle(String? title) {
    if (title == null || title.trim().isEmpty) return false;
    final String normalized = title.toLowerCase().replaceAll(_nonWord, '');
    return normalized == 'оглавление' ||
        normalized == 'содержание' ||
        normalized == 'contents' ||
        normalized == 'tableofcontents';
  }
}

/// Адаптер `ParsedDocument → ContentModel`.
class ContentModelBuilder {
  /// Создаёт адаптер.
  const ContentModelBuilder({
    this.normalizer = const ContentNormalizer(),
    this.noiseDetector = const ContentNoiseDetector(),
  });

  /// Нормализатор строк (для сравнения повторов, а не для текста блоков).
  final ContentNormalizer normalizer;

  /// Детектор мусора.
  final ContentNoiseDetector noiseDetector;

  /// Строит модель по разобранному документу.
  ///
  /// Порядок: строки текста → пометка мусора (нужны повторы по разделам) →
  /// блоки с якорями → разделы с иерархией. Ошибок пользователя здесь нет:
  /// `ParsedDocument` уже валиден, поэтому единственные исключения —
  /// `ArgumentError` инвариантов [Document].
  Document build(ParsedDocument document) {
    final String text = document.text;
    final String documentId = contentDocumentId(document.fileName);
    final List<_SourceLine> lines = _splitLines(text);
    final Map<String, Set<int>> repeatedLines = _repeatedEdgeLines(
      document,
      lines,
    );
    final List<Block> blocks = <Block>[];
    final Map<int, List<Block>> blocksBySection = <int, List<Block>>{};
    final Map<int, int> blockCounters = <int, int>{};
    for (final _SourceLine line in lines) {
      if (line.isBlank) continue;
      final int sectionIndex = _sectionIndexOf(document.sections, line.start);
      final int ordinal = blockCounters[sectionIndex] ?? 0;
      blockCounters[sectionIndex] = ordinal + 1;
      final String sectionId = contentSectionId(documentId, sectionIndex);
      final Block block = Block(
        id: contentTextPieceId(sectionId, ordinal),
        sectionId: sectionId,
        start: line.start,
        end: line.end,
        text: line.text,
        noiseKind: noiseDetector.detect(
          line.text,
          repeatedInSections:
              repeatedLines[normalizer.normalize(line.text.trim())]?.length ??
              1,
          sectionTitle: document.sections[sectionIndex].title,
        ),
      );
      blocks.add(block);
      (blocksBySection[sectionIndex] ??= <Block>[]).add(block);
    }
    return Document(
      fileName: document.fileName,
      format: document.format,
      text: text,
      blocks: blocks,
      sections: _buildSections(document, documentId, blocksBySection),
    );
  }

  /// Строит модель по результату парсинга: ошибка файла — пустая модель.
  ///
  /// Скан без текстового слоя (`ParserErrorCode.scannedPdf`), нечитаемый и
  /// неподдерживаемый файл не должны бросать исключение на этапе Ingestion:
  /// материала просто нет, остальные файлы набора обрабатываются дальше.
  Document buildFromOutcome(ParsingOutcome outcome) => switch (outcome) {
    ParsedFileSuccess(document: final ParsedDocument document) => build(
      document,
    ),
    ParsedFileFailure(fileName: final String fileName) => Document.empty(
      fileName: fileName,
      format: documentFormatFromFileName(fileName),
    ),
  };

  /// Разделы модели: пустые разделы парсера отсеяны, границы — по блокам,
  /// иерархия — по нумерации заголовков.
  List<Section> _buildSections(
    ParsedDocument document,
    String documentId,
    Map<int, List<Block>> blocksBySection,
  ) {
    final List<int> kept = <int>[
      for (var index = 0; index < document.sections.length; index++)
        if ((blocksBySection[index] ?? const <Block>[]).isNotEmpty) index,
    ];
    final List<int> depths = <int>[];
    final List<String?> parentIds = <String?>[];
    // Стек позиций в [kept]: родитель — ближайший предыдущий раздел с меньшей
    // глубиной.
    final List<int> stack = <int>[];
    for (var position = 0; position < kept.length; position++) {
      var depth = _titleDepth(document.sections[kept[position]].title);
      while (stack.isNotEmpty && depths[stack.last] >= depth) {
        stack.removeLast();
      }
      if (stack.isEmpty) {
        // Нумерация с разрывом («1.2» без «1») — раздел считается корневым.
        depth = 0;
      } else if (depth > depths[stack.last] + 1) {
        // Пропущенный уровень («1.1.1» без «1.1»): глубина не прыгает через
        // уровень, иначе иерархия перестаёт быть деревом.
        depth = depths[stack.last] + 1;
      }
      depths.add(depth);
      parentIds.add(
        stack.isEmpty ? null : contentSectionId(documentId, kept[stack.last]),
      );
      stack.add(position);
    }
    final Map<String, List<String>> children = <String, List<String>>{};
    for (var position = 0; position < kept.length; position++) {
      final String? parentId = parentIds[position];
      if (parentId == null) continue;
      (children[parentId] ??= <String>[]).add(
        contentSectionId(documentId, kept[position]),
      );
    }
    return <Section>[
      for (var position = 0; position < kept.length; position++)
        _sectionOf(
          document: document,
          documentId: documentId,
          parserIndex: kept[position],
          blocks: blocksBySection[kept[position]]!,
          depth: depths[position],
          parentId: parentIds[position],
          childIds:
              children[contentSectionId(documentId, kept[position])] ??
              const <String>[],
        ),
    ];
  }

  Section _sectionOf({
    required ParsedDocument document,
    required String documentId,
    required int parserIndex,
    required List<Block> blocks,
    required int depth,
    required String? parentId,
    required List<String> childIds,
  }) {
    final String id = contentSectionId(documentId, parserIndex);
    return Section(
      id: id,
      index: parserIndex,
      start: blocks.first.start,
      end: blocks.last.end,
      title: document.sections[parserIndex].title,
      parentId: parentId,
      depth: depth,
      blockIds: <String>[for (final Block block in blocks) block.id],
      childIds: childIds,
    );
  }

  /// Строки, которые стоят первой или последней в разделе, и число разделов,
  /// где такая строка повторяется (ключ — нормализованный текст).
  Map<String, Set<int>> _repeatedEdgeLines(
    ParsedDocument document,
    List<_SourceLine> lines,
  ) {
    final int sectionCount = document.sections.length;
    final List<_SourceLine?> first = List<_SourceLine?>.filled(
      sectionCount,
      null,
    );
    final List<_SourceLine?> last = List<_SourceLine?>.filled(
      sectionCount,
      null,
    );
    for (final _SourceLine line in lines) {
      if (line.isBlank) continue;
      final int index = _sectionIndexOf(document.sections, line.start);
      first[index] ??= line;
      last[index] = line;
    }
    final Map<String, Set<int>> repeated = <String, Set<int>>{};
    for (var index = 0; index < sectionCount; index++) {
      for (final _SourceLine? line in <_SourceLine?>[
        first[index],
        last[index],
      ]) {
        if (line == null) continue;
        final String key = normalizer.normalize(line.text.trim());
        if (key.isEmpty) continue;
        (repeated[key] ??= <int>{}).add(index);
      }
    }
    return repeated;
  }

  /// Индекс раздела парсера, в котором начинается [offset] (двоичный поиск).
  ///
  /// Разделы упорядочены и не пересекаются; блок всегда принадлежит разделу,
  /// в котором он **начинается**, поэтому граница раздела никогда не режет
  /// строку.
  int _sectionIndexOf(List<ParsedSection> sections, int offset) {
    var low = 0;
    var high = sections.length - 1;
    var index = 0;
    while (low <= high) {
      final int middle = (low + high) ~/ 2;
      if (sections[middle].start <= offset) {
        index = middle;
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    return index;
  }

  /// Глубина раздела по нумерации заголовка: «1.» → 0, «1.1.» → 1, «1.1.2.» → 2.
  int _titleDepth(String? title) {
    if (title == null) return 0;
    final Match? match = _numberedTitle.firstMatch(title);
    if (match == null) return 0;
    return match.group(1)!.split('.').length - 1;
  }

  /// Делит текст на строки, сохраняя смещения (перевод строки в блок не входит).
  List<_SourceLine> _splitLines(String text) {
    final List<_SourceLine> lines = <_SourceLine>[];
    var start = 0;
    while (start <= text.length) {
      final int newline = text.indexOf('\n', start);
      final int end = newline < 0 ? text.length : newline;
      lines.add(
        _SourceLine(start: start, end: end, text: text.substring(start, end)),
      );
      if (newline < 0) break;
      start = newline + 1;
    }
    return lines;
  }
}

/// Номерная часть заголовка раздела: «1.», «1.2», «3.4.5.»
final RegExp _numberedTitle = RegExp(r'^\s*(\d+(?:\.\d+)*)\.?(?:\s|$)');

/// Строка источника со смещениями в тексте документа.
class _SourceLine {
  const _SourceLine({
    required this.start,
    required this.end,
    required this.text,
  });

  final int start;
  final int end;
  final String text;

  bool get isBlank => text.trim().isEmpty;
}
