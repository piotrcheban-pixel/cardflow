/// Изображение, извлечённое из прикреплённого документа (итерация fix-gen).
///
/// Изображения из файлов пользователя — приоритетный источник иллюстраций
/// (SPEC A6.8/A8.1): модель видит каталог `<images>` и возвращает `image_id`.
/// Байты хранятся в памяти до импорта; в `MediaStore` их пишет только импорт.
/// Домен не зависит от Flutter.
///
/// Итерация PDF Visual Intelligence (L76, ADR-037): у изображения появились
/// источник (`embedded`/`renderedPage`/`croppedRegion`), положение на странице
/// (`rect`, доли 0..1) и порядок (`order`). Значения по умолчанию сохраняют
/// поведение DOCX/PPTX/ODT: `source = embedded`, координат нет.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:cardflow/domain/generation/generation_attachment.dart';

/// SHA-256 содержимого изображения (дедупликация частей запроса и каталога).
///
/// Одна реализация на домен и API: сервис/планировщик не должны расходиться в
/// том, какие байты считаются одинаковыми (TASK 03, D11).
String documentImageDigest(List<int> bytes) => sha256.convert(bytes).toString();

/// Максимальная длина подписи/окружающего текста в каталоге `<images>`.
const int kDocumentImageContextMaxLength = 160;

/// Источник изображения документа (ADR-037).
enum DocumentImageSource {
  /// Встроенное изображение файла: `word/media`/`ppt/media`/ODT `Pictures/`
  /// или PDF Image XObject (в том числе внутри Form XObject).
  embedded,

  /// Полный рендер страницы PDF без текстового слоя (скан или векторная
  /// страница): контекст для модели и основа для выделения областей.
  renderedPage,

  /// Значимая область страницы скана (схема, график, чертёж), вырезанная из
  /// полного рендера без масштабирования.
  croppedRegion,
}

/// Прямоугольник изображения на странице в долях страницы (0..1).
///
/// Начало координат — левый верхний угол страницы в экранной ориентации:
/// [left]/[top] отсчитываются от левого/верхнего края, [width]/[height] —
/// размеры области. Для PDF точка (0, 0) находится в левом нижнем углу,
/// поэтому парсер переводит координаты PDFium в эту систему.
class DocumentImageRect {
  /// Создаёт прямоугольник (значения клампятся в 0..1).
  DocumentImageRect({
    required double left,
    required double top,
    required double width,
    required double height,
  }) : left = _clamp(left),
       top = _clamp(top),
       width = _clamp(width),
       height = _clamp(height);

  /// Отступ слева (доля ширины страницы).
  final double left;

  /// Отступ сверху (доля высоты страницы).
  final double top;

  /// Ширина (доля ширины страницы).
  final double width;

  /// Высота (доля высоты страницы).
  final double height;

  /// Площадь области в долях площади страницы.
  double get areaFraction => width * height;

  /// Покрывает ли область почти всю страницу (скан целиком).
  bool coversPage([double threshold = 0.85]) => areaFraction >= threshold;

  /// JSON для метаданных/диагностики (схема БД не меняется).
  Map<String, Object?> toJson() => <String, Object?>{
    'left': left,
    'top': top,
    'width': width,
    'height': height,
  };

  static double _clamp(double value) {
    if (value.isNaN) return 0;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  @override
  String toString() =>
      'DocumentImageRect(${left.toStringAsFixed(3)}, '
      '${top.toStringAsFixed(3)}, ${width.toStringAsFixed(3)}×'
      '${height.toStringAsFixed(3)})';
}

/// Изображение из DOCX/PPTX/ODT/PDF с контекстом (подпись, абзац, страница).
class DocumentImage {
  /// Создаёт изображение документа.
  const DocumentImage({
    required this.fileName,
    required this.bytes,
    required this.mediaType,
    this.id = '',
    this.caption,
    this.context,
    this.page,
    this.sectionIndex = 0,
    this.width,
    this.height,
    this.source = DocumentImageSource.embedded,
    this.rect,
    this.order = 0,
  });

  /// Идентификатор в каталоге `<images>` текущего фрагмента (`img1`, `img2`, …).
  ///
  /// Назначается пайплайном перед вызовом модели; в парсере пуст.
  final String id;

  /// Имя исходного файла.
  final String fileName;

  /// Содержимое изображения (JPEG/PNG).
  final Uint8List bytes;

  /// MIME-тип (только JPEG/PNG; прочие форматы документов пропускаются).
  final AttachmentMediaType mediaType;

  /// Подпись («Рис. 3 …»), если её удалось найти.
  final String? caption;

  /// Окружающий текст: абзац с рисунком, заголовок раздела или страницы.
  final String? context;

  /// Номер страницы/слайда (с 1); `null` — не применимо.
  final int? page;

  /// Индекс раздела документа, к которому относится изображение.
  final int sectionIndex;

  /// Ширина в пикселях (если удалось определить по заголовку файла).
  final int? width;

  /// Высота в пикселях (если удалось определить по заголовку файла).
  final int? height;

  /// Как изображение получено из файла (ADR-037).
  final DocumentImageSource source;

  /// Положение на странице в долях (PDF/скан); `null` — неизвестно.
  final DocumentImageRect? rect;

  /// Порядок изображения на странице (0 — первое).
  final int order;

  /// MIME-тип строкой (`image/jpeg`/`image/png`).
  String get mimeType => mediaType.mimeType;

  /// Строка происхождения для каталога/диагностики:
  /// «стр. 2, схема из PDF» / «стр. 2, область скана».
  String? get sourceLabel {
    final int? pageNumber = page;
    if (pageNumber == null) return null;
    return switch (source) {
      DocumentImageSource.embedded => 'стр. $pageNumber',
      DocumentImageSource.renderedPage => 'стр. $pageNumber, страница скана',
      DocumentImageSource.croppedRegion => 'стр. $pageNumber, область скана',
    };
  }

  /// Копия с другим [id] (назначение идентификатора каталога).
  DocumentImage withId(String value) {
    return DocumentImage(
      id: value,
      fileName: fileName,
      bytes: bytes,
      mediaType: mediaType,
      caption: caption,
      context: context,
      page: page,
      sectionIndex: sectionIndex,
      width: width,
      height: height,
      source: source,
      rect: rect,
      order: order,
    );
  }

  /// Копия с номером раздела (после сборки документа).
  DocumentImage withSectionIndex(int value) {
    return DocumentImage(
      id: id,
      fileName: fileName,
      bytes: bytes,
      mediaType: mediaType,
      caption: caption,
      context: context,
      page: page,
      sectionIndex: value,
      width: width,
      height: height,
      source: source,
      rect: rect,
      order: order,
    );
  }

  /// Копия с подписью и окружающим текстом (привязка к тексту страницы).
  DocumentImage withContext({String? caption, String? context}) {
    return DocumentImage(
      id: id,
      fileName: fileName,
      bytes: bytes,
      mediaType: mediaType,
      caption: caption ?? this.caption,
      context: context ?? this.context,
      page: page,
      sectionIndex: sectionIndex,
      width: width,
      height: height,
      source: source,
      rect: rect,
      order: order,
    );
  }

  @override
  String toString() =>
      'DocumentImage($id, $fileName, ${bytes.length} байт, page: $page, '
      'source: ${source.name})';
}
