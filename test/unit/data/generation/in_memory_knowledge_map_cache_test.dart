import 'package:cardflow/data/generation/in_memory_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory реализация порта `KnowledgeMapCache` (TASK «Срез 3»; миграция БД
/// — срез 7). Ключ — документ + хеш содержимого: правка файла даёт новый ключ.
void main() {
  group('InMemoryKnowledgeMapCache', () {
    test('пустой кэш возвращает null', () async {
      final InMemoryKnowledgeMapCache cache = InMemoryKnowledgeMapCache();

      expect(
        await cache.read(documentId: 'doc:файл.md', contentHash: 'h1'),
        isNull,
      );
      expect(cache.length, 0);
    });

    test('пишет и читает ту же карту по ключу документа и хеша', () async {
      final InMemoryKnowledgeMapCache cache = InMemoryKnowledgeMapCache();
      final KnowledgeMap map = KnowledgeMap(
        documentId: 'doc:файл.md',
        units: <KnowledgeUnit>[_unit()],
      );

      await cache.write(documentId: 'doc:файл.md', contentHash: 'h1', map: map);

      expect(
        identical(
          await cache.read(documentId: 'doc:файл.md', contentHash: 'h1'),
          map,
        ),
        isTrue,
      );
      expect(cache.length, 1);
    });

    test('другой хеш или документ — другой ключ', () async {
      final InMemoryKnowledgeMapCache cache = InMemoryKnowledgeMapCache();
      await cache.write(
        documentId: 'doc:файл.md',
        contentHash: 'h1',
        map: KnowledgeMap(documentId: 'doc:файл.md'),
      );

      expect(
        await cache.read(documentId: 'doc:файл.md', contentHash: 'h2'),
        isNull,
      );
      expect(
        await cache.read(documentId: 'doc:другой.md', contentHash: 'h1'),
        isNull,
      );
    });

    test('повторная запись заменяет карту и не плодит ключи', () async {
      final InMemoryKnowledgeMapCache cache = InMemoryKnowledgeMapCache();
      final KnowledgeMap first = KnowledgeMap(documentId: 'doc:файл.md');
      final KnowledgeMap second = KnowledgeMap(
        documentId: 'doc:файл.md',
        units: <KnowledgeUnit>[_unit()],
      );

      await cache.write(
        documentId: 'doc:файл.md',
        contentHash: 'h1',
        map: first,
      );
      await cache.write(
        documentId: 'doc:файл.md',
        contentHash: 'h1',
        map: second,
      );

      expect(cache.length, 1);
      expect(
        identical(
          await cache.read(documentId: 'doc:файл.md', contentHash: 'h1'),
          second,
        ),
        isTrue,
      );
    });

    test('clear очищает кэш', () async {
      final InMemoryKnowledgeMapCache cache = InMemoryKnowledgeMapCache();
      await cache.write(
        documentId: 'doc:файл.md',
        contentHash: 'h1',
        map: KnowledgeMap(documentId: 'doc:файл.md'),
      );

      cache.clear();

      expect(cache.length, 0);
      expect(
        await cache.read(documentId: 'doc:файл.md', contentHash: 'h1'),
        isNull,
      );
    });
  });
}

KnowledgeUnit _unit() => KnowledgeUnit(
  id: 'ku:doc:файл.md#0#0',
  sectionId: 'doc:файл.md#0',
  topic: 'тема',
  kind: KnowledgeUnitKind.fact,
  statement: 'Утверждение.',
  anchors: const <KnowledgeAnchor>[
    KnowledgeAnchor(blockId: 'doc:файл.md#0#0', quote: 'цитата'),
  ],
  salience: 0.5,
  splittable: false,
);
