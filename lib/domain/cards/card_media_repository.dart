import 'dart:typed_data';

/// Чтение медиа карточек для сессий (без доступа UI к drift).
abstract interface class CardMediaRepository {
  Future<Map<String, Uint8List>> readMedia(Iterable<String> mediaIds);
}
