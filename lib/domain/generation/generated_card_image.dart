/// Найденная в интернете иллюстрация для сгенерированной карточки (итерация 7.9).
///
/// Байты живут в памяти до импорта карточки; в `MediaStore` их записывает
/// `DriftGenerationCardStore` только для выбранных пользователем карточек.
/// Домен не зависит от Flutter.
library;

import 'dart:typed_data';

import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Иллюстрация карточки из поиска (не сгенерированная моделью).
class GeneratedCardImage {
  /// Создаёт иллюстрацию.
  const GeneratedCardImage({
    required this.bytes,
    required this.mediaType,
    required this.query,
    this.sourceUrl,
    this.attribution,
  });

  /// Содержимое изображения (JPEG/PNG).
  final Uint8List bytes;

  /// MIME-тип изображения.
  final AttachmentMediaType mediaType;

  /// Поисковый запрос, по которому найдена картинка.
  final String query;

  /// URL, откуда скачано изображение.
  final String? sourceUrl;

  /// Атрибуция/лицензия источника (CC), если провайдер поиска её вернул.
  final String? attribution;

  /// MIME-тип строкой (`image/jpeg`/`image/png`).
  String get mimeType => mediaType.mimeType;

  /// Расширение файла для `MediaStore`.
  String get fileExtension =>
      mediaType == AttachmentMediaType.jpeg ? 'jpg' : 'png';

  @override
  String toString() =>
      'GeneratedCardImage(${mediaType.mimeType}, ${bytes.length} байт, '
      'query: $query)';
}
