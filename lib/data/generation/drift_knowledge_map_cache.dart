/// Кэш карт знаний на drift (TASK «Срез 8»: повторный материал не платит за
/// Understanding).
///
/// Порт `KnowledgeMapCache` объявлен в домене (`ports.dart`); до среза 8 карта
/// жила только в памяти процесса (`in_memory_knowledge_map_cache.dart`), поэтому
/// после перезапуска приложения Understanding оплачивался заново. Здесь кэш
/// лежит в `knowledge_maps`: ключ — документ и хеш содержимого (правка файла
/// даёт новый ключ), значение — JSON v1 (`knowledge_map_json.dart`).
///
/// Повреждённая строка кэша не роняет прогон: она считается промахом
/// (`null`), и понимание пересчитывается — кэш обязан ускорять, а не мешать.
library;

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/knowledge_map_json.dart';
import 'package:cardflow/domain/generation/ports.dart';

/// Кэш карт знаний поверх drift-БД.
class DriftKnowledgeMapCache implements KnowledgeMapCache<KnowledgeMap> {
  /// Создаёт кэш поверх БД; [clock] — для детерминированных тестов записи.
  DriftKnowledgeMapCache(this.database, {DateTime Function()? clock})
    : _clock = clock ?? DateTime.now;

  /// БД приложения.
  final AppDatabase database;

  final DateTime Function() _clock;

  @override
  Future<KnowledgeMap?> read({
    required String documentId,
    required String contentHash,
  }) async {
    final KnowledgeMapRow? row =
        await (database.select(database.knowledgeMaps)..where(
              (table) =>
                  table.documentId.equals(documentId) &
                  table.contentHash.equals(contentHash),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    try {
      return decodeKnowledgeMapJsonString(row.mapJson);
    } on FormatException {
      // Повреждённая запись — промах: понимание пересчитается и перезапишет её.
      return null;
    }
  }

  @override
  Future<void> write({
    required String documentId,
    required String contentHash,
    required KnowledgeMap map,
  }) async {
    await database
        .into(database.knowledgeMaps)
        .insertOnConflictUpdate(
          KnowledgeMapsCompanion.insert(
            documentId: documentId,
            contentHash: contentHash,
            mapJson: encodeKnowledgeMapJsonString(map),
            createdAt: toEpochMs(_clock().toUtc()),
          ),
        );
  }

  /// Сколько карт в кэше (диагностика/тесты).
  Future<int> count() async {
    final List<KnowledgeMapRow> rows = await database
        .select(database.knowledgeMaps)
        .get();
    return rows.length;
  }
}
