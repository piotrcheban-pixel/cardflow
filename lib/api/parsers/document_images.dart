/// Извлечение изображений из документов с контекстом (fix-gen, Д3).
///
/// Приоритет 1 для иллюстраций — изображения из прикреплённых файлов
/// (SPEC A8.1): DOCX — `word/media` + привязка к абзацу через `r:embed`,
/// PPTX — `ppt/media` + слайд, ODT — `Pictures/`. Для каждого изображения
/// сохраняется подпись («Рис. N …»), соседний абзац/заголовок слайда и номер
/// страницы/слайда. Логотипы, иконки и повторы отбрасываются по размеру
/// байт/пикселей и хешу содержимого.
library;

import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Минимальный размер файла изображения (меньше — иконка/линия/логотип).
const int kMinDocumentImageBytes = 4096;

/// Минимальная сторона изображения в пикселях (меньше — мусор).
const int kMinDocumentImageSide = 64;

/// MIME-тип изображения по имени записи архива; `null` — формат не поддержан.
AttachmentMediaType? documentImageMediaType(String entryName) {
  final int dot = entryName.lastIndexOf('.');
  if (dot < 0 || dot == entryName.length - 1) return null;
  final String extension = entryName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' || 'jpe' => AttachmentMediaType.jpeg,
    'png' => AttachmentMediaType.png,
    _ => null,
  };
}

/// Размеры JPEG/PNG по заголовку файла без полного декодирования.
({int width, int height})? imagePixelSize(Uint8List bytes) {
  if (bytes.length < 24) return null;
  if (_startsWith(bytes, const <int>[0x89, 0x50, 0x4E, 0x47])) {
    final ByteData data = ByteData.sublistView(bytes);
    final int width = data.getUint32(16);
    final int height = data.getUint32(20);
    if (width <= 0 || height <= 0) return null;
    return (width: width, height: height);
  }
  if (_startsWith(bytes, const <int>[0xFF, 0xD8])) {
    return _jpegSize(bytes);
  }
  return null;
}

({int width, int height})? _jpegSize(Uint8List bytes) {
  var index = 2;
  while (index + 9 < bytes.length) {
    if (bytes[index] != 0xFF) {
      index++;
      continue;
    }
    final int marker = bytes[index + 1];
    final bool isStartOfFrame =
        marker >= 0xC0 && marker <= 0xCF && marker != 0xC4 && marker != 0xC8;
    if (isStartOfFrame) {
      final int height = (bytes[index + 5] << 8) | bytes[index + 6];
      final int width = (bytes[index + 7] << 8) | bytes[index + 8];
      if (width <= 0 || height <= 0) return null;
      return (width: width, height: height);
    }
    final int length = (bytes[index + 2] << 8) | bytes[index + 3];
    if (length < 2) return null;
    index += 2 + length;
  }
  return null;
}

bool _startsWith(Uint8List bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}

/// SHA-256 содержимого — для отсева повторов (логотип на каждом слайде).
String contentDigest(Uint8List bytes) => sha256.convert(bytes).toString();

/// Подпись рисунка: «Рис. 3 Схема фермы», «Рисунок 2», «Figure 4».
final RegExp _captionPattern = RegExp(
  r'^\s*(?:рис(?:унок|\.)?|fig(?:ure|\.)?|табл(?:ица|\.)?|схема|photo|фото)'
  r'\s*\.?\s*\d',
  caseSensitive: false,
  unicode: true,
);

/// Похож ли текст на подпись рисунка.
bool looksLikeImageCaption(String text) => _captionPattern.hasMatch(text);

/// Собирает изображения документа: фильтры мусора и дедупликация.
class DocumentImageCollector {
  /// Создаёт коллектор.
  DocumentImageCollector();

  final Set<String> _digests = <String>{};

  /// Возвращает изображение, если оно проходит фильтры, иначе `null`.
  ///
  /// [entryName] — имя записи архива (для типа), [bytes] — содержимое,
  /// [fileName] — имя исходного документа, [sectionIndex] — раздел.
  DocumentImage? add({
    required String entryName,
    required Uint8List bytes,
    required String fileName,
    required int sectionIndex,
    String? caption,
    String? context,
    int? page,
  }) {
    final AttachmentMediaType? mediaType = documentImageMediaType(entryName);
    if (mediaType == null) return null;
    if (bytes.length < kMinDocumentImageBytes) return null;
    if (!hasValidAttachmentSignature(mediaType, bytes)) return null;
    final ({int width, int height})? size = imagePixelSize(bytes);
    if (size == null) return null;
    if (size.width < kMinDocumentImageSide ||
        size.height < kMinDocumentImageSide) {
      return null;
    }
    final String digest = contentDigest(bytes);
    if (!_digests.add(digest)) return null;
    return DocumentImage(
      fileName: fileName,
      bytes: bytes,
      mediaType: mediaType,
      caption: _normalize(caption),
      context: _normalize(context),
      page: page,
      sectionIndex: sectionIndex,
      width: size.width,
      height: size.height,
    );
  }

  static String? _normalize(String? value) {
    if (value == null) return null;
    final String cleaned = value
        .replaceAll(RegExp(r'\s+', unicode: true), ' ')
        .trim();
    return cleaned.isEmpty ? null : cleaned;
  }
}
