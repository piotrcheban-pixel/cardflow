import 'dart:typed_data';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_media_repository.dart';

/// Чтение байтов медиа по строкам `media`.
class DriftCardMediaRepository implements CardMediaRepository {
  DriftCardMediaRepository(this.database, this.mediaStore);

  final AppDatabase database;
  final MediaStore mediaStore;

  @override
  Future<Map<String, Uint8List>> readMedia(Iterable<String> mediaIds) async {
    final result = <String, Uint8List>{};
    for (final id in mediaIds) {
      if (result.containsKey(id)) continue;
      final row = await (database.select(
        database.media,
      )..where((table) => table.id.equals(id))).getSingleOrNull();
      if (row == null) continue;
      final bytes = await mediaStore.readMedia(row.path);
      if (bytes != null) result[id] = bytes;
    }
    return result;
  }
}
