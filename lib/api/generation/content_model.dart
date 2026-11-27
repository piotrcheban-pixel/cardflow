/// Модель содержимого документа для генерации v3 — этап Ingestion (ADR-050).
///
/// Текст перестаёт быть строкой: `Document → Section → Block`, где каждый
/// [Block] — строка источника с точными смещениями `start`/`end` в тексте
/// документа, стабильным [Block.id] и флагом [Block.isNoise]. Смещения — якоря:
/// текст блока восстанавливается как `document.text.substring(start, end)` и не
/// ищется подстрокой; [Document.block] даёт блок по id за O(1) (индексная
/// карта), а [Document.blockAt] — блок по смещению за O(log n).
///
/// Модель строится адаптером `ContentModelBuilder` поверх существующего
/// [ParsedDocument]: парсеры не переписываются (TASK «Срез 1»).
///
/// Инварианты (проверяются в конструкторе [Document], нарушение —
/// [ArgumentError], то есть ошибка программиста, а не пользователя):
/// 1. Блоки идут по возрастанию `start` и не пересекаются.
/// 2. `text.substring(block.start, block.end) == block.text` — offsets точные.
/// 3. Каждый блок лежит ровно в одном разделе; разделы идут по порядку и не
///    пересекаются, границы разделов не режут блок (раздел не рвёт абзац).
/// 4. Иерархия разделов замкнута: `parentId`/`childIds`/`depth` согласованы;
///    раздел без родителя имеет `depth == 0`.
///
/// Мусор (колонтитулы, номера страниц, оглавление, подписи «Рис. N») не
/// удаляется: блок остаётся в модели с `isNoise == true`, чтобы offsets не
/// пересчитывались, а потребители (карта знаний, цитаты) могли отфильтровать
/// его и знали причину.
library;

import 'package:cardflow/api/generation/content_normalizer.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/text/document_format.dart';

/// Причина, по которой строка документа признана мусором.
///
/// Отсев выполняется флагом [Block.isNoise], текст остаётся в [Document.text]
/// и в модели — поэтому смещения блоков не сдвигаются.
enum NoiseKind {
  /// Колонтитул: строка повторяется в нескольких разделах и стоит первой или
  /// последней строкой раздела (бегущий заголовок/подвал).
  runningHeaderFooter,

  /// Номер страницы: строка состоит только из номера (возможно, «Стр. 3 из 10»).
  pageNumber,

  /// Строка оглавления: раздел «Оглавление»/«Содержание» или запись с точками
  /// и номером страницы.
  tableOfContents,

  /// Подпись рисунка: «Рис. 4», «Fig. 3» (ADR-050: подписи — служебный текст).
  figureCaption,
}

/// Строка документа (блок) с якорем в тексте.
///
/// [text] — ровно `document.text.substring(start, end)`: отступы и переводы
/// строк внутри блока сохраняются как в источнике. [normalizedText] — форма
/// для сравнения (пробелы/ё/кавычки/дефисы), смещения она не меняет.
class Block {
  /// Создаёт блок; инварианты диапазона — `assert` на этапе разработки.
  const Block({
    required this.id,
    required this.sectionId,
    required this.start,
    required this.end,
    required this.text,
    this.noiseKind,
  }) : assert(id != '', 'У блока обязан быть id'),
       assert(sectionId != '', 'У блока обязан быть раздел'),
       assert(start >= 0, 'Начало блока не может быть отрицательным'),
       assert(end >= start, 'Конец блока не раньше начала'),
       assert(
         text.length == end - start,
         'Длина текста блока должна совпадать с диапазоном start/end',
       );

  /// Стабильный id (`doc:<файл>#<раздел>#<номер блока в разделе>`).
  final String id;

  /// id раздела, которому принадлежит блок целиком.
  final String sectionId;

  /// Смещение начала блока в тексте документа (включительно).
  final int start;

  /// Смещение конца блока в тексте документа (исключительно).
  final int end;

  /// Текст блока — ровно `text.substring(start, end)` текста документа.
  final String text;

  /// Причина отсева; `null` — блок содержательный.
  final NoiseKind? noiseKind;

  /// true, если блок — мусор (колонтитул, номер страницы, оглавление, подпись).
  bool get isNoise => noiseKind != null;

  /// Длина блока в UTF-16 code units (`String.length`).
  int get length => end - start;

  /// Текст в нормализованной форме (для сравнения), якорь не затрагивает.
  String get normalizedText => const ContentNormalizer().normalize(text);

  @override
  String toString() =>
      'Block($id, $start..$end'
      '${noiseKind == null ? '' : ', ${noiseKind!.name}'})';
}

