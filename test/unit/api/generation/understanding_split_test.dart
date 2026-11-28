import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/knowledge_map_parser.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/data/generation/in_memory_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Срез 11, п. 5: обрыв ответа Understanding по `max_tokens` не теряет весь
/// раздел — блоки делятся на части по лимиту вывода (целыми блоками, а не
/// пополам), каждая часть запрашивается отдельно; повторный обрыв части —
/// прежний фолбэк среза 3 (фрагмент помечен, прогон продолжается).
void main() {
  /// Один раздел из [lines] строк: каждая строка — отдельный блок.
  Document documentOf(int lines) {
    final String text = <String>[
      for (var index = 0; index < lines; index++)
        'Утверждение $index: момент силы равен произведению силы на плечо.',
    ].join('\n');
    return const ContentModelBuilder().build(
      ParsedDocument(
        format: DocumentFormat.docx,
        fileName: 'конспект.docx',
        text: text,
        sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
      ),
    );
  }

  test('обрезанный ответ делится по блокам в пределах max_tokens', () async {
    final _SplittingCaller caller = _SplittingCaller();
    final UnderstandingService service = UnderstandingService(
      caller: caller,
      cache: InMemoryKnowledgeMapCache(),
      // 192 / 96 = 2 блока на часть: 4 блока → две части.
      maxOutputTokens: 192,
    );

    final UnderstandingResult result = await service.build(documentOf(4));

    expect(caller.requests, hasLength(3), reason: 'целиком + две части');
    expect(caller.requests.first.maxOutputTokens, 192);
    expect(caller.requests.first.fragmentId, 'doc:конспект.docx#0');
    expect(caller.requests[1].fragmentId, 'doc:конспект.docx#0#1');
    expect(caller.requests[2].fragmentId, 'doc:конспект.docx#0#2');
    expect(
      caller.requests[1].userContent,
      isNot(equals(caller.requests[2].userContent)),
      reason: 'части — разные блоки, а не половина символов',
    );

    expect(result.hasFailures, isFalse);
    expect(result.fragments, hasLength(1));
    expect(result.fragments.single.unitCount, 2);
    expect(result.map.units, hasLength(2));
    expect(
      result.usage.totalTokens,
      300,
      reason: 'usage обрыва и частей суммируется, а не теряется',
    );
  });

  test(
    'обрыв части с одним блоком — прежний фолбэк: фрагмент помечен',
    () async {
      final _AlwaysTruncatedCaller caller = _AlwaysTruncatedCaller();
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
        maxOutputTokens: 192,
      );

      final UnderstandingResult result = await service.build(documentOf(1));

      expect(caller.calls, 1, reason: 'один блок делить не на что');
      expect(result.hasFailures, isTrue);
      expect(
        result.failures.single.failureReason,
        KnowledgeMapFailureReason.truncated,
      );
      expect(result.map.units, isEmpty);
    },
  );

  test('предел вывода по умолчанию не делит обычный раздел', () async {
    final _SplittingCaller caller = _SplittingCaller();
    final UnderstandingService service = UnderstandingService(
      caller: caller,
      cache: InMemoryKnowledgeMapCache(),
    );

    await service.build(documentOf(4));

    expect(blocksPerMapRequest(kDefaultMapOutputTokens), 42);
    expect(caller.requests, hasLength(1));
  });
}

/// Портит первый ответ (`truncated`), затем отдаёт по одной единице на часть.
class _SplittingCaller implements KnowledgeMapCaller {
  final List<KnowledgeMapRequest> requests = <KnowledgeMapRequest>[];

  @override
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request) async {
    requests.add(request);
    if (requests.length == 1) {
      return KnowledgeMapRawResponse(
        json: '{"units": [',
        usage: const TokenUsage(
          promptTokens: 50,
          completionTokens: 10,
          totalTokens: 60,
        ),
        truncated: true,
      );
    }
    final String firstBlockId = _blockIdsOf(request.userContent).first;
    return KnowledgeMapRawResponse(
      json: _unitsJson(<Map<String, Object?>>[_unitJson(firstBlockId)]),
      usage: const TokenUsage(
        promptTokens: 100,
        completionTokens: 20,
        totalTokens: 120,
      ),
    );
  }
}

/// Всегда обрывает ответ: фолбэк среза 3 должен пометить фрагмент.
class _AlwaysTruncatedCaller implements KnowledgeMapCaller {
  int calls = 0;

  @override
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request) async {
    calls++;
    return const KnowledgeMapRawResponse(json: '{"units": [', truncated: true);
  }
}

List<String> _blockIdsOf(String userContent) => <String>[
  for (final RegExpMatch match in RegExp(
    '<block id="([^"]+)"',
  ).allMatches(userContent))
    match.group(1)!,
];

Map<String, Object?> _unitJson(String blockId) => <String, Object?>{
  'section_id': null,
  'topic': 'тема',
  'kind': 'fact',
  'statement': 'Утверждение из материала.',
  'anchors': <Map<String, Object?>>[
    <String, Object?>{'block_id': blockId, 'quote': 'строка материала'},
  ],
  'salience': 0.5,
  'splittable': false,
};

String _unitsJson(List<Map<String, Object?>> units) =>
    jsonEncode(<String, Object?>{'units': units});
