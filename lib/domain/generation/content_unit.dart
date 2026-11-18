/// Единицы содержимого генерации (раздел E.1 аудита TASK 01).
///
/// Представление «документ → раздел → фрагмент текста/изображение» строится
/// поверх уже существующих доменных сущностей ([ParsedDocument],
/// [DocumentImage], [GenerationAttachment]) и не меняет их. Каждая единица
/// имеет стабильный id (`doc:<файл>#<раздел>#<фрагмент>`, `img:<файл>#<n>`):
/// план и причины сбоев ссылаются на ids, а не пересобирают текст заново.
///
/// Токены единиц вычисляет оценщик и передаёт готовыми значениями: здесь нет
/// второй реализации оценки (правило «одна логика — одна реализация»).
/// Домен не зависит от Flutter.
library;

import 'dart:typed_data';

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/text/document_format.dart';

/// Идентификатор документа: `doc:<имя файла>`.
String contentDocumentId(String fileName) => 'doc:$fileName';

/// Идентификатор раздела: `doc:<файл>#<индекс раздела>`.
String contentSectionId(String documentId, int sectionIndex) =>
    '$documentId#$sectionIndex';

/// Идентификатор фрагмента текста: `doc:<файл>#<раздел>#<порядковый номер>`.
String contentTextPieceId(String sectionId, int pieceIndex) =>
    '$sectionId#$pieceIndex';

/// Идентификатор изображения: `img:<файл>#<порядковый номер>`.
String contentImageId(String fileName, int imageIndex) =>
    'img:$fileName#$imageIndex';

/// Идентификатор вложения: `att:<имя файла или ключ группы>`.
String contentAttachmentId(String fileName, {String? groupKey}) {
  final String key = groupKey == null || groupKey.isEmpty ? fileName : groupKey;
  return 'att:$key';
}

/// Идентификатор страницы вложения.
///
/// У PDF-скана номер страницы известен — `att:<ключ>#p<N>`; у одиночного
/// изображения номера нет, и страница совпадает с вложением.
String contentPageId(String attachmentId, int? pageNumber) =>
    pageNumber == null ? attachmentId : '$attachmentId#p$pageNumber';

/// Диапазон страниц раздела (включительно), например PDF/PPTX.
class PageRange {
  /// Создаёт диапазон (страницы с 1, начало не позже конца).
  const PageRange({required this.firstPage, required this.lastPage})
    : assert(firstPage >= 1, 'Страницы нумеруются с 1'),
      assert(lastPage >= firstPage, 'Конец диапазона не раньше начала');

  /// Первая страница диапазона.
  final int firstPage;

  /// Последняя страница диапазона.
  final int lastPage;

  /// Сколько страниц в диапазоне.
  int get length => lastPage - firstPage + 1;

  @override
  String toString() => 'PageRange($firstPage..$lastPage)';
}

/// Вид границы, по которой выделен [TextPiece] (D.4/D.6).
enum TextPieceKind {
  /// Абзац.
  paragraph,

  /// Предложение.
  sentence,

  /// Строка.
  line,
}

/// Фрагмент текста с границами в исходном тексте документа.
class TextPiece {
  /// Создаёт фрагмент; [start]/[end] — смещения в тексте документа.
  const TextPiece({
    required this.id,
    required this.kind,
    required this.order,
    required this.text,
    required this.start,
    required this.end,
    required this.tokens,
  }) : assert(id != '', 'У единицы обязан быть id'),
       assert(order >= 0),
       assert(start >= 0),
       assert(end >= start),
       assert(tokens >= 0, 'Токены не могут быть отрицательными');

  /// Стабильный id (`doc:<файл>#<раздел>#<номер>`).
  final String id;

  /// Граница, по которой выделен фрагмент.
  final TextPieceKind kind;

  /// Порядковый номер внутри раздела (0 — первый).
  final int order;

  /// Текст фрагмента.
  final String text;

