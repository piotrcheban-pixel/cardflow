import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/http_knowledge_map_caller.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/prompts/understanding_prompt.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/data/generation/in_memory_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

/// Срез 11, часть 2, п. 5–6: HTTP-реализация `KnowledgeMapCaller` поверх
/// существующих адаптеров и `RetryPolicy` — промпт `gen-map-v1`, схема карты,
/// `usage`, обрыв по `max_tokens`, повторы по 429/таймауту.
void main() {
  late FakeGenerationTransport transport;
  late FakeApiKeyStore keyStore;
  late ProviderAccount account;
  late List<Duration> delays;

  setUp(() {
    keyStore = FakeApiKeyStore(<String, String>{'deepseek': 'sk-test'});
    account = testProviderAccount(modelId: 'deepseek-chat');
    delays = <Duration>[];
  });

  Map<String, Object?> openAiResponse(
    String content, {
    String finish = 'stop',
  }) => <String, Object?>{
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, Object?>{'content': content},
        'finish_reason': finish,
      },
    ],
    'usage': <String, Object?>{
      'prompt_tokens': 100,
      'completion_tokens': 20,
      'total_tokens': 120,
    },
  };

  KnowledgeMapRequest request({int? maxOutputTokens}) => KnowledgeMapRequest(
    fragmentId: 'doc:лекция.docx#0',
    sectionId: 'doc:лекция.docx#0',
    promptVersion: understandingPromptVersion,
    systemPrompt: understandingSystemPromptGenMapV1,
    userContent: '<section id="doc:лекция.docx#0">материал</section>',
    maxOutputTokens: maxOutputTokens,
  );

  HttpKnowledgeMapCaller caller({
    RetryPolicy? retryPolicy,
    int maxOutputTokens = 512,
  }) {
    transport = FakeGenerationTransport(
      response: openAiResponse('{"units": []}'),
    );
    return HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: retryPolicy ?? RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
      maxOutputTokens: maxOutputTokens,
    );
  }

  test('строит запрос gen-map-v1 с лимитом вывода и схемой карты', () async {
    final HttpKnowledgeMapCaller mapCaller = caller(maxOutputTokens: 512);

    final KnowledgeMapRawResponse response = await mapCaller.extract(request());

    expect(transport.calls, 1);
    final ProviderRequest sent = transport.requests.single;
    expect(sent.uri.toString(), contains('/chat/completions'));
    expect(sent.headers['Authorization'], 'Bearer sk-test');
    final List<Object?> messages = sent.body['messages']! as List<Object?>;
    expect(
      (messages.first! as Map<String, Object?>)['content'],
      understandingSystemPromptGenMapV1,
    );
    expect(sent.body['max_tokens'], 512);
    final Map<String, Object?> format =
        sent.body['response_format']! as Map<String, Object?>;
    final Map<String, Object?> jsonSchema =
        format['json_schema']! as Map<String, Object?>;
    final Map<String, Object?> schema =
        jsonSchema['schema']! as Map<String, Object?>;
    final Map<String, Object?> properties =
        schema['properties']! as Map<String, Object?>;
    expect(properties.keys, contains('units'));

    expect(response.truncated, isFalse);
    expect(response.json, '{"units": []}');
    expect(response.usage.promptTokens, 100);
    expect(response.usage.completionTokens, 20);
    expect(response.usage.totalTokens, 120);
    expect(delays, isEmpty);
  });

  test('лимит вывода запроса перекрывает лимит реализации', () async {
    final HttpKnowledgeMapCaller mapCaller = caller(maxOutputTokens: 512);

    await mapCaller.extract(request(maxOutputTokens: 128));

    expect(transport.requests.single.body['max_tokens'], 128);
  });

  test(
    '400 на strict-схеме: лестница ADR-021 упрощает запрос (3 ступени)',
    () async {
      transport = FakeGenerationTransport(
        response: openAiResponse('{"units": []}'),
        errorsBeforeResponse: <Object?>[
          const GenerationException(GenerationErrorCode.badRequest),
          const GenerationException(GenerationErrorCode.badRequest),
        ],
      );
      final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
        transport: transport,
        apiKeyStore: keyStore,
        account: account,
        retryPolicy: RetryPolicy(jitter: () => 0),
        delay: (Duration duration) async => delays.add(duration),
      );

      await mapCaller.extract(request());

      expect(transport.calls, 3);
      expect(transport.requests[0].body['response_format'], isNotNull);
      expect(transport.requests[0].body['max_tokens'], 4096);
      expect(transport.requests[1].body['response_format'], isNull);
      expect(transport.requests[1].body['max_tokens'], 4096);
      expect(transport.requests[2].body['response_format'], isNull);
      expect(transport.requests[2].body['max_tokens'], isNull);
      expect(delays, isEmpty, reason: '400 — не повтор, а следующая ступень');
    },
  );

  test('нативный протокол 400 не упрощает: ошибка как есть', () async {
    final ProviderAccount native = testProviderAccount(modelId: 'gpt-4o');
    final ProviderAccount accountNative = ProviderAccount(
      id: native.id,
      label: native.label,
      presetId: native.presetId,
      protocol: ProviderProtocol.openai,
      baseUrl: native.baseUrl,
      modelId: native.modelId,
      contextTokens: native.contextTokens,
      requiresApiKey: native.requiresApiKey,
    );
    transport = FakeGenerationTransport(
      error: const GenerationException(GenerationErrorCode.badRequest),
    );
    final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: accountNative,
      retryPolicy: RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    await expectLater(
      mapCaller.extract(request()),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.badRequest,
        ),
      ),
    );
    expect(transport.calls, 1);
  });

  test('429 с Retry-After: пауза из заголовка, повтор, затем ответ', () async {
    final HttpKnowledgeMapCaller mapCaller = caller();
    transport = FakeGenerationTransport(
      response: openAiResponse('{"units": []}'),
      errorsBeforeResponse: <Object?>[
        const GenerationException(
          GenerationErrorCode.rateLimited,
          retryAfter: Duration(seconds: 7),
        ),
      ],
    );
    final HttpKnowledgeMapCaller retrying = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    final KnowledgeMapRawResponse response = await retrying.extract(request());

    expect(transport.calls, 2);
    expect(delays, <Duration>[const Duration(seconds: 7)]);
    expect(response.json, '{"units": []}');
    expect(mapCaller, isNotNull);
  });

  test('таймаут: повтор по политике, затем доменная ошибка', () async {
    transport = FakeGenerationTransport(
      error: const GenerationException(GenerationErrorCode.timeout),
    );
    final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: RetryPolicy(maxAttempts: 2, jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    await expectLater(
      mapCaller.extract(request()),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.timeout,
        ),
      ),
    );
    expect(transport.calls, 2);
    expect(delays, hasLength(1));
  });

  test('401 не повторяется: ключ/доступ — терминальная ошибка', () async {
    transport = FakeGenerationTransport(
      error: const GenerationException(GenerationErrorCode.invalidApiKey),
    );
    final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    await expectLater(
      mapCaller.extract(request()),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.invalidApiKey,
        ),
      ),
    );
    expect(transport.calls, 1);
    expect(delays, isEmpty);
  });

  test('пустой ответ модели — доменная ошибка, а не пустая карта', () async {
    transport = FakeGenerationTransport(response: openAiResponse(''));
    final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    await expectLater(
      mapCaller.extract(request()),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.emptyResponse,
        ),
      ),
    );
    expect(transport.calls, 1, reason: 'пустой ответ не повторяем');
  });

  test('битый JSON возвращается как есть: фрагмент пометит парсер', () async {
    transport = FakeGenerationTransport(
      response: openAiResponse('{"units": ['),
    );
    final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    final KnowledgeMapRawResponse response = await mapCaller.extract(request());

    expect(response.json, '{"units": [');
    expect(response.truncated, isFalse);
  });

  test('обрыв по max_tokens помечается truncated (делит сервис)', () async {
    transport = FakeGenerationTransport(
      response: openAiResponse('{"units": [', finish: 'length'),
    );
    final HttpKnowledgeMapCaller mapCaller = HttpKnowledgeMapCaller(
      transport: transport,
      apiKeyStore: keyStore,
      account: account,
      retryPolicy: RetryPolicy(jitter: () => 0),
      delay: (Duration duration) async => delays.add(duration),
    );

    final KnowledgeMapRawResponse response = await mapCaller.extract(request());

    expect(response.truncated, isTrue);
    expect(response.usage.totalTokens, 120, reason: 'usage обрыва тоже факт');
  });

  test('срез 13: проба strict-схемы один раз на прогон — 12 разделов = 13 запросов', () async {
    // 12 разделов × две ступени лестницы ADR-021 = 24 запроса (дефект S12).
    // Профиль совместимости запоминает первую 400, и каждый следующий раздел
    // идёт сразу без strict: 1 проба + 12 успешных = 13.
    final _StrictRejectingTransport strictTransport =
        _StrictRejectingTransport();
    final UnderstandingService service = UnderstandingService(
      caller: HttpKnowledgeMapCaller(
        transport: strictTransport,
        apiKeyStore: keyStore,
        account: account,
        retryPolicy: RetryPolicy(jitter: () => 0),
        delay: (Duration duration) async => delays.add(duration),
      ),
      cache: InMemoryKnowledgeMapCache(),
      maxOutputTokens: 512,
    );

    final UnderstandingResult result = await service.build(_document12());

    expect(strictTransport.calls, 13);
    expect(
      strictTransport.strictCalls,
      1,
      reason: 'strict-вариант запрошен ровно один раз за прогон',
    );
    expect(result.requests, 13, reason: 'отчёт считает запросы числом');
    expect(result.hasFailures, isFalse);
    expect(delays, isEmpty, reason: '400 — ступень лестницы, не повтор');
  });
}

