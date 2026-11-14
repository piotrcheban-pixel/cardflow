import 'dart:convert';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';

/// Удаляет только доказанно несвязанные медиа (ADR-017).
class MediaGarbageCollector {
  MediaGarbageCollector(this.database, this.mediaStore);

  final AppDatabase database;
  final MediaStore mediaStore;

  Future<int> collect() async {
    var deleted = 0;
    final retainedPaths = <String>{};
    await database.transaction(() async {
      final cards = await database.select(database.cards).get();
      final cardIds = <String>{for (final card in cards) card.id};
      final referencedMedia = <String>{};
      for (final card in cards) {
        try {
          final ids = jsonDecode(card.mediaJson);
          if (ids is List) {
            referencedMedia.addAll(ids.whereType<String>());
          }
        } on FormatException {
          // Битая карточка не должна привести к удалению её возможных медиа:
          // строки этой карточки сохраняются по cardId ниже.
        }
      }
      final rows = await database.select(database.media).get();
      for (final row in rows) {
        final linked =
            cardIds.contains(row.cardId) &&
            (referencedMedia.contains(row.id) || !_validJsonFor(cards, row));
        if (linked) {
          retainedPaths.add(row.path);
          continue;
        }
        await (database.delete(
          database.media,
        )..where((table) => table.id.equals(row.id))).go();
        deleted++;
      }
    });
    for (final path in await mediaStore.listMedia()) {
      if (retainedPaths.contains(path)) continue;
      await mediaStore.deleteMedia(path);
      deleted++;
    }
    return deleted;
  }

  bool _validJsonFor(List<CardRow> cards, MediaRow row) {
    for (final card in cards) {
      if (card.id != row.cardId) continue;
      try {
        jsonDecode(card.mediaJson);
        return true;
      } on FormatException {
        return false;
      }
    }
    return true;
  }
}
