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

  String get extension => mimeType == 'image/jpeg' ? 'jpg' : 'png';
}

/// Системный выбор одного изображения для Image Occlusion.
abstract interface class CardImageGateway {
  static const int maxImageBytes = 25 * 1024 * 1024;

  Future<CardImageUpload?> pickImage();
}
