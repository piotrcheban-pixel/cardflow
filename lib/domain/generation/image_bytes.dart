/// Проверка байтов изображения по сигнатуре (итерация 7.19).
///
/// MIME из ответа модели/метаданных не является фактом: сервер мог отдать
/// HTML/пустое тело/JSON ошибки. Перед записью в `MediaStore` и при
/// диагностике целостности байты проверяются по магическим числам, чтобы
/// повреждённый файл не попал в карточку как «изображение».
///
/// Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Формат изображения, определённый по сигнатуре.
enum ImageFormat {
  /// JPEG (`FF D8 FF`).
  jpeg,

  /// PNG (`89 50 4E 47 0D 0A 1A 0A`).
  png,

  /// WebP (`RIFF…WEBP`).
  webp,

  /// GIF (`GIF87a`/`GIF89a`).
  gif,

  /// Не изображение или сигнатура повреждена.
  unknown,
}

/// Определяет формат по первым байтам; пустой массив → [ImageFormat.unknown].
///
/// Каждый формат требует своей минимальной длины сигнатуры: JPEG — 3 байта,
/// PNG — 8, WebP — 12 («RIFF????WEBP»), GIF — 6. Короткие обрезки не считаются
/// изображением.
ImageFormat sniffImageFormat(List<int> bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return ImageFormat.jpeg;
  }
  const List<int> png = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  if (bytes.length >= png.length && _startsWith(bytes, png)) {
    return ImageFormat.png;
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return ImageFormat.webp;
  }
  if (bytes.length >= 6 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return ImageFormat.gif;
  }
  return ImageFormat.unknown;
}

/// Поддерживаемый формат карточки: JPEG/PNG/WebP (GIF не показывается
/// карточками и не сохраняется как медиа карточки).
bool isSupportedImageBytes(List<int> bytes) {
  return switch (sniffImageFormat(bytes)) {
    ImageFormat.jpeg || ImageFormat.png || ImageFormat.webp => true,
    ImageFormat.gif || ImageFormat.unknown => false,
  };
}

/// Совпадает ли MIME из ответа с фактической сигнатурой.
bool imageBytesMatchMediaType(List<int> bytes, AttachmentMediaType type) {
  return switch (sniffImageFormat(bytes)) {
    ImageFormat.jpeg => type == AttachmentMediaType.jpeg,
    ImageFormat.png => type == AttachmentMediaType.png,
    ImageFormat.webp => type == AttachmentMediaType.webp,
    ImageFormat.gif || ImageFormat.unknown => false,
  };
}

/// MIME по сигнатуре; `null` — не поддерживаемое изображение.
AttachmentMediaType? mediaTypeOfImageBytes(List<int> bytes) {
  return switch (sniffImageFormat(bytes)) {
    ImageFormat.jpeg => AttachmentMediaType.jpeg,
    ImageFormat.png => AttachmentMediaType.png,
    ImageFormat.webp => AttachmentMediaType.webp,
    ImageFormat.gif || ImageFormat.unknown => null,
  };
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}
