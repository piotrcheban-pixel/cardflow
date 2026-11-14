/// Вложение запроса генерации: изображение или PDF-скан (итерация 7.8).
///
/// Прямая загрузка файлов поддерживается провайдерами по-разному, поэтому
/// вложения передаются только как inline-части запроса (base64) и лишь когда
/// выбранная модель поддерживает Vision. Домен не зависит от Flutter.
library;

import 'dart:typed_data';

/// Максимальный размер inline-вложения (base64 увеличивает тело на ~33 %).
const int kMaxInlineAttachmentBytes = 10 * 1024 * 1024;

/// MIME-тип вложения.
enum AttachmentMediaType {
  /// JPEG-изображение.
  jpeg('image/jpeg'),

  /// PNG-изображение.
  png('image/png'),

  /// PDF, отправляемый как документ/скан (только PDF-vision протоколы).
  pdf('application/pdf');

  const AttachmentMediaType(this.mimeType);

  /// MIME-тип для части запроса провайдера.
  final String mimeType;

  /// true для изображений (JPG/PNG).
  bool get isImage => this != pdf;
}

/// Вложение генерации.
class GenerationAttachment {
  /// Создаёт вложение.
  const GenerationAttachment({
    required this.fileName,
    required this.mediaType,
    required this.bytes,
  });

  /// Имя исходного файла (для prompt и `generation_jobs.files`).
  final String fileName;

  /// MIME-тип.
  final AttachmentMediaType mediaType;

  /// Содержимое файла.
  final Uint8List bytes;

  /// MIME-тип строкой.
  String get mimeType => mediaType.mimeType;

  /// true, если это PDF-скан (document-part, а не image-part).
  bool get isPdf => mediaType == AttachmentMediaType.pdf;

  @override
  String toString() =>
      'GenerationAttachment($fileName, ${mediaType.mimeType}, '
      '${bytes.length} байт)';
}

/// MIME-тип изображения по имени файла; `null` — не JPG/JPEG/PNG.
AttachmentMediaType? attachmentMediaTypeForFileName(String fileName) {
  final int dot = fileName.lastIndexOf('.');
  if (dot < 0 || dot == fileName.length - 1) return null;
  final String extension = fileName.substring(dot + 1).toLowerCase();
  return switch (extension) {
    'jpg' || 'jpeg' => AttachmentMediaType.jpeg,
    'png' => AttachmentMediaType.png,
    _ => null,
  };
}

/// Проверяет сигнатуру изображения/PDF до отправки провайдеру.
bool hasValidAttachmentSignature(
  AttachmentMediaType mediaType,
  List<int> bytes,
) {
  return switch (mediaType) {
    AttachmentMediaType.png => _startsWith(bytes, const <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]),
    AttachmentMediaType.jpeg => _startsWith(bytes, const <int>[
      0xFF,
      0xD8,
      0xFF,
    ]),
    AttachmentMediaType.pdf => _startsWith(bytes, const <int>[
      0x25,
      0x50,
      0x44,
      0x46,
      0x2D,
    ]),
  };
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var i = 0; i < prefix.length; i++) {
    if (bytes[i] != prefix[i]) return false;
  }
  return true;
}