/// Документ из 12 разделов по одному блоку: материал Understanding.
Document _document12() {
  final StringBuffer buffer = StringBuffer();
  final List<ParsedSection> sections = <ParsedSection>[];
  for (var index = 0; index < 12; index++) {
    if (buffer.isNotEmpty) buffer.write('\n');
    final int start = buffer.length;
    buffer.writeln('Утверждение $index: момент силы равен произведению силы.');
    sections.add(
      ParsedSection(start: start, end: buffer.length, title: 'Раздел $index'),
    );
  }
  final String text = buffer.toString();
  return ContentModelBuilder().build(
    ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'материал.txt',
      text: text,
      sections: sections,
    ),
  );
}

/// Транспорт DeepSeek-подобного сервера: strict `json_schema` — 400,
/// запрос без схемы — успешный ответ карты знаний.
class _StrictRejectingTransport implements GenerationTransport {
  int calls = 0;
  int strictCalls = 0;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    if (request.body['response_format'] != null) {
      strictCalls++;
      throw const GenerationException(GenerationErrorCode.badRequest);
    }
    return <String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'content': '{"units": []}'},
          'finish_reason': 'stop',
        },
      ],
      'usage': <String, Object?>{
        'prompt_tokens': 10,
        'completion_tokens': 5,
        'total_tokens': 15,
      },
    };
  }
}
