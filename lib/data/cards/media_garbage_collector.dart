import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';

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
        // 7.19: `media_json` v2 (стороны) и legacy-массив поддерживаются одним
        // разбором; битая карточка не должна привести к удалению её медиа.
        final CardMediaSides? sides = CardMediaSides.tryDecode(card.mediaJson);
        if (sides == null) {
          malformedCards.add(card.id);
        } else {
          referencedByCard[card.id] = sides.all.toSet();
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
    // Побочные метаданные без живого медиафайла: удаляем вместе с базой.
    for (final path in await mediaStore.listMetadata()) {
      final String mediaPath = path.substring(
        0,
        path.length - MediaStore.metadataSuffix.length,
      );
      if (retainedPaths.contains(mediaPath)) continue;
      await mediaStore.deleteMedia(mediaPath);
      deleted++;
    }
    return deleted;
  }
}