  /// Смещение начала в тексте документа (включительно).
  final int start;

  /// Смещение конца в тексте документа (исключительно).
  final int end;

  /// Оценка токенов фрагмента.
  final int tokens;

  /// Длина фрагмента в UTF-16 code units (`String.length`).
  int get length => end - start;

  @override
  String toString() =>
      'TextPiece($id, ${kind.name}, $tokens ток., '
      '$start..$end)';
}

/// Ссылка на изображение документа с привязкой к разделу.
///
/// Обёртка над [DocumentImage] (байты, страница, `rect`, подпись, контекст),
/// не изменяющая саму доменную сущность. [sectionId] == `null` — изображение
/// без текстовой секции (orphan): оно не теряется, а становится отдельной
/// единицей [OrphanImageUnit].
class ImageRef {
  /// Создаёт ссылку на изображение.
  const ImageRef({
    required this.id,
    required this.image,
    required this.tokens,
    this.sectionId,
  }) : assert(id != '', 'У единицы обязан быть id'),
       assert(tokens >= 0, 'Токены не могут быть отрицательными');

  /// Стабильный id (`img:<файл>#<номер>`).
  final String id;

  /// Исходное изображение (байты и метаданные).
  final DocumentImage image;

  /// Оценка токенов изображения.
  final int tokens;

  /// id раздела, где изображение упомянуто; `null` — orphan.
  final String? sectionId;

  /// Имя документа-источника.
  String get documentId => image.fileName;

  /// Индекс раздела документа.
  int get sectionIndex => image.sectionIndex;

  /// Номер страницы; `null` — не применимо.
  int? get page => image.page;

  /// Порядок на странице.
  int get order => image.order;

  /// Положение на странице в долях.
  DocumentImageRect? get rect => image.rect;

  /// Подпись изображения.
  String? get caption => image.caption;

  /// Окружающий текст.
  String? get context => image.context;

  /// true, если у изображения нет текстовой секции.
  bool get isOrphan => sectionId == null;

  @override
  String toString() =>
      'ImageRef($id, ${image.mediaType.mimeType}, '
      '${sectionId ?? 'orphan'})';
}

/// Все изображения документа (строки каталога `<images>` доступны каждому
/// фрагменту документа — E.2).
class DocumentCatalog {
  /// Создаёт каталог; порядок изображений сохраняется.
  DocumentCatalog({
    required this.documentId,
    List<ImageRef> images = const <ImageRef>[],
  }) : assert(documentId.isNotEmpty),
       images = List<ImageRef>.unmodifiable(images);

  /// id документа.
  final String documentId;

  /// Изображения документа.
  final List<ImageRef> images;

  /// true, если изображений нет.
  bool get isEmpty => images.isEmpty;

  /// Изображение по id или `null`.
  ImageRef? imageById(String id) {
    for (final ImageRef ref in images) {
      if (ref.id == id) return ref;
    }
    return null;
  }

  @override
  String toString() => 'DocumentCatalog($documentId, ${images.length})';
}

/// Раздел документа: текст, фрагменты текста и связанные изображения.
class SectionUnit {
  /// Создаёт раздел; списки становятся неизменяемыми.
  SectionUnit({
    required this.id,
    required this.index,
    required this.text,
    required this.tokens,
    this.title,
    this.pageRange,
    List<TextPiece> pieces = const <TextPiece>[],
    List<ImageRef> images = const <ImageRef>[],
  }) : assert(id.isNotEmpty),
       assert(index >= 0),
       assert(tokens >= 0, 'Токены не могут быть отрицательными'),
       pieces = List<TextPiece>.unmodifiable(pieces),
       images = List<ImageRef>.unmodifiable(images);

  /// Стабильный id (`doc:<файл>#<индекс>`).
  final String id;

  /// Индекс раздела в документе.
  final int index;

  /// Заголовок раздела, если известен.
  final String? title;