/// Раздел документа: диапазон текста, список блоков и место в иерархии.
class Section {
  /// Создаёт раздел; [index] — номер раздела в [ParsedDocument.sections].
  ///
  /// Списки становятся неизменяемыми. [start]/[end] — границы **модели**:
  /// они расширены до границ блоков, поэтому не режут абзац (могут отличаться
  /// от границ парсера).
  Section({
    required this.id,
    required this.index,
    required this.start,
    required this.end,
    this.title,
    this.parentId,
    this.depth = 0,
    List<String> blockIds = const <String>[],
    List<String> childIds = const <String>[],
  }) : assert(id != '', 'У раздела обязан быть id'),
       assert(index >= 0, 'Индекс раздела не может быть отрицательным'),
       assert(start >= 0, 'Начало раздела не может быть отрицательным'),
       assert(end >= start, 'Конец раздела не раньше начала'),
       assert(depth >= 0, 'Глубина раздела не может быть отрицательной'),
       assert(
         parentId != null || depth == 0,
         'Раздел без родителя обязан быть корневым (depth == 0)',
       ),
       blockIds = List<String>.unmodifiable(blockIds),
       childIds = List<String>.unmodifiable(childIds);

  /// Стабильный id (`doc:<файл>#<индекс>`), совпадает с id единиц парсера.
  final String id;

  /// Номер раздела в исходном [ParsedDocument] (id стабилен даже при отсеве).
  final int index;

  /// Смещение начала раздела в тексте документа (включительно).
  final int start;

  /// Смещение конца раздела в тексте документа (исключительно).
  final int end;

  /// Заголовок раздела из документа, если он выводится парсером.
  final String? title;

  /// id родительского раздела; `null` — корневой раздел.
  final String? parentId;

  /// Глубина в иерархии: 0 — корень, 1 — подраздел и т. д.
  final int depth;

  /// Блоки раздела в порядке следования (включая мусорные).
  final List<String> blockIds;

  /// id непосредственных подразделов в порядке следования.
  final List<String> childIds;

  @override
  String toString() =>
      'Section($id, $start..$end, depth: $depth'
      '${title == null ? '' : ', «$title»'}, blocks: ${blockIds.length})';
}

/// Документ: текст, блоки с якорями и разделы с иерархией.
class Document {
  /// Создаёт модель и проверяет инварианты (см. документацию библиотеки).
  ///
  /// [format] — формат источника; `null` только у пустой модели (файл не
  /// разобран парсером, например скан без текстового слоя).
  Document({
    required this.fileName,
    this.format,
    required this.text,
    List<Block> blocks = const <Block>[],
    List<Section> sections = const <Section>[],
  }) : id = contentDocumentId(fileName),
       blocks = List<Block>.unmodifiable(blocks),
       sections = List<Section>.unmodifiable(sections),
       _blocksById = _indexBlocks(blocks),
       _sectionsById = _indexSections(sections),
       _blocksBySection = _groupBlocks(blocks) {
    _validate();
  }

  /// Пустая модель документа (нет текста, блоков и разделов).
  ///
  /// Используется, когда файл не дал текста: скан PDF без текстового слоя
  /// (`ParserErrorCode.scannedPdf`), нечитаемый файл, пустой документ. Это не
  /// ошибка модели: этап Ingestion просто не получает материала.
  factory Document.empty({required String fileName, DocumentFormat? format}) =>
      Document(fileName: fileName, format: format, text: '');

  /// Стабильный id документа (`doc:<имя файла>`).
  final String id;

  /// Имя исходного файла.
  final String fileName;

  /// Формат источника; `null` — документ не разобран.
  final DocumentFormat? format;

  /// Нормализованный текст документа (единственный источник истины).
  final String text;

  /// Блоки в порядке следования; включают мусорные (флаг [Block.isNoise]).
  final List<Block> blocks;

  /// Разделы в порядке следования; пустые разделы парсера отсеяны.
  final List<Section> sections;

  final Map<String, Block> _blocksById;
  final Map<String, Section> _sectionsById;
  final Map<String, List<Block>> _blocksBySection;

  /// Блок по id за O(1); `null` — такого блока нет.
  Block? block(String id) => _blocksById[id];

  /// Раздел по id за O(1); `null` — такого раздела нет.
  Section? section(String id) => _sectionsById[id];

  /// Блоки раздела в порядке следования (пустой список, если раздела нет).
  List<Block> blocksOfSection(String sectionId) =>
      _blocksBySection[sectionId] ?? const <Block>[];

  /// Непосредственные подразделы раздела в порядке следования.
  List<Section> childrenOf(String sectionId) => <Section>[
    for (final String childId
        in _sectionsById[sectionId]?.childIds ?? const <String>[])
      _sectionsById[childId]!,
  ];

  /// Содержательные блоки (без мусора) в порядке следования.
  Iterable<Block> get contentBlocks =>
      blocks.where((Block block) => !block.isNoise);

  /// Мусорные блоки в порядке следования.
  Iterable<Block> get noiseBlocks =>
      blocks.where((Block block) => block.isNoise);

  /// Блок, содержащий [offset], за O(log n); `null` — смещение в промежутке
  /// между блоками (пустая строка) или вне текста.
  Block? blockAt(int offset) {
    if (offset < 0 || offset >= text.length) return null;
    var low = 0;
    var high = blocks.length - 1;
    while (low <= high) {
      final int middle = (low + high) ~/ 2;
      final Block block = blocks[middle];
      if (offset < block.start) {
        high = middle - 1;
      } else if (offset >= block.end) {
        low = middle + 1;
      } else {
        return block;
      }
    }
    return null;
  }

