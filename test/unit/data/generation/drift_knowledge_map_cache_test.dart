// Кэш карт знаний на БД (TASK «Срез 8», п. 5): повторный запуск того же
// материала не платит за Understanding. Тест на in-memory drift + сквозная
// проверка через `UnderstandingService`: второй прогон берёт карту из кэша и не
// вызывает модель.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/knowledge_map_json.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

void main() {
  late AppDatabase db;
  late DriftKnowledgeMapCache cache;

  final DateTime fixedNow = DateTime.utc(2026, 11, 28, 11);

  setUp(() {
    db = AppDatabase.inMemory();
    cache = DriftKnowledgeMapCache(db, clock: () => fixedNow);
  });

  tearDown(() async {
    await db.close();
  });

  KnowledgeMap mapFor(String documentId) => KnowledgeMap(
    documentId: documentId,
    units: <KnowledgeUnit>[
      KnowledgeUnit(
        id: 'ku:$documentId#0',
        sectionId: 's1',
        topic: 'тема',
        kind: KnowledgeUnitKind.definition,
        statement: 'Определение ключевого понятия.',
        anchors: const <KnowledgeAnchor>[
          KnowledgeAnchor(blockId: 'b1', quote: 'Определение'),
          KnowledgeAnchor(blockId: 'b2', quote: 'понятие'),
        ],
        salience: 0.9,
        splittable: true,
      ),
    ],
  );

  group('DriftKnowledgeMapCache', () {
    test('карта переживает запись и чтение (все поля единиц)', () async {
      await cache.write(
        documentId: 'doc:конспект.docx',
        contentHash: 'hash-a',
        map: mapFor('doc:конспект.docx'),
      );

      final KnowledgeMap? restored = await cache.read(
        documentId: 'doc:конспект.docx',
        contentHash: 'hash-a',
      );

      expect(restored, isNotNull);
      expect(restored!.documentId, 'doc:конспект.docx');
      final KnowledgeUnit unit = restored.unit('ku:doc:конспект.docx#0')!;
      expect(unit.kind, KnowledgeUnitKind.definition);
      expect(unit.statement, 'Определение ключевого понятия.');
      expect(unit.salience, 0.9);
      expect(unit.splittable, isTrue);
      expect(
        unit.anchors.map((KnowledgeAnchor anchor) => anchor.blockId),
        <String>['b1', 'b2'],
      );
      expect(await cache.count(), 1);
    });

    test(
      'другой хеш содержимого — промах: правка файла даёт новую карту',
      () async {
        await cache.write(
          documentId: 'doc:конспект.docx',
          contentHash: 'hash-a',
          map: mapFor('doc:конспект.docx'),
        );

        expect(
          await cache.read(
            documentId: 'doc:конспект.docx',
            contentHash: 'hash-b',
          ),
          isNull,
        );
      },
    );

    test(
      'повторная запись того же ключа обновляет карту, а не дублирует',
      () async {
        await cache.write(
          documentId: 'doc:конспект.docx',
          contentHash: 'hash-a',
          map: mapFor('doc:конспект.docx'),
        );
        await cache.write(
          documentId: 'doc:конспект.docx',
          contentHash: 'hash-a',
          map: KnowledgeMap(
            documentId: 'doc:конспект.docx',
            units: <KnowledgeUnit>[
              KnowledgeUnit(
                id: 'ku:#0',
                sectionId: 's1',
                topic: 'тема',
                kind: KnowledgeUnitKind.fact,
                statement: 'Новая карта.',
                anchors: const <KnowledgeAnchor>[
                  KnowledgeAnchor(blockId: 'b1', quote: 'Новая'),
                ],
              ),
            ],
          ),
        );

        expect(await cache.count(), 1);
        final KnowledgeMap restored = (await cache.read(
          documentId: 'doc:конспект.docx',
          contentHash: 'hash-a',
        ))!;
        expect(restored.units.single.statement, 'Новая карта.');
      },
    );

    test('повреждённая запись — промах, а не падение прогона', () async {
      await db.customStatement(
        "INSERT INTO knowledge_maps (document_id, content_hash, map_json, "
        "created_at) VALUES ('doc:битый.pdf', 'h', '{не json', 0)",
      );

      expect(
        await cache.read(documentId: 'doc:битый.pdf', contentHash: 'h'),
        isNull,
      );

      // Перезапись исправляет запись: повреждение не залипает.
      await cache.write(
        documentId: 'doc:битый.pdf',
        contentHash: 'h',
        map: mapFor('doc:битый.pdf'),
      );
      expect(
        await cache.read(documentId: 'doc:битый.pdf', contentHash: 'h'),
        isNotNull,
      );
    });
  });

  group('JSON карты знаний', () {
    test('кодирование и разбор сохраняют карту', () {
      final KnowledgeMap map = mapFor('doc:х.md');
      final KnowledgeMap decoded = decodeKnowledgeMapJson(
        jsonDecode(encodeKnowledgeMapJsonString(map)) as Map<String, Object?>,
      );

      expect(decoded.documentId, map.documentId);
      expect(decoded.units, hasLength(1));
      expect(decoded.units.single.statement, map.units.single.statement);
      expect(decoded.units.single.anchors, map.units.single.anchors);
    });

    test('неизвестная версия и пустые якоря — FormatException', () {
      expect(
        () => decodeKnowledgeMapJson(const <String, Object?>{
          'version': 2,
          'document_id': 'doc:х.md',
          'units': <Object?>[],
        }),
        throwsA(isA<FormatException>()),
      );
      expect(
        () => decodeKnowledgeMapJson(const <String, Object?>{
          'version': 1,
          'document_id': 'doc:х.md',
          'units': <Object?>[
            <String, Object?>{
              'id': 'ku:1',
              'section_id': 's1',
              'topic': 'тема',
              'kind': 'fact',
              'statement': 'Утверждение.',
              'salience': 0.5,
              'splittable': false,
              'anchors': <Object?>[],
            },
          ],
        }),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('UnderstandingService на DB-кэше', () {
    test('второй прогон того же материала не вызывает модель', () async {
      final _CountingCaller caller = _CountingCaller();
      final UnderstandingService first = UnderstandingService(
        caller: caller,
        cache: cache,
      );
      final UnderstandingResult firstResult = await first.build(_document());

      expect(firstResult.fromCache, isFalse);
      expect(firstResult.map.units, hasLength(1));
      expect(caller.callCount, 1);

      // «Перезапуск приложения»: новый сервис, та же БД.
      final UnderstandingService second = UnderstandingService(
        caller: caller,
        cache: DriftKnowledgeMapCache(db, clock: () => fixedNow),
      );
      final UnderstandingResult secondResult = await second.build(_document());

      expect(secondResult.fromCache, isTrue);
      expect(secondResult.map.documentId, firstResult.map.documentId);
      expect(secondResult.map.units.single.id, firstResult.map.units.single.id);
      expect(caller.callCount, 1, reason: 'понимание оплачено один раз');
    });
  });
}

/// Один раздел и одна строка — блок `doc:конспект.md#0#0`.
Document _document() {
  const String text = 'Определение понятия в материале.';
  return const ContentModelBuilder().build(
    ParsedDocument(
      format: DocumentFormat.md,
      fileName: 'конспект.md',
      text: text,
      sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
    ),
  );
}

class _CountingCaller implements KnowledgeMapCaller {
  int callCount = 0;

  @override
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request) async {
    callCount++;
    final String blockId = 'doc:конспект.md#0#0';
    return KnowledgeMapRawResponse(
      json: jsonEncode(<String, Object?>{
        'units': <Object?>[
          <String, Object?>{
            'section_id': null,
            'topic': 'тема',
            'kind': 'definition',
            'statement': 'Определение понятия.',
            'anchors': <Object?>[
              <String, Object?>{'block_id': blockId, 'quote': 'Определение'},
            ],
            'salience': 0.8,
            'splittable': false,
          },
        ],
      }),
      usage: const TokenUsage(promptTokens: 10, completionTokens: 5),
    );
  }
}
