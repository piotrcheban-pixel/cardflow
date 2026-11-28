import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_batch_port.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Срез 5, п. 1: `LlmPort` реализуется поверх **существующих** адаптеров.
/// Срез 18: порт строит запрос **дефолтным** промптом `gen-cards-v4` (единицы
/// с якорями), отправляет его существующим транспортом и нормализует ответ
/// адаптера: карточки с `unit_id`/`angle`/`quote_ref`; отказ/ошибка —
/// `GenerationException` для движка; обрезанный ответ — спасённые полные
/// карточки.
void main() {
  const ProviderAccount account = ProviderAccount(
    id: 'acc-1',
    label: 'DeepSeek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.test/v1',
    modelId: 'deepseek-chat',
  );

  test(
    'запрос: дефолтный промпт gen-cards-v4, единицы с якорями и v3-схема',
    () async {
      final _FakeTransport transport = _FakeTransport.success(
        _openAiResponse(<Map<String, Object?>>[_card()]),
      );
      final AdapterCardsBatchPort port = _port(transport);

      await port.generate(_batch(), account: account);

      final ProviderRequest request = transport.requests.single;
      expect(request.uri.toString(), contains('/chat/completions'));
      final List<Object?> messages = request.body['messages']! as List<Object?>;
      final Map<String, Object?> system =
          messages.first! as Map<String, Object?>;
      expect(system['content'], cardsSystemPrompt);
      expect(system['content'], cardsSystemPromptGenCardsV4);
      final Map<String, Object?> user = messages.last! as Map<String, Object?>;
      final String userContent = user['content']! as String;
      expect(userContent, contains('<unit id="ku:A"'));
      expect(userContent, contains('<budget cards="2">'));

      final Map<String, Object?> responseFormat =
          request.body['response_format']! as Map<String, Object?>;
      final Map<String, Object?> jsonSchema =
          responseFormat['json_schema']! as Map<String, Object?>;
      final Map<String, Object?> schema =
          jsonSchema['schema']! as Map<String, Object?>;
      final Map<String, Object?> properties =
          schema['properties']! as Map<String, Object?>;
      final Map<String, Object?> cards =
          properties['cards']! as Map<String, Object?>;
      final Map<String, Object?> items =
          cards['items']! as Map<String, Object?>;
      final Map<String, Object?> cardProperties =
          items['properties']! as Map<String, Object?>;
      expect(cardProperties, contains('unit_id'));
      expect(cardProperties, contains('angle'));
      expect(cardProperties, contains('quote_ref'));
      expect(
        items['required'],
        containsAll(<String>['unit_id', 'angle', 'quote_ref']),
      );
    },
  );

  test('ответ: карточки с unit_id/angle/quote_ref и фактом расхода', () async {
    final List<Map<String, Object?>> cards = <Map<String, Object?>>[
      _card(),
      _card(angle: 'cloze'),
    ];
    final AdapterCardsBatchPort port = _port(
      _FakeTransport.success(_openAiResponse(cards)),
    );

    final GenerationResult result = await port.generate(
      _batch(),
      account: account,
    );

    expect(result.provider, account.protocol.adapterProvider);
    expect(result.model, 'deepseek-chat');
    expect(result.promptVersion, 'gen-cards-v4');
    expect(result.cards.length, 2);
    expect(result.rejectedCards, 0);
    expect(result.truncated, isFalse);
    final GeneratedCard primary = result.cards.first;
    expect(primary.unitId, 'ku:A');
    expect(primary.angle, isNull, reason: 'primary — основная карточка');
    expect(primary.quoteRef, 'Цитата материала A.');
    expect(primary.cardType, CardType.basic);
    expect(result.cards.last.angle, 'cloze');
    expect(result.usage.promptTokens, 10);
    expect(result.usage.completionTokens, 5);
  });

  test('карточка без unit_id/quote_ref отбрасывается поштучно', () async {
    final List<Map<String, Object?>> cards = <Map<String, Object?>>[
      _card(),
      _card(unitId: '', quoteRef: ''),
    ];
    final AdapterCardsBatchPort port = _port(
      _FakeTransport.success(_openAiResponse(cards)),
    );

    final GenerationResult result = await port.generate(
      _batch(),
      account: account,
    );

    expect(result.cards.length, 1);
    expect(result.rejectedCards, 1);
  });

  test('неизвестный угол отбрасывает карточку, остальные остаются', () async {
    final List<Map<String, Object?>> cards = <Map<String, Object?>>[
      _card(),
      _card(angle: 'definition'),
    ];
    final AdapterCardsBatchPort port = _port(
      _FakeTransport.success(_openAiResponse(cards)),
    );

    final GenerationResult result = await port.generate(
      _batch(),
      account: account,
    );

    expect(result.cards.length, 1);
    expect(result.rejectedCards, 1);
  });

  test('обрезанный ответ: спасённые полные карточки, truncated', () async {
    const String truncatedBody =
        '{"cards":['
        '{"front":"Q1","back":"A1","hint":null,"tags":[],'
        '"card_type":"basic","source_excerpt":null,"source_file":null,'
        '"section_id":null,"question_image_ids":[],"answer_image_ids":[],'
        '"image":null,"unit_id":"ku:A","angle":"primary",'
        '"quote_ref":"Цитата материала A."},'
        '{"front":"Q2","back":"A2","hint":null,"tags":[],'
        '"card_type":"basic","source_excerpt":null,"source_file":null,'
        '"section_id":null,"question_image_ids":[],"answer_image_ids":[],'
        '"image":null,"unit_id":"ku:A","angle":"clo';
    final AdapterCardsBatchPort port = _port(
      _FakeTransport.success(
        _openAiResponseRaw(truncatedBody, finishReason: 'length'),
      ),
    );

    final GenerationResult result = await port.generate(
      _batch(),
      account: account,
    );

    expect(result.truncated, isTrue);
    expect(result.cards.length, 1);
    expect(result.salvagedCards, 1);
    expect(result.cards.single.front, 'Q1');
  });

  test(
    '400 на strict-схеме: лестница ADR-021 (3 ступени), затем карточки',
    () async {
      var calls = 0;
      final _FakeTransport transport = _FakeTransport((
        ProviderRequest request,
      ) {
        calls++;
        if (calls < 3) {
          throw const GenerationException(GenerationErrorCode.badRequest);
        }
        return _openAiResponse(<Map<String, Object?>>[_card()]);
      });
      final AdapterCardsBatchPort port = _port(transport);

      final GenerationResult result = await port.generate(
        _batch(),
        account: account,
      );

      expect(result.cards, hasLength(1));
      expect(transport.requests, hasLength(3));
      expect(transport.requests[0].body['response_format'], isNotNull);
      expect(transport.requests[0].body['max_tokens'], isNotNull);
      expect(transport.requests[1].body['response_format'], isNull);
      expect(transport.requests[1].body['max_tokens'], isNotNull);
      expect(transport.requests[2].body['response_format'], isNull);
      expect(transport.requests[2].body['max_tokens'], isNull);
    },
  );

  test(
    'срез 13: проба strict-схемы один раз на прогон — 10 батчей = 11 запросов',
    () async {
      final _FakeTransport transport = _FakeTransport((
        ProviderRequest request,
      ) {
        if (request.body['response_format'] != null) {
          throw const GenerationException(GenerationErrorCode.badRequest);
        }
        return _openAiResponse(<Map<String, Object?>>[_card()]);
      });
      final AdapterCardsBatchPort port = _port(transport);

      for (var index = 0; index < 10; index++) {
        await port.generate(_batch(), account: account);
      }

      expect(
        transport.requests,
        hasLength(11),
        reason: '1 проба strict + 10 ответов без схемы, а не 20 запросов',
      );
      expect(
        transport.requests.where(
          (ProviderRequest request) => request.body['response_format'] != null,
        ),
        hasLength(1),
        reason: 'strict-вариант запрошен ровно один раз за прогон',
      );
    },
  );

  test(
    'ответ без choices — GenerationException(invalidResponse), а не пусто',
    () async {
      final AdapterCardsBatchPort port = _port(
        _FakeTransport.success(<String, Object?>{'error': 'nope'}),
      );

      expect(
        () => port.generate(_batch(), account: account),
        throwsA(
          isA<GenerationException>().having(
            (GenerationException error) => error.code,
            'code',
            GenerationErrorCode.invalidResponse,
          ),
        ),
      );
    },
  );
}

