/// Каталог изображений из прикреплённых файлов для блока `<images>` (fix-gen).
///
/// Формат строки задан системным промптом `gen-ru-v7`:
/// «id | файл | подпись | окружающий текст»; для PDF/сканов перед окружающим
/// текстом добавляется страница («стр. 2»), чтобы модель привязывала
/// изображение к странице. В запрос уходят и текст, и идентификаторы, и —
/// если модель поддерживает Vision — **байты** изображений отдельными частями
/// (ADR-037).
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/document_image.dart';

/// Префикс идентификатора изображения в каталоге (id как в промпте: `img1`).
const String kDocumentImageIdPrefix = 'img';

/// Максимум изображений документа, передаваемых модели как image-parts
/// в одном запросе (ADR-037): защита от переполнения запроса.
const int kMaxVisionDocumentImages = 8;

/// Максимум суммарного размера image-parts документов в одном запросе.
const int kMaxVisionDocumentImagesBytes = 24 * 1024 * 1024;

/// Назначает изображениям идентификаторы каталога `img1…imgN` по порядку.
List<DocumentImage> withCatalogIds(List<DocumentImage> images) {
  return <DocumentImage>[
    for (var index = 0; index < images.length; index++)
      images[index].withId('$kDocumentImageIdPrefix${index + 1}'),
  ];
}

/// Одна строка каталога `<images>`: `id | файл | подпись | окружающий текст`.
///
/// Для изображений с известной страницей окружающий текст начинается с
/// «стр. N» (PDF/scан, ADR-037).
String imageCatalogLine(DocumentImage image) {
  final String context = _clean(
    image.context,
    maxLength: kDocumentImageContextMaxLength,
  );
  final String? page = image.sourceLabel;
  final String mergedContext = page == null
      ? context
      : context.isEmpty
      ? page
      : '$page. $context';
  return <String>[
    image.id,
    _clean(image.fileName),
    _clean(image.caption),
    mergedContext,
  ].join(' | ');
}

/// Текст блока `<images>` (без тегов) по каталогу изображений фрагмента.
String buildImageCatalog(List<DocumentImage> images) {
  return <String>[
    for (final DocumentImage image in images) imageCatalogLine(image),
  ].join('\n');
}

/// Отбирает изображения для передачи модели как image-parts (Vision).
///
/// Приоритет (ADR-037): подпись рисунка → значимая область/встроенное
/// изображение → площадь в пикселях. Ограничения: [maxImages] изображений и
/// [maxBytes] суммарного размера. Не вошедшие остаются в каталоге `<images>`:
/// модель может выбрать их по `image_id`, байты найдутся при импорте.
List<DocumentImage> selectVisionDocumentImages(
  List<DocumentImage> images, {
  int maxImages = kMaxVisionDocumentImages,
  int maxBytes = kMaxVisionDocumentImagesBytes,
}) {
  if (images.isEmpty) return const <DocumentImage>[];
  final List<({DocumentImage image, int index, int score})> ranked =
      <({DocumentImage image, int index, int score})>[];

  final Set<String> digests = <String>{};
  for (var index = 0; index < images.length; index++) {
    final DocumentImage image = images[index];
    // Одинаковые байты не отправляем дважды.
    if (!digests.add(contentDigestOf(image.bytes))) continue;
    ranked.add((image: image, index: index, score: _visionScore(image)));
  }
  ranked.sort((a, b) {
    final int byScore = b.score.compareTo(a.score);
    if (byScore != 0) return byScore;
    final int byPage = (a.image.page ?? 0).compareTo(b.image.page ?? 0);
    if (byPage != 0) return byPage;
    return a.index.compareTo(b.index);
  });
  final List<({DocumentImage image, int index, int score})> selected =
      <({DocumentImage image, int index, int score})>[];
  var totalBytes = 0;
  for (final ({DocumentImage image, int index, int score}) entry in ranked) {
    if (selected.length >= maxImages) break;
    final int size = entry.image.bytes.length;
    if (totalBytes + size > maxBytes) continue;
    totalBytes += size;
    selected.add(entry);
  }
  // Возвращаем порядок документа — стабильные id/части запроса.
  selected.sort((a, b) => a.index.compareTo(b.index));
  return List<DocumentImage>.unmodifiable(<DocumentImage>[
    for (final entry in selected) entry.image,
  ]);
}

/// Оценка приоритета изображения для Vision.
int _visionScore(DocumentImage image) {
  var score = 0;
  if (image.caption != null) score += 40;
  score += switch (image.source) {
    DocumentImageSource.embedded => 20,
    DocumentImageSource.croppedRegion => 12,
    DocumentImageSource.renderedPage => 4,
  };
  final int area = (image.width ?? 0) * (image.height ?? 0);
  if (area > 0) score += (math.log(area + 1) * 2).round();
  return score;
}

/// SHA-256 содержимого изображения (дедупликация частей запроса).
String contentDigestOf(List<int> bytes) => documentImageDigest(bytes);

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
