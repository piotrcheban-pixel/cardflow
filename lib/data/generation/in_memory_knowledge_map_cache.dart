/// In-memory реализация порта `KnowledgeMapCache` (TASK «Срез 3»).
///
/// Миграция БД — срез 7: до неё карта живёт в памяти процесса, а ключ —
/// документ + хеш содержимого (правка файла даёт новый ключ). Слой данных:
/// порт объявлен в домене (`lib/domain/generation/ports.dart`), реализация —
/// здесь, чтобы этап понимания не зависел от хранилища.
library;

import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/ports.dart';

/// Кэш карт знаний в памяти процесса.
class InMemoryKnowledgeMapCache implements KnowledgeMapCache<KnowledgeMap> {
  final Map<String, KnowledgeMap> _entries = <String, KnowledgeMap>{};

  /// Сколько карт в кэше (диагностика/тесты).
  int get length => _entries.length;

  @override
  Future<KnowledgeMap?> read({
    required String documentId,
    required String contentHash,
  }) async => _entries[_key(documentId, contentHash)];

  @override
  Future<void> write({
    required String documentId,
    required String contentHash,
    required KnowledgeMap map,
  }) async {
    _entries[_key(documentId, contentHash)] = map;
  }

  /// Очищает кэш.
  void clear() => _entries.clear();

  /// Ключ кэша: документ и хеш содержимого не могут смешаться.
  static String _key(String documentId, String contentHash) =>
      '$documentId\u0000$contentHash';
}