  /// Диапазон страниц раздела, если известен.
  final PageRange? pageRange;

  /// Текст раздела.
  final String text;

  /// Оценка токенов текста раздела.
  final int tokens;

  /// Фрагменты текста в порядке следования.
  final List<TextPiece> pieces;

  /// Изображения этого раздела в порядке следования.
  final List<ImageRef> images;

  @override
  String toString() =>
      'SectionUnit($id, ${text.length} симв., pieces: ${pieces.length}, '
      'images: ${images.length})';
}

/// Документ как набор разделов и каталога изображений.
class DocumentUnit {
  /// Создаёт документ; каталог дополняется изображениями разделов, чтобы ни
  /// одно изображение не выпало из модели (E.2/E.6).
  DocumentUnit({
    required this.id,
    required this.fileName,
    required this.format,
    List<SectionUnit> sections = const <SectionUnit>[],
    DocumentCatalog? catalog,
    this.pageCount,
  }) : assert(id.isNotEmpty),
       assert(fileName.isNotEmpty),
       sections = List<SectionUnit>.unmodifiable(sections),
       catalog = _mergeCatalog(
         documentId: id,
         sections: sections,
         catalog: catalog,
       );

  /// Стабильный id (`doc:<имя файла>`).
  final String id;

  /// Имя исходного файла.
  final String fileName;

  /// Формат источника.
  final DocumentFormat format;

  /// Число страниц (PDF/PPTX), если известно.
  final int? pageCount;

  /// Разделы в порядке следования.
  final List<SectionUnit> sections;

  /// Каталог всех изображений документа.
  final DocumentCatalog catalog;

  /// Изображения документа.
  List<ImageRef> get images => catalog.images;

  /// Раздел по индексу или `null`.
  SectionUnit? sectionByIndex(int index) {
    for (final SectionUnit section in sections) {
      if (section.index == index) return section;
    }
    return null;
  }

  @override
  String toString() =>
      'DocumentUnit($id, ${format.extension}, sections: ${sections.length}, '
      'images: ${images.length})';
}

/// Страница вложения (PDF-скан или одиночное изображение).
class PageUnit {
  /// Создаёт страницу; [pageNumber] == `null` — номер неизвестен.
  PageUnit({
    required this.id,
    required this.bytes,
    required this.tokens,
    this.pageNumber,
  }) : assert(id.isNotEmpty),
       assert(tokens >= 0, 'Токены не могут быть отрицательными'),
       assert(bytes.isNotEmpty, 'Страница не может быть пустой'),
       assert(pageNumber == null || pageNumber >= 1);

  /// Стабильный id (`att:<ключ>#p<N>` или id вложения).
  final String id;

  /// Номер страницы (с 1); `null` — не применимо.
  final int? pageNumber;

  /// Содержимое страницы (JPEG/PNG/PDF).
  final Uint8List bytes;

  /// Оценка токенов изображения.
  final int tokens;

  @override
  String toString() => 'PageUnit($id, ${bytes.length} байт)';
}

/// Вложение пользователя как группа страниц одного файла.
class AttachmentUnit {
  /// Создаёт вложение; страницы сохраняют порядок.
  AttachmentUnit({
    required this.id,
    required this.fileName,
    required this.mediaType,
    this.groupKey,
    List<PageUnit> pages = const <PageUnit>[],
  }) : assert(id.isNotEmpty),
       assert(fileName.isNotEmpty),
       pages = List<PageUnit>.unmodifiable(pages);

  /// Стабильный id (`att:<имя или ключ группы>`).
  final String id;

  /// Имя исходного файла.
  final String fileName;

  /// MIME-тип вложения.
  final AttachmentMediaType mediaType;

  /// Ключ группы: страницы одного PDF отправляются вместе.
  final String? groupKey;

  /// Страницы в порядке следования.
  final List<PageUnit> pages;

