import 'dart:convert';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/knowledge_map_parser.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/api/prompts/understanding_prompt.dart';
import 'package:cardflow/data/generation/in_memory_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:flutter_test/flutter_test.dart';

/// Этап Understanding (TASK «Срез 3»): последовательные вызовы по фрагментам,
/// пометка невалидного фрагмента без остановки прогона, фактический `usage`
/// вместо оценки и кэш карты (второй вызов не идёт в LLM).
void main() {
  group('UnderstandingService: успешный прогон', () {
    test(
      'вызывает модель по фрагментам по порядку и суммирует usage',
      () async {
        final _FakeCaller caller = _FakeCaller(
          (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
            json: _unitsJson(<Map<String, Object?>>[
              _unitJson(_anchorOf(request.sectionId)),
            ]),
            usage: const TokenUsage(
              promptTokens: 100,
              completionTokens: 20,
              totalTokens: 120,
            ),
          ),
        );
        final InMemoryKnowledgeMapCache cache = InMemoryKnowledgeMapCache();
        final UnderstandingService service = UnderstandingService(
          caller: caller,
          cache: cache,
        );

        final UnderstandingResult result = await service.build(_document());

        expect(caller.callCount, 2);
        expect(
          caller.requests.map(
            (KnowledgeMapRequest request) => request.sectionId,
          ),
          <String>['doc:конспект.docx#0', 'doc:конспект.docx#1'],
        );
        expect(caller.requests.first.promptVersion, understandingPromptVersion);
        expect(
          caller.requests.first.systemPrompt,
          understandingSystemPromptGenMapV1,
        );
        expect(
          caller.requests.first.userContent,
          contains('<block id="doc:конспект.docx#0#0">'),
        );

        expect(result.fragments, hasLength(2));
        expect(
          result.fragments.map(
            (KnowledgeMapFragmentOutcome outcome) => outcome.status,
          ),
          <KnowledgeMapFragmentStatus>[
            KnowledgeMapFragmentStatus.understood,
            KnowledgeMapFragmentStatus.understood,
          ],
        );
        expect(result.hasFailures, isFalse);
        expect(result.failures, isEmpty);
        expect(result.map.documentId, 'doc:конспект.docx');
        expect(result.map.units, hasLength(2));
        expect(result.fromCache, isFalse);
        expect(result.rejectedUnits, 0);

        expect(result.usage.promptTokens, 200);
        expect(result.usage.completionTokens, 40);
        expect(result.usage.totalTokens, 240);
      },
    );

    test('второй вызов берёт карту из кэша и не идёт в LLM', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
          json: _unitsJson(<Map<String, Object?>>[
            _unitJson(_anchorOf(request.sectionId)),
          ]),
          usage: const TokenUsage(promptTokens: 10, completionTokens: 2),
        ),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );
      final Document document = _document();

      final UnderstandingResult first = await service.build(document);
      final UnderstandingResult second = await service.build(document);

      expect(caller.callCount, 2, reason: 'Повторный прогон не должен звонить');
      expect(first.fromCache, isFalse);
      expect(second.fromCache, isTrue);
      expect(second.map.units, hasLength(2));
      expect(second.fragments, isEmpty);
      expect(
        second.usage.promptTokens,
        isNull,
        reason: 'Из кэша нет факта usage — оценку не подставляем',
      );
    });

    test('правка документа даёт новый ключ кэша', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
          json: _unitsJson(<Map<String, Object?>>[
            _unitJson(_anchorOf(request.sectionId)),
          ]),
        ),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );

      await service.build(_document());
      await service.build(_document(secondSection: 'Другая строка.'));

      expect(caller.callCount, 4, reason: 'Содержимое изменилось — новый ключ');
    });
  });

  group('UnderstandingService: фолбэк по фрагменту', () {
    test('битый ответ помечает фрагмент, остальные обрабатываются', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async => request.sectionId.endsWith('#0')
            ? const KnowledgeMapRawResponse(
                json: '{"units": [',
                usage: TokenUsage(promptTokens: 10),
              )
            : KnowledgeMapRawResponse(
                json: _unitsJson(<Map<String, Object?>>[
                  _unitJson(_anchorOf(request.sectionId)),
                ]),
                usage: const TokenUsage(
                  promptTokens: 10,
                  completionTokens: 5,
                  totalTokens: 15,
                ),
              ),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );
      final Document document = _document();

      final UnderstandingResult result = await service.build(document);

      expect(caller.callCount, 2);
      expect(result.hasFailures, isTrue);
      expect(result.failures, hasLength(1));
      expect(result.failures.single.fragmentId, 'doc:конспект.docx#0');
      expect(
        result.failures.single.failureReason,
        KnowledgeMapFailureReason.jsonParse,
      );
      expect(
        result.fragments.map(
          (KnowledgeMapFragmentOutcome outcome) => outcome.status,
        ),
        <KnowledgeMapFragmentStatus>[
          KnowledgeMapFragmentStatus.failed,
          KnowledgeMapFragmentStatus.understood,
        ],
      );
      expect(result.map.units, hasLength(1));
      expect(result.map.units.single.sectionId, 'doc:конспект.docx#1');

      expect(result.usage.promptTokens, 20);
      expect(
        result.usage.completionTokens,
        isNull,
        reason: 'У одного ответа нет факта — сумма неизвестна, а не 5',
      );
      expect(result.usage.totalTokens, isNull);

      await service.build(document);
      expect(
        caller.callCount,
        4,
        reason: 'Неполная карта не кэшируется — повтор снова идёт в LLM',
      );
    });

    test('сбой провайдера помечает фрагмент, прогон продолжается', () async {
      final _FakeCaller caller = _FakeCaller((
        KnowledgeMapRequest request,
      ) async {
        if (request.sectionId.endsWith('#0')) {
          throw const GenerationException(
            GenerationErrorCode.serverUnavailable,
          );
        }
        return KnowledgeMapRawResponse(
          json: _unitsJson(<Map<String, Object?>>[
            _unitJson(_anchorOf(request.sectionId)),
          ]),
        );
      });
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );

      final UnderstandingResult result = await service.build(_document());

      expect(caller.callCount, 2);
      expect(result.hasFailures, isTrue);
      expect(
        result.failures.single.failureReason,
        KnowledgeMapFailureReason.providerError,
      );
      expect(result.map.units, hasLength(1));
    });

    test('обрезанный ответ — невалидный фрагмент', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
          json: request.sectionId.endsWith('#0')
              ? '{"units": []}'
              : _unitsJson(<Map<String, Object?>>[
                  _unitJson(_anchorOf(request.sectionId)),
                ]),
          truncated: request.sectionId.endsWith('#0'),
        ),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );

      final UnderstandingResult result = await service.build(_document());

      expect(result.hasFailures, isTrue);
      expect(
        result.failures.single.failureReason,
        KnowledgeMapFailureReason.truncated,
      );
      expect(result.map.units, hasLength(1));
    });

    test(
      'отмена пробрасывается наружу, а не «продолжается без фрагмента»',
      () async {
        final _FakeCaller caller = _FakeCaller(
          (KnowledgeMapRequest request) async =>
              throw const GenerationException(GenerationErrorCode.cancelled),
        );
        final UnderstandingService service = UnderstandingService(
          caller: caller,
          cache: InMemoryKnowledgeMapCache(),
        );

        await expectLater(
          service.build(_document()),
          throwsA(
            isA<GenerationException>().having(
              (GenerationException error) => error.code,
              'code',
              GenerationErrorCode.cancelled,
            ),
          ),
        );
        expect(caller.callCount, 1);
      },
    );
  });

  group('UnderstandingService: пустые ответы и пустые разделы', () {
    test('пустой список единиц — валидный пустой фрагмент', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
          json: request.sectionId.endsWith('#0')
              ? _unitsJson(<Map<String, Object?>>[])
              : _unitsJson(<Map<String, Object?>>[
                  _unitJson(_anchorOf(request.sectionId)),
                ]),
        ),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );

      final UnderstandingResult result = await service.build(_document());

      expect(result.hasFailures, isFalse);
      expect(
        result.fragments.map(
          (KnowledgeMapFragmentOutcome outcome) => outcome.status,
        ),
        <KnowledgeMapFragmentStatus>[
          KnowledgeMapFragmentStatus.empty,
          KnowledgeMapFragmentStatus.understood,
        ],
      );
      expect(result.map.units, hasLength(1));
    });

    test('раздел без содержательных блоков не отправляется', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
          json: _unitsJson(<Map<String, Object?>>[
            _unitJson(_anchorOf(request.sectionId)),
          ]),
        ),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );

      final UnderstandingResult result = await service.build(
        _document(secondSection: '12'),
      );

      expect(
        caller.callCount,
        1,
        reason: 'Номер страницы — мусор, не материал',
      );
      expect(result.fragments, hasLength(1));
      expect(result.hasFailures, isFalse);
    });

    test('пустой документ — без запросов, кэша и usage', () async {
      final _FakeCaller caller = _FakeCaller(
        (KnowledgeMapRequest request) async =>
            const KnowledgeMapRawResponse(json: '{"units": []}'),
      );
      final UnderstandingService service = UnderstandingService(
        caller: caller,
        cache: InMemoryKnowledgeMapCache(),
      );

      final UnderstandingResult result = await service.build(
        Document.empty(fileName: 'скан.pdf'),
      );

      expect(caller.callCount, 0);
      expect(result.map.isEmpty, isTrue);
      expect(result.fragments, isEmpty);
      expect(result.hasFailures, isFalse);
      expect(result.usage.promptTokens, isNull);
      expect(result.usage.completionTokens, isNull);

      await service.build(Document.empty(fileName: 'скан.pdf'));
      expect(caller.callCount, 0);
    });

    test(
      'частично невалидные единицы считаются, валидные принимаются',
      () async {
        final _FakeCaller caller = _FakeCaller(
          (KnowledgeMapRequest request) async => KnowledgeMapRawResponse(
            json: _unitsJson(<Map<String, Object?>>[
              _unitJson(_anchorOf(request.sectionId), statement: 'Хорошее.'),
              _unitJson(_anchorOf(request.sectionId), salience: 2),
            ]),
          ),
        );
        final UnderstandingService service = UnderstandingService(
          caller: caller,
          cache: InMemoryKnowledgeMapCache(),
        );

        final UnderstandingResult result = await service.build(_document());

        expect(result.hasFailures, isFalse);
        expect(result.rejectedUnits, 2);
        expect(result.map.units, hasLength(2));
      },
    );
  });
}

