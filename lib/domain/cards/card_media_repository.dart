import 'dart:typed_data';

import 'package:cardflow/domain/cards/media_metadata.dart';

/// Чтение медиа карточек для сессий (без доступа UI к drift).
abstract interface class CardMediaRepository {
  /// Байты медиа по `media.id`.
  Future<Map<String, Uint8List>> readMedia(Iterable<String> mediaIds);

  /// Метаданные атрибуции по `media.id` (провайдер, автор, лицензия, заглушка).
  Future<Map<String, MediaMetadata>> readMetadata(Iterable<String> mediaIds);
}
