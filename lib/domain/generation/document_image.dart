/// Изображение, извлечённое из прикреплённого документа (итерация fix-gen).
///
/// Изображения из файлов пользователя — приоритетный источник иллюстраций
/// (SPEC A6.8/A8.1): модель видит каталог `<images>` и возвращает `image_id`.
/// Байты хранятся в памяти до импорта; в `MediaStore` их пишет только импорт.
/// Домен не зависит от Flutter.
library;

import 'dart:typed_data';

import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Максимальная длина подписи/окружающего текста в каталоге `<images>`.
const int kDocumentImageContextMaxLength = 160;

/// Изображение из DOCX/PPTX/ODT с контекстом (подпись, абзац, слайд/страница).
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

  /// Окружающий текст: абзац с рисунком, заголовок раздела или заголовок слайда.
  final String? context;

  /// Номер страницы/слайда (с 1); `null` — не применимо.
  final int? page;

  /// Индекс раздела документа, к которому относится изображение.
  final int sectionIndex;

  /// Ширина в пикселях (если удалось определить по заголовку файла).
  final int? width;

  /// Высота в пикселях (если удалось определить по заголовку файла).
  final int? height;

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
    );
  }

  /// MIME-тип строкой (`image/jpeg`/`image/png`).
  String get mimeType => mediaType.mimeType;

  @override
  String toString() =>
      'DocumentImage($id, $fileName, ${bytes.length} байт, page: $page)';
}