class _FakeCaller implements KnowledgeMapCaller {
  _FakeCaller(this._onExtract);

  final Future<KnowledgeMapRawResponse> Function(KnowledgeMapRequest request)
  _onExtract;
  final List<KnowledgeMapRequest> requests = <KnowledgeMapRequest>[];

  int get callCount => requests.length;

  @override
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request) {
    requests.add(request);
    return _onExtract(request);
  }
}

/// Два раздела: в первом две строки, во втором одна.
Document _document({String secondSection = 'Третья строка.'}) {
  final StringBuffer buffer = StringBuffer();
  final List<ParsedSection> sections = <ParsedSection>[];
  for (final String sectionText in <String>[
    'Первая строка.\nВторая строка.',
    secondSection,
  ]) {
    if (buffer.isNotEmpty) buffer.write('\n\n');
    final int start = buffer.length;
    buffer.write(sectionText);
    sections.add(ParsedSection(start: start, end: buffer.length));
  }
  return const ContentModelBuilder().build(
    ParsedDocument(
      format: DocumentFormat.docx,
      fileName: 'конспект.docx',
      text: buffer.toString(),
      sections: sections,
    ),
  );
}

String _anchorOf(String sectionId) => sectionId.endsWith('#0')
    ? 'doc:конспект.docx#0#0'
    : 'doc:конспект.docx#1#0';

Map<String, Object?> _unitJson(
  String blockId, {
  String statement = 'Утверждение из материала.',
  num salience = 0.5,
}) => <String, Object?>{
  'section_id': null,
  'topic': 'тема',
  'kind': 'fact',
  'statement': statement,
  'anchors': <Map<String, Object?>>[
    <String, Object?>{'block_id': blockId, 'quote': 'строка материала'},
  ],
  'salience': salience,
  'splittable': false,
};

String _unitsJson(List<Map<String, Object?>> units) =>
    jsonEncode(<String, Object?>{'units': units});
