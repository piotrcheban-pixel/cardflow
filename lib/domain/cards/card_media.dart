import 'dart:typed_data';

/// Изображение, выбранное для новой или редактируемой карточки.
class CardImageUpload {
  const CardImageUpload({
    required this.fileName,
    required this.mimeType,
    required this.bytes,
  });

  final String fileName;
  final String mimeType;
  final Uint8List bytes;

  /// Расширение файла по MIME (JPEG → jpg, WebP → webp, иначе png).
  String get extension => switch (mimeType) {
    'image/jpeg' => 'jpg',
    'image/webp' => 'webp',
    _ => 'png',
  };
}

/// Токен порядка для нового изображения в `CardDraft.*MediaOrder`.
///
/// В `questionMediaOrder`/`answerMediaOrder` хранимые id карточки и новые
/// загрузки идут в одном списке: `upload:<index>` ссылается на соответствующий
/// элемент `questionUploads`/`answerUploads`. Так порядок «хранимое ↔ новое»
/// сохраняется при записи (ADR-042).
const String kUploadMediaTokenPrefix = 'upload:';

/// Токен для загрузки с индексом [index] (индекс в списке uploads стороны).
String uploadMediaToken(int index) => '$kUploadMediaTokenPrefix$index';

/// Индекс загрузки из токена; `null` — это не токен загрузки.
int? uploadMediaIndexOf(String value) {
  if (!value.startsWith(kUploadMediaTokenPrefix)) return null;
  return int.tryParse(value.substring(kUploadMediaTokenPrefix.length));
}

/// Системный выбор одного изображения для Image Occlusion.
abstract interface class CardImageGateway {
  static const int maxImageBytes = 25 * 1024 * 1024;

  Future<CardImageUpload?> pickImage();
}