  /// Суммарная оценка токенов страниц.
  int get totalTokens =>
      pages.fold(0, (int total, PageUnit page) => total + page.tokens);

  /// Суммарный размер вложенных байтов.
  int get byteLength =>
      pages.fold(0, (int total, PageUnit page) => total + page.bytes.length);

  /// Страница по номеру или `null`.
  PageUnit? pageByNumber(int pageNumber) {
    for (final PageUnit page in pages) {
      if (page.pageNumber == pageNumber) return page;
    }
    return null;
  }

  @override
  String toString() =>
      'AttachmentUnit($id, ${mediaType.mimeType}, pages: ${pages.length})';
}

/// Изображение без текстовой секции (orphan) — отдельная единица, не теряется.
class OrphanImageUnit {
  /// Создаёт единицу; [image] обязан быть orphan (`sectionId == null`).
  OrphanImageUnit({required this.image})
    : assert(image.isOrphan, 'Orphan-единица требует изображение без раздела');

  /// Изображение без раздела.
  final ImageRef image;

  /// Стабильный id изображения.
  String get id => image.id;

  /// Имя документа-источника.
  String get fileName => image.documentId;

  @override
  String toString() => 'OrphanImageUnit($id)';
}

/// Полный перечень содержимого запроса генерации.
class ContentInventory {
  /// Создаёт перечень; списки становятся неизменяемыми.
  ContentInventory({
    List<DocumentUnit> documents = const <DocumentUnit>[],
    List<AttachmentUnit> attachments = const <AttachmentUnit>[],
    List<OrphanImageUnit> orphanImages = const <OrphanImageUnit>[],
  }) : documents = List<DocumentUnit>.unmodifiable(documents),
       attachments = List<AttachmentUnit>.unmodifiable(attachments),
       orphanImages = List<OrphanImageUnit>.unmodifiable(orphanImages);

  /// Пустой перечень (prompt-only без материалов, ADR-024).
  static final ContentInventory empty = ContentInventory();

  /// Документы пользователя.
  final List<DocumentUnit> documents;

  /// Вложения пользователя (изображения/PDF-сканы).
  final List<AttachmentUnit> attachments;

  /// Изображения без текстовой секции.
  final List<OrphanImageUnit> orphanImages;

  /// true, если материалов нет вообще.
  bool get isEmpty =>
      documents.isEmpty && attachments.isEmpty && orphanImages.isEmpty;

  /// Все изображения модели: каталоги документов и orphan-единицы.
  Iterable<ImageRef> get allImages sync* {
    for (final DocumentUnit document in documents) {
      yield* document.images;
    }
    for (final OrphanImageUnit orphan in orphanImages) {
      yield orphan.image;
    }
  }

  /// Число изображений в перечне.
  int get imageCount => allImages.length;

  /// Изображение по стабильному id или `null`.
  ImageRef? imageById(String id) {
    for (final ImageRef ref in allImages) {
      if (ref.id == id) return ref;
    }
    return null;
  }

  @override
  String toString() =>
      'ContentInventory(documents: ${documents.length}, '
      'attachments: ${attachments.length}, orphans: ${orphanImages.length})';
}

DocumentCatalog _mergeCatalog({
  required String documentId,
  required List<SectionUnit> sections,
  required DocumentCatalog? catalog,
}) {
  assert(
    catalog == null || catalog.documentId == documentId,
    'Каталог принадлежит другому документу',
  );
  final Map<String, ImageRef> merged = <String, ImageRef>{};
  if (catalog != null) {
    for (final ImageRef ref in catalog.images) {
      merged.putIfAbsent(ref.id, () => ref);
    }
  }
  for (final SectionUnit section in sections) {
    for (final ImageRef ref in section.images) {
      merged.putIfAbsent(ref.id, () => ref);
    }
  }
  return DocumentCatalog(
    documentId: documentId,
    images: merged.values.toList(growable: false),
  );
}