AdapterCardsBatchPort _port(GenerationTransport transport) =>
    AdapterCardsBatchPort(
      transport: transport,
      apiKeyStore: _MemoryKeyStore(),
      adapters: const <GenerationProviderAdapter>[OpenAiCompatibleAdapter()],
    );

CardsBatch _batch() => CardsBatch(
  index: 0,
  units: <KnowledgeUnit>[_unit()],
  cards: const <AllocatedCard>[
    AllocatedCard(unitId: 'ku:A'),
    AllocatedCard(unitId: 'ku:A', angle: AllocationAngle.cloze),
  ],
);

KnowledgeUnit _unit() => KnowledgeUnit(
  id: 'ku:A',
  sectionId: 'doc:материал.md#0',
  topic: 'момент силы',
  kind: KnowledgeUnitKind.definition,
  statement: 'Моментом силы называют произведение силы на плечо.',
  anchors: const <KnowledgeAnchor>[
    KnowledgeAnchor(
      blockId: 'doc:материал.md#0#0',
      quote: 'Цитата материала A.',
    ),
  ],
);

Map<String, Object?> _card({
  String unitId = 'ku:A',
  String angle = 'primary',
  String quoteRef = 'Цитата материала A.',
}) => <String, Object?>{
  'front': 'Что такое момент силы?',
  'back': 'Произведение силы на плечо.',
  'hint': null,
  'tags': <Object?>['физика'],
  'card_type': 'basic',
  'source_excerpt': 'Цитата материала A.',
  'source_file': 'материал.md',
  'section_id': 'doc:материал.md#0',
  'question_image_ids': <Object?>[],
  'answer_image_ids': <Object?>[],
  'image': null,
  'unit_id': unitId,
  'angle': angle,
  'quote_ref': quoteRef,
};

