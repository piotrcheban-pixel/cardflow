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
      final referencedByCard = <String, Set<String>>{};
      final malformedCards = <String>{};
      for (final card in cards) {
        try {
          final ids = jsonDecode(card.mediaJson);
          if (ids is List) {
            referencedByCard[card.id] = ids.whereType<String>().toSet();
          } else {
            malformedCards.add(card.id);
          }
        } on FormatException {
          // Битая карточка не должна привести к удалению её возможных медиа.
          malformedCards.add(card.id);
        }
      }
      final rows = await database.select(database.media).get();
      for (final row in rows) {
        final linked =
            malformedCards.contains(row.cardId) ||
            (referencedByCard[row.cardId]?.contains(row.id) ?? false);
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
}
