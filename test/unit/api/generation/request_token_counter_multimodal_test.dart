import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/exact_token_cache.dart';
import 'package:cardflow/api/generation/request_token_counter.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Итерация 7.18.3: нативный `count_tokens` видит **тот же** мультимодальный
/// материал, что уходит в production-запрос.
///
/// Документация: Anthropic `messages/count_tokens` принимает images/documents
/// только как base64-блоки; Gemini `models/{m}:countTokens` принимает полный
/// `generateContentRequest` с `inlineData` (PDF — `application/pdf`).
/// Живых запросов нет — только mock-HTTP.
void main() {
  Dio dioWith(FakeHttpAdapter adapter) {
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 2),
        receiveTimeout: const Duration(seconds: 2),
      ),
    );
    dio.httpClientAdapter = adapter;
    return dio;
  }

  ProviderAccount account(ProviderProtocol protocol, String model) =>
      ProviderAccount(
        id: 'acc',
        label: 'Acc',
        protocol: protocol,
        baseUrl: protocol == ProviderProtocol.anthropicMessages
            ? 'https://api.anthropic.com'
            : 'https://generativelanguage.googleapis.com',
        modelId: model,
        requiresApiKey: true,
      );

  GenerationAttachment image({
    String name = 'схема.png',
    int seed = 1,
    String? label,
  }) => GenerationAttachment(
    fileName: name,
    mediaType: AttachmentMediaType.png,
    bytes: Uint8List.fromList(
      List<int>.generate(96, (int i) => (i * 31 + seed) % 251),
    ),
    label: label,
  );

  GenerationAttachment pdf({String name = 'скан.pdf'}) => GenerationAttachment(
    fileName: name,
    mediaType: AttachmentMediaType.pdf,
    bytes: Uint8List.fromList(
      List<int>.generate(128, (int i) => (i * 17 + 3) % 251),
    ),
  );

  Map<String, Object?> bodyOf(RequestOptions request) =>
      request.data! as Map<String, Object?>;

  test('Anthropic: изображение уходит base64 image-блоком', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(<String, Object?>{'input_tokens': 1234}),
    );
    final GenerationAttachment picture = image();
    final ExactTokenCount count =
        await AnthropicRequestTokenCounter(
          dioWith(adapter),
          readApiKey: (String id) async => 'test-key',
        ).count(
          account(ProviderProtocol.anthropicMessages, 'claude-test'),
          systemPrompt: 'system',
          userContent: 'Опиши схему',
          attachments: <GenerationAttachment>[picture],
        );
    expect(count.tokens, 1234);
    final Map<String, Object?> body = bodyOf(adapter.requests.single);
    expect(body['system'], 'system');
    final List<Object?> messages = body['messages']! as List<Object?>;
    final Map<String, Object?> message =
        messages.single! as Map<String, Object?>;
    final List<Object?> content = message['content']! as List<Object?>;
    final Map<String, Object?> textBlock =
        content.first! as Map<String, Object?>;
    expect(textBlock['type'], 'text');
    expect(textBlock['text'], 'Опиши схему');
    final Map<String, Object?> imageBlock = content[1]! as Map<String, Object?>;
    expect(imageBlock['type'], 'image');
    final Map<String, Object?> source =
        imageBlock['source']! as Map<String, Object?>;
    expect(source['type'], 'base64');
    expect(source['media_type'], 'image/png');
    expect(source['data'], base64Encode(picture.bytes));
    expect(source.containsKey('url'), isFalse, reason: 'только base64');
    expect(source.containsKey('file'), isFalse);
  });

  test('Anthropic: PDF уходит base64 document-блоком', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(<String, Object?>{'input_tokens': 2188}),
    );
    final GenerationAttachment document = pdf();
    await AnthropicRequestTokenCounter(
      dioWith(adapter),
      readApiKey: (String id) async => 'k',
    ).count(
      account(ProviderProtocol.anthropicMessages, 'claude-test'),
      systemPrompt: 's',
      userContent: 'Суммируй документ',
      attachments: <GenerationAttachment>[document],
    );
    final Map<String, Object?> body = bodyOf(adapter.requests.single);
    final List<Object?> messages = body['messages']! as List<Object?>;
    final List<Object?> content =
        (messages.single! as Map<String, Object?>)['content']! as List<Object?>;
    final Map<String, Object?> block = content[1]! as Map<String, Object?>;
    expect(block['type'], 'document');
    final Map<String, Object?> source =
        block['source']! as Map<String, Object?>;
    expect(source['type'], 'base64');
    expect(source['media_type'], 'application/pdf');
    expect(source['data'], base64Encode(document.bytes));
  });

  test('Anthropic: несколько изображений и подписи каталога', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(<String, Object?>{'input_tokens': 10}),
    );
    final List<GenerationAttachment> pictures = <GenerationAttachment>[
      image(name: 'a.png', seed: 1, label: 'img1 | a.png | подпись'),
      image(name: 'b.png', seed: 5),
      image(name: 'c.png', seed: 9, label: 'img3 | c.png'),
    ];
    await AnthropicRequestTokenCounter(
      dioWith(adapter),
      readApiKey: (String id) async => 'k',
    ).count(
      account(ProviderProtocol.anthropicMessages, 'claude-test'),
      systemPrompt: 's',
      userContent: 'u',
      attachments: pictures,
    );
    final Map<String, Object?> body = bodyOf(adapter.requests.single);
    final List<Object?> messages = body['messages']! as List<Object?>;
    final List<Object?> content =
        (messages.single! as Map<String, Object?>)['content']! as List<Object?>;
    final List<Map<String, Object?>> blocks = <Map<String, Object?>>[
      for (final Object? item in content) item! as Map<String, Object?>,
    ];
    final List<Map<String, Object?>> images = <Map<String, Object?>>[
      for (final Map<String, Object?> block in blocks)
        if (block['type'] == 'image') block,
    ];
    expect(images, hasLength(3), reason: 'каждое изображение — отдельный блок');
    expect(
      images
          .map(
            (Map<String, Object?> block) =>
                (block['source']! as Map<String, Object?>)['data'],
          )
          .toList(),
      <Object?>[
        base64Encode(pictures[0].bytes),
        base64Encode(pictures[1].bytes),
        base64Encode(pictures[2].bytes),
      ],
      reason: 'порядок частей совпадает с production-запросом',
    );
    expect(
      blocks.where((Map<String, Object?> block) => block['type'] == 'text'),
      hasLength(3),
      reason: 'user content + две подписи каталога',
    );
  });

  test('Gemini: inlineData внутри generateContentRequest', () async {
    final FakeHttpAdapter adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(<String, Object?>{'totalTokens': 777}),
    );
    final List<GenerationAttachment> pictures = <GenerationAttachment>[
      image(name: 'a.png', seed: 2, label: 'img1 | a.png'),
      pdf(name: 'скан.pdf'),
    ];
    final ExactTokenCount count =
        await GeminiRequestTokenCounter(
          dioWith(adapter),
          readApiKey: (String id) async => 'k',
        ).count(
          account(ProviderProtocol.geminiGenerateContent, 'gemini-test'),
          systemPrompt: 'sys',
          userContent: 'text',
          attachments: pictures,
        );
    expect(count.tokens, 777);
    final RequestOptions request = adapter.requests.single;
    expect(request.uri.path, '/v1beta/models/gemini-test:countTokens');
    final Map<String, Object?> body = bodyOf(request);
    // Gemini countTokens принимает либо contents, либо полный
    // generateContentRequest; systemInstruction/generationConfig в top-level
    // не входят в схему CountTokensRequest и игнорируются.
    final Map<String, Object?> envelope =
        body['generateContentRequest']! as Map<String, Object?>;
    expect(body.containsKey('systemInstruction'), isFalse);
    expect(body.containsKey('generationConfig'), isFalse);
    expect(body.containsKey('contents'), isFalse);
    expect(
      envelope['model'],
      'models/gemini-test',
      reason: 'обёртка требует model в форме models/<id>',
    );
    final Map<String, Object?> system =
        envelope['systemInstruction']! as Map<String, Object?>;
    expect(
      ((system['parts']! as List<Object?>).first!
          as Map<String, Object?>)['text'],
      'sys',
    );
    final List<Object?> contents = envelope['contents']! as List<Object?>;
    final List<Object?> parts =
        (contents.single! as Map<String, Object?>)['parts']! as List<Object?>;
    final List<Map<String, Object?>> inline = <Map<String, Object?>>[
      for (final Object? part in parts)
        if (part is Map<String, Object?> && part['inlineData'] != null) part,
    ];
    expect(inline, hasLength(2));
    final Map<String, Object?> first =
        inline[0]['inlineData']! as Map<String, Object?>;
    expect(first['mimeType'], 'image/png');
    expect(first['data'], base64Encode(pictures[0].bytes));
    final Map<String, Object?> second =
        inline[1]['inlineData']! as Map<String, Object?>;
    expect(second['mimeType'], 'application/pdf');
    expect(second['data'], base64Encode(pictures[1].bytes));
  });

  test('ключ кэша учитывает байты, MIME-тип и подпись части', () {
    final ProviderAccount acc = account(
      ProviderProtocol.anthropicMessages,
      'claude-test',
    );
    final GenerationAttachment first = image(seed: 1);
    final GenerationAttachment changed = image(seed: 2);
    final String base = exactTokenCacheKey(
      account: acc,
      systemPrompt: 's',
      userContent: 'u',
      attachments: <GenerationAttachment>[first],
    );
    expect(
      exactTokenCacheKey(
        account: acc,
        systemPrompt: 's',
        userContent: 'u',
        attachments: <GenerationAttachment>[first],
      ),
      base,
      reason: 'то же содержимое — тот же ключ',
    );
    expect(
      exactTokenCacheKey(
        account: acc,
        systemPrompt: 's',
        userContent: 'u',
        attachments: <GenerationAttachment>[changed],
      ),
      isNot(base),
      reason: 'изменённые байты изображения меняют ключ',
    );
    expect(
      exactTokenCacheKey(
        account: acc,
        systemPrompt: 's',
        userContent: 'u',
        attachments: <GenerationAttachment>[
          GenerationAttachment(
            fileName: 'схема.png',
            mediaType: AttachmentMediaType.jpeg,
            bytes: first.bytes,
          ),
        ],
      ),
      isNot(base),
      reason: 'MIME-тип входит в ключ',
    );
    expect(
      exactTokenCacheKey(
        account: acc,
        systemPrompt: 's',
        userContent: 'u',
        attachments: <GenerationAttachment>[
          image(seed: 1, label: 'img1 | схема.png'),
        ],
      ),
      isNot(base),
      reason: 'подпись части входит в запрос — входит и в ключ',
    );
  });
}
