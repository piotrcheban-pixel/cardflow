import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';

/// Conservative GC медиа (контракт красной фазы).
class MediaGarbageCollector {
  MediaGarbageCollector(this.database, this.mediaStore);

  final AppDatabase database;
  final MediaStore mediaStore;

  Future<int> collect() async => 0;
}
