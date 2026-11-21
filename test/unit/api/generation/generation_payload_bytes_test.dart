import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../../../helpers/generation_fakes.dart';

/// §3.4 / T5: байты тела запроса — это **сериализованный** payload после
/// адаптера (system prompt + сообщение + схема + каталог + base64 + обвязка), а
/// не оценка «текст + base64». Лимит `maxRequestBytes` проверяется по факту;
/// превышение — ошибка `payloadTooLarge`, а не молчаливая потеря изображений.
void main() {
  const OpenAiCompatibleAdapter adapter = OpenAiCompatibleAdapter();

  ProviderAccount account({int? maxRequestBytes, int? maxImageBytes}) =>
      ProviderAccount(
        id: 'acc',
        label: 'Совместимый сервер',
        protocol: ProviderProtocol.openaiCompletions,
        baseUrl: 'https://api.example.com/v1',
        modelId: 'test-model',
        requiresApiKey: true,
        supportsVision: true,
        visionConfigured: true,
        maxRequestBytes: maxRequestBytes,
        maxImageBytes: maxImageBytes,
      );

  DocumentImage documentImage({
    String id = 'img1',
    int bytes = 4096,
    int seed = 0,
    String caption = 'Схема',
  }) => DocumentImage(
    fileName: 'a.docx',
    bytes: Uint8List.fromList(
      List<int>.generate(bytes, (int i) => (seed + i) % 251),
    ),
    mediaType: AttachmentMediaType.png,
    id: id,
    caption: caption,
    context: 'Схема из документа',
  );

  ParsedDocument docOf(String text) => ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'a.doc',
    text: text,
    sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
  );

  FakeGenerationTransport transportWithResponse() => FakeGenerationTransport(
    response: <String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{'content': '{"cards":[]}'},
          'finish_reason': 'stop',
        },
      ],
    },
  );

  CardGenerationService serviceOn(FakeGenerationTransport transport) =>
      CardGenerationService(
        adapters: <GenerationProviderAdapter>[adapter],
        apiKeyStore: FakeApiKeyStore(<String, String>{'acc': 'test-key'}),
        httpClient: transport,
      );

  /// Байты тела, как их увидит HTTP: UTF-8 сериализованного JSON.
  int serializedBytes(ProviderRequest request) =>
      utf8.encode(jsonEncode(request.body)).length;

  test('payload включает промпт, схему, каталог и base64 — не только текст', () {
    final String materials = 'Текст раздела про фотосинтез.';
    final DocumentImage image = documentImage(bytes: 60000);
    final GenerationPlan plan = const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[docOf(materials)],
      capabilities: const ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.userConfigured,
        maxOutputTokens: 8192,
        supportsVision: true,
      ),
      documentImages: <DocumentImage>[image],
    );
    final PlannedChunk chunk = plan.chunks.single;
    final String userContent = buildGenerationUserContent(
      materialsText: chunk.materialsText,
      limit: chunk.limit,
      imagesCatalog: 'img1 | a.docx | Схема | Схема из документа',
    );
    final ProviderRequest request = adapter.buildRequest(
      apiKey: 'test-key',
      model: 'test-model',
      systemPrompt: systemPromptGenRuV8,
      userContent: userContent,
      maxOutputTokens: 4096,
      baseUrl: 'https://api.example.com/v1',
      images: <GenerationAttachment>[
        GenerationAttachment(
          fileName: image.fileName,
          mediaType: image.mediaType,
          bytes: image.bytes,
          label: 'img1 | a.docx | Схема | Схема из документа',
        ),
      ],
    );
    final int actual = serializedBytes(request);
    expect(
      chunk.bodyBytes,
      lessThanOrEqualTo(actual),
      reason: 'оценка плана — нижняя граница реального тела',
    );
    expect(
      chunk.bodyBytes,
      greaterThanOrEqualTo(actual - 4096),
      reason:
          'requestBytes плана обязан учитывать обвязку протокола: промпт, '
          'схему ответа и JSON-ключи (запас — 4 КБ на экранирование)',
    );
  });

  test('превышение лимита тела: payloadTooLarge, запрос не отправлен', () async {
    final FakeGenerationTransport transport = transportWithResponse();
    final DocumentImage image = documentImage(bytes: 200 * 1024);
    await expectLater(
      serviceOn(transport).generate(
        GenerationRequest(
          account: account(maxRequestBytes: 200 * 1024),
          materialsText: 'Текст раздела.',
          limit: 3,
          documentImages: <DocumentImage>[image],
          documentImageParts: <DocumentImage>[image],
        ),
      ),
      throwsA(
        isA<GenerationException>().having(
          (GenerationException error) => error.code,
          'code',
          GenerationErrorCode.payloadTooLarge,
        ),
      ),
      reason: 'превышение технического лимита — явная ошибка протокола',
    );
    expect(
      transport.requests,
      isEmpty,
      reason: 'гарантированно проваливающийся запрос не тратит токены',
    );
  });

  test('T5: 13 МБ + каталог в лимите 20 МБ — запрос уходит', () async {
    final FakeGenerationTransport transport = transportWithResponse();
    final DocumentImage first = documentImage(bytes: 13 * 1024 * 1024);
    final DocumentImage second = documentImage(
      id: 'img2',
      bytes: 13 * 1024 * 1024,
      seed: 1,
    );
    final GenerationResult result = await serviceOn(transport).generate(
      GenerationRequest(
        account: account(
          maxRequestBytes: 20 * 1024 * 1024,
          maxImageBytes: 20 * 1024 * 1024,
        ),
        materialsText: 'Текст схем. Схема страницы.',
        limit: 5,
        documentImages: <DocumentImage>[first, second],
        documentImageParts: <DocumentImage>[first],
      ),
    );
    final ProviderRequest sent = transport.requests.single;
    expect(
      serializedBytes(sent),
      lessThanOrEqualTo(20 * 1024 * 1024),
      reason: 'реальный payload укладывается в лимит тела',
    );
    expect(
      result.sentDocumentImageIds,
      <String>['img1'],
      reason: 'отправлена ровно та картинка, которую выбрал план',
    );
    expect(
      result.skippedDocumentImageIds,
      isNot(contains('img2')),
      reason:
          'не отправленная картинка остаётся в каталоге плана '
          '(omittedPayload), а не теряется внутри сервиса',
    );
  });

  test(
    'T5: две части в одном запросе — payloadTooLarge, без молчаливой потери',
    () async {
      final FakeGenerationTransport transport = transportWithResponse();
      final DocumentImage first = documentImage(bytes: 13 * 1024 * 1024);
      final DocumentImage second = documentImage(
        id: 'img2',
        bytes: 13 * 1024 * 1024,
        seed: 1,
      );
      await expectLater(
        serviceOn(transport).generate(
          GenerationRequest(
            account: account(
              maxRequestBytes: 20 * 1024 * 1024,
              maxImageBytes: 20 * 1024 * 1024,
            ),
            materialsText: 'Текст схем.',
            limit: 5,
            documentImages: <DocumentImage>[first, second],
            // План ошибочно посчитал, что в 20 МБ помещаются обе части.
            documentImageParts: <DocumentImage>[first, second],
          ),
        ),
        throwsA(
          isA<GenerationException>().having(
            (GenerationException error) => error.code,
            'code',
            GenerationErrorCode.payloadTooLarge,
          ),
        ),
        reason:
            '34,7 МБ base64 в лимит 20 МБ не помещаются — это статус, а не '
            'молчаливая отправка с отброшенной картинкой',
      );
      expect(transport.requests, isEmpty);
    },
  );

  test('каталог `<images>` входит в сериализованный payload', () async {
    final FakeGenerationTransport transport = transportWithResponse();
    final DocumentImage image = documentImage(caption: 'Очень длинная подпись');
    await serviceOn(transport).generate(
      GenerationRequest(
        account: account(),
        materialsText: 'Текст.',
        limit: 3,
        documentImages: <DocumentImage>[image],
        documentImageParts: const <DocumentImage>[],
      ),
    );
    final String body = jsonEncode(transport.requests.single.body);
    expect(
      body,
      contains('a.docx'),
      reason: 'каталог `<images>` — часть тела запроса',
    );
    expect(body, contains('Схема из документа'));
  });

  test('схема ответа и системный промпт присутствуют в теле', () async {
    final FakeGenerationTransport transport = transportWithResponse();
    await serviceOn(transport).generate(
      GenerationRequest(
        account: account(),
        materialsText: 'Текст.',
        limit: 3,
      ),
    );
    final String body = jsonEncode(transport.requests.single.body);
    expect(body, contains(cardsResponseSchemaName));
    expect(body, contains('ПЛАНИРОВАНИЕ ВЫДАЧИ'));
  });
}
