import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'package:cardflow/domain/cards/card_media.dart';

/// Системный picker одного PNG/JPEG через `file_picker` (ADR-017).
class FilePickerImageGateway implements CardImageGateway {
  const FilePickerImageGateway();

  @override
  Future<CardImageUpload?> pickImage() async {
    final files = await FilePicker.pickFiles(type: FileType.image);
    if (files.isEmpty) return null;
    final file = files.single;
    final knownSize = file.lengthSync() ?? await file.length();
    if (knownSize != null && knownSize > CardImageGateway.maxImageBytes) {
      throw StateError('Изображение больше 25 МБ');
    }
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw StateError('Не удалось прочитать изображение');
    }
    if (bytes.length > CardImageGateway.maxImageBytes) {
      throw StateError('Изображение больше 25 МБ');
    }
    final lowerName = file.name.toLowerCase();
    final mimeType = lowerName.endsWith('.png')
        ? 'image/png'
        : lowerName.endsWith('.jpg') || lowerName.endsWith('.jpeg')
        ? 'image/jpeg'
        : null;
    if (mimeType == null) {
      throw const FormatException('Поддерживаются только PNG и JPEG');
    }
    return CardImageUpload(
      fileName: file.name,
      mimeType: mimeType,
      bytes: bytes,
    );
  }
}
