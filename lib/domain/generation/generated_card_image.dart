/// Найденная в интернете иллюстрация для сгенерированной карточки (итерация 7.9).
///
/// Байты живут в памяти до импорта карточки; в `MediaStore` их записывает
/// `DriftGenerationCardStore` только для выбранных пользователем карточек.
/// Вместе с байтами хранятся метаданные атрибуции (провайдер, автор, лицензия).
/// С 7.19 синтезированных изображений нет: `isPlaceholder` удалён, а байты
/// проверяются по сигнатуре (`image_bytes.dart`) до записи (ADR-041).
/// Домен не зависит от Flutter.
library;

import 'dart:typed_data';

import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Иллюстрация карточки из поиска (не сгенерированная моделью).
class GeneratedCardImage {
  /// Создаёт иллюстрацию.
  const GeneratedCardImage({
    required this.bytes,
    required this.mediaType,
    required this.query,
    this.kind = GeneratedCardImageKind.photo,
    this.fallbackQuery,
    this.sourceUrl,
    this.attribution,
    this.provider,
    this.author,
    this.license,
  });

  /// Содержимое изображения (JPEG/PNG/WebP).
  final Uint8List bytes;

  /// MIME-тип изображения.
  final AttachmentMediaType mediaType;

  /// Поисковый запрос, по которому найдена картинка.
  final String query;

  /// Тип иллюстрации из ответа модели (`photo | diagram | illustration`).
  final GeneratedCardImageKind kind;

  /// Более общий запасной запрос модели; `null` — не задан.
  final String? fallbackQuery;

  /// URL, откуда скачано изображение; `null` — изображение из файла.
  final String? sourceUrl;

  /// Готовая строка атрибуции для показа («автор · лицензия»), если есть.
  final String? attribution;

  /// Провайдер поиска (`wikimedia`, `openverse`, `pixabay`, `pexels`, `file`).
  final String? provider;

  /// Автор изображения (для полноэкранного просмотра).
  final String? author;

  /// Лицензия изображения (CC BY-SA 4.0, CC0, Public domain, …).
  final String? license;

  /// MIME-тип строкой (`image/jpeg`, `image/png`, `image/webp`).
  String get mimeType => mediaType.mimeType;

  /// Расширение файла для `MediaStore`.
  String get fileExtension => switch (mediaType) {
    AttachmentMediaType.jpeg => 'jpg',
    AttachmentMediaType.png => 'png',
    AttachmentMediaType.webp => 'webp',
    AttachmentMediaType.pdf => 'pdf',
  };

  /// Копия с заменёнными метаданными (кэш/повторный поиск).
  GeneratedCardImage copyWith({
    Uint8List? bytes,
    AttachmentMediaType? mediaType,
    String? query,
    GeneratedCardImageKind? kind,
    String? fallbackQuery,
    String? sourceUrl,
    String? attribution,
    String? provider,
    String? author,
    String? license,
  }) {
    return GeneratedCardImage(
      bytes: bytes ?? this.bytes,
      mediaType: mediaType ?? this.mediaType,
      query: query ?? this.query,
      kind: kind ?? this.kind,
      fallbackQuery: fallbackQuery ?? this.fallbackQuery,
      sourceUrl: sourceUrl ?? this.sourceUrl,
      attribution: attribution ?? this.attribution,
      provider: provider ?? this.provider,
      author: author ?? this.author,
      license: license ?? this.license,
    );
  }

  @override
  String toString() =>
      'GeneratedCardImage(${mediaType.mimeType}, ${bytes.length} байт, '
      'query: $query, kind: ${kind.wireName}, provider: $provider)';
}
