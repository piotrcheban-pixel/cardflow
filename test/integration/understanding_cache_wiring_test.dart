import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Срез 11, часть 2, п. 7: кэш карты знаний на БД подключён к Understanding —
/// повторный прогон того же материала не делает запросов Understanding (счётчик
/// вызовов модели, а не «кажется, что работает»).
void main() {
  late AppDatabase database;
  late DriftKnowledgeMapCache cache;
  late _CountingCaller caller;

  setUp(() {
    database = AppDatabase.inMemory();
    cache = DriftKnowledgeMapCache(database);
    caller = _CountingCaller();
  });

  tearDown(() async {
    await database.close();
  });

  Document documentOf(String first, [String second = 'Вторая строка.']) {
    final String text = '$first\n$second';
    return const ContentModelBuilder().build(
      ParsedDocument(
        format: DocumentFormat.txt,
        fileName: 'лекция.txt',
        text: text,
        sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
      ),
    );
  }

  UnderstandingService service() =>
      UnderstandingService(caller: caller, cache: cache, maxOutputTokens: 1024);

  test('второй прогон того же материала не зовёт модель', () async {
    final Document document = documentOf('Первое утверждение.');
    final UnderstandingResult first = await service().build(document);

    expect(first.fromCache, isFalse);
    expect(caller.calls, 1);
    expect(first.map.units, hasLength(1));

    // Новый экземпляр сервиса — как после перезапуска приложения: кэш в БД.
    final UnderstandingResult second = await service().build(document);

    expect(second.fromCache, isTrue);
    expect(
      caller.calls,
      1,
      reason: 'повторный прогон не платит за Understanding',
    );
    expect(second.map.units, hasLength(1));
    expect(second.fragments, isEmpty);
  });

  test('другой материал — новый ключ кэша и новый запрос', () async {
    await service().build(documentOf('Первое утверждение.'));
    await service().build(documentOf('Другое утверждение.'));

    expect(caller.calls, 2);
  });
}

/// Считающий вызовы модели Understanding: одна единица с якорем на первый блок.
class _CountingCaller implements KnowledgeMapCaller {
  int calls = 0;

  @override
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request) async {
    calls++;
    final RegExpMatch? block = RegExp('<block id="([^"]+)"')
        .firstMatch(request.userContent);
    final String blockId = block?.group(1) ?? request.sectionId;
    return KnowledgeMapRawResponse(
      json: jsonEncode(<String, Object?>{
        'units': <Map<String, Object?>>[
          <String, Object?>{
            'section_id': null,
            'topic': 'тема',
            'kind': 'fact',
            'statement': 'Утверждение из материала.',
            'anchors': <Map<String, Object?>>[
              <String, Object?>{'block_id': blockId, 'quote': 'строка'},
            ],
            'salience': 0.5,
            'splittable': false,
          },
        ],
      }),
      usage: const TokenUsage(promptTokens: 10, completionTokens: 5),
    );
  }
}