  /// true, если текста нет: ни блоков, ни разделов.
  bool get isEmpty => blocks.isEmpty && sections.isEmpty;

  /// Сколько символов текста вошло в содержательные блоки.
  int get contentLength =>
      contentBlocks.fold(0, (int sum, Block block) => sum + block.length);

  void _validate() {
    if (text.isEmpty) {
      if (blocks.isNotEmpty || sections.isNotEmpty) {
        throw ArgumentError(
          'У пустого документа не может быть блоков/разделов',
        );
      }
      return;
    }
    if (_blocksById.length != blocks.length) {
      throw ArgumentError('id блоков должны быть уникальными');
    }
    if (_sectionsById.length != sections.length) {
      throw ArgumentError('id разделов должны быть уникальными');
    }
    var previousEnd = 0;
    for (final Block block in blocks) {
      if (block.start < previousEnd) {
        throw ArgumentError(
          'Блоки должны идти по порядку и не пересекаться: '
          '${block.id} начинается в ${block.start} после $previousEnd',
        );
      }
      if (block.end > text.length) {
        throw ArgumentError(
          'Границы блока ${block.start}..${block.end} выходят за текст '
          'длиной ${text.length}',
        );
      }
      if (text.substring(block.start, block.end) != block.text) {
        throw ArgumentError(
          'Текст блока ${block.id} не совпадает с текстом документа '
          'в ${block.start}..${block.end}',
        );
      }
      previousEnd = block.end;
    }
    var previousSectionEnd = 0;
    for (final Section section in sections) {
      if (section.end > text.length) {
        throw ArgumentError(
          'Границы раздела ${section.start}..${section.end} выходят за текст '
          'длиной ${text.length}',
        );
      }
      if (section.start < previousSectionEnd) {
        throw ArgumentError(
          'Разделы должны идти по порядку и не пересекаться: '
          '${section.id} начинается в ${section.start} после '
          '$previousSectionEnd',
        );
      }
      previousSectionEnd = section.end;
      final String? parentId = section.parentId;
      if (parentId != null && !_sectionsById.containsKey(parentId)) {
        throw ArgumentError(
          'Родительский раздел $parentId для ${section.id} не существует',
        );
      }
      for (final String childId in section.childIds) {
        if (_sectionsById[childId]?.parentId != section.id) {
          throw ArgumentError(
            'Подраздел $childId не указывает на ${section.id} как на родителя',
          );
        }
      }
      for (final String blockId in section.blockIds) {
        final Block? block = _blocksById[blockId];
        if (block == null) {
          throw ArgumentError('Блок $blockId раздела ${section.id} не найден');
        }
        if (block.sectionId != section.id) {
          throw ArgumentError(
            'Блок $blockId принадлежит ${block.sectionId}, а не ${section.id}',
          );
        }
        if (block.start < section.start || block.end > section.end) {
          throw ArgumentError(
            'Блок $blockId (${block.start}..${block.end}) выходит за границы '
            'раздела ${section.start}..${section.end}',
          );
        }
      }
    }
    for (final Block block in blocks) {
      if (!_sectionsById.containsKey(block.sectionId)) {
        throw ArgumentError(
          'Раздел ${block.sectionId} блока ${block.id} не существует',
        );
      }
    }
    for (final Section section in sections) {
      final Set<String> declaredIds = section.blockIds.toSet();
      if (declaredIds.length != section.blockIds.length) {
        throw ArgumentError('Блоки раздела ${section.id} указаны дважды');
      }
      for (final Block block
          in _blocksBySection[section.id] ?? const <Block>[]) {
        if (!declaredIds.contains(block.id)) {
          throw ArgumentError(
            'Блок ${block.id} принадлежит ${section.id}, но не указан в '
            'blockIds раздела',
          );
        }
      }
    }
  }

  static Map<String, Block> _indexBlocks(List<Block> blocks) {
    final Map<String, Block> index = <String, Block>{};
    for (final Block block in blocks) {
      index[block.id] = block;
    }
    return Map<String, Block>.unmodifiable(index);
  }

  static Map<String, Section> _indexSections(List<Section> sections) {
    final Map<String, Section> index = <String, Section>{};
    for (final Section section in sections) {
      index[section.id] = section;
    }
    return Map<String, Section>.unmodifiable(index);
  }

  static Map<String, List<Block>> _groupBlocks(List<Block> blocks) {
    final Map<String, List<Block>> grouped = <String, List<Block>>{};
    for (final Block block in blocks) {
      (grouped[block.sectionId] ??= <Block>[]).add(block);
    }
    return Map<String, List<Block>>.unmodifiable(<String, List<Block>>{
      for (final MapEntry<String, List<Block>> entry in grouped.entries)
        entry.key: List<Block>.unmodifiable(entry.value),
    });
  }
}