Map<String, Object?> _openAiResponse(List<Map<String, Object?>> cards) =>
    _openAiResponseRaw(
      jsonEncode(<String, Object?>{'cards': cards, 'source_exhausted': false}),
    );

Map<String, Object?> _openAiResponseRaw(
  String content, {
  String finishReason = 'stop',
}) => <String, Object?>{
  'choices': <Object?>[
    <String, Object?>{
      'message': <String, Object?>{'content': content},
      'finish_reason': finishReason,
    },
  ],
  'usage': <String, Object?>{
    'prompt_tokens': 10,
    'completion_tokens': 5,
    'total_tokens': 15,
  },
};

class _FakeTransport implements GenerationTransport {
  _FakeTransport(this._response);

  factory _FakeTransport.success(Map<String, Object?> response) =>
      _FakeTransport((ProviderRequest request) => response);

  final Map<String, Object?> Function(ProviderRequest request) _response;
  final List<ProviderRequest> requests = <ProviderRequest>[];

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    return _response(request);
  }
}

class _MemoryKeyStore implements ApiKeyStore {
  final Map<String, String> keys = <String, String>{'acc-1': 'test-key'};

  @override
  Future<String?> read(String providerId) async => keys[providerId];

  @override
  Future<void> write(String providerId, String apiKey) async {
    keys[providerId] = apiKey;
  }

  @override
  Future<void> delete(String providerId) async {
    keys.remove(providerId);
  }
}
