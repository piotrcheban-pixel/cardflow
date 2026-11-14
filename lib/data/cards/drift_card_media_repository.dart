import 'dart:typed_data';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_media_repository.dart';

/// Чтение байтов медиа по строкам `media` (контракт красной фазы).
class DriftCardMediaRepository implements CardMediaRepository {
  DriftCardMediaRepository(this.database, this.mediaStore);

  final AppDatabase database;
  final MediaStore mediaStore;

  @override
  Future<Map<String, Uint8List>> readMedia(Iterable<String> mediaIds) async =>
      <String, Uint8List>{};
}
