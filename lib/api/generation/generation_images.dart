/// Каталог изображений из прикреплённых файлов для блока `<images>` (fix-gen).
///
/// Формат строки задан системным промптом `gen-ru-v5`:
/// «id | файл | подпись | окружающий текст». В запрос уходят только текст и
/// идентификаторы — бинарные данные передаются провайдеру отдельными частями
/// (Vision) либо не передаются вовсе.
library;

import 'package:cardflow/domain/generation/document_image.dart';

/// Префикс идентификатора изображения в каталоге (id как в промпте: `img1`).
const String kDocumentImageIdPrefix = 'img';

/// Назначает изображениям идентификаторы каталога `img1…imgN` по порядку.
List<DocumentImage> withCatalogIds(List<DocumentImage> images) {
  return <DocumentImage>[
    for (var index = 0; index < images.length; index++)
      images[index].withId('$kDocumentImageIdPrefix${index + 1}'),
  ];
}

/// Одна строка каталога `<images>`: `id | файл | подпись | окружающий текст`.
String imageCatalogLine(DocumentImage image) {
  return <String>[
    image.id,
    _clean(image.fileName),
    _clean(image.caption),
    _clean(image.context, maxLength: kDocumentImageContextMaxLength),
  ].join(' | ');
}

/// Текст блока `<images>` (без тегов) по каталогу изображений фрагмента.
String buildImageCatalog(List<DocumentImage> images) {
  return <String>[
    for (final DocumentImage image in images) imageCatalogLine(image),
  ].join('\n');
}

/// Чистит значение для строки каталога: без переводов строк и разделителя `|`.
String _clean(String? value, {int maxLength = 80}) {
  if (value == null) return '';
  final String cleaned = value
      .replaceAll(RegExp(r'\s+', unicode: true), ' ')
      .replaceAll('|', '/')
      .trim();
  if (cleaned.length <= maxLength) return cleaned;
  return '${cleaned.substring(0, maxLength).trim()}…';
}
