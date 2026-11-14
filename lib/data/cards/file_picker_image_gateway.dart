import 'package:cardflow/domain/cards/card_media.dart';

/// Системный picker изображения (контракт красной фазы).
class FilePickerImageGateway implements CardImageGateway {
  const FilePickerImageGateway();

  @override
  Future<CardImageUpload?> pickImage() async => null;
}
