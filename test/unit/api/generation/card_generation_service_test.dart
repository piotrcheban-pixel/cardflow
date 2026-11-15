import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/generation_fakes.dart';

/// Итерация 7.5 (ADR-020): сервис генерации — аккаунт → промпт → адаптер →
/// транспорт → разбор → схема → контент-валидация (SPEC A8.5 шаги 6–7).
void main() {
  /// Облачный аккаунт с ключом в хранилище.
  ProviderAccount openAiAccount({
    String modelId = 'gpt-test',
    bool supportsVision = false,
  }) {
    return ProviderAccount(
      id: 'openai',
      label: 'OpenAI',
      presetId: 'openai',
      protocol: ProviderProtocol.openai,
      baseUrl: 'https://api.openai.com/v1',
      modelId: modelId,
      contextTokens: 128000,
      requiresApiKey: true,
      supportsVision: supportsVision,
    );
  }

  /// OpenAI-совместимый аккаунт (DeepSeek/локальный сервер).
  ProviderAccount compatibleAccount({
    String id = 'deepseek',
    String baseUrl = 'https://api.deepseek.com',
    String modelId = 'deepseek-chat',
    bool requiresApiKey = false,
    bool supportsVision = false,
  }) {
    return ProviderAccount(
      id: id,
      label: 'DeepSeek',
      presetId: 'deepseek',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: baseUrl,
      modelId: modelId,
      contextTokens: 128000,
      requiresApiKey: requiresApiKey,
      supportsVision: supportsVision,
    );
  }

  GenerationRequest requestFor(
    ProviderAccount account, {
    String materialsText = 'Материал лекции',
    String? wishes = 'Акцент на датах',
    int limit = 10,
    List<GenerationAttachment> images = const <GenerationAttachment>[],
  }) {
    return GenerationRequest(
      account: account,
      materialsText: materialsText,
      wishes: wishes,
      limit: limit,
      images: images,
    );
  }

  Map<String, Object?> validCardJson() => <String, Object?>{
    'front': 'Вопрос',
    'back': 'Ответ',
    'hint': null,
    'tags': <Object?>['тег'],
    'card_type': 'basic',
    'source_excerpt': null,
    'source_file': null,
  };

  String cardsJson(List<Map<String, Object?>> cards) =>
      jsonEncode(<String, Object?>{'cards': cards});

  CardGenerationService serviceWith({
    required FakeProviderAdapter adapter,
    required FakeGenerationTransport transport,
    FakeApiKeyStore? apiKeyStore,
    String systemPrompt = 'СИСТЕМНЫЙ ПРОМПТ',
  }) {
    return CardGenerationService(
      adapters: <FakeProviderAdapter>[adapter],
      apiKeyStore:
          apiKeyStore ??
          FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
      httpClient: transport,
      systemPrompt: systemPrompt,
      promptVersion: 'gen-ru-v2',
      maxOutputTokens: 1234,
    );
  }

  Matcher throwsGeneration(GenerationErrorCode code) => throwsA(
    isA<GenerationException>().having(
      (exception) => exception.code,
      'code',
      code,
    ),
  );

  test(
    'успех: ключ → запрос → ответ → карточки, расход и версия промпта',
    () async {
      final adapter = FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[validCardJson()]),
      );
      final transport = FakeGenerationTransport(
        response: <String, Object?>{'ok': true},
      );
      final service = serviceWith(adapter: adapter, transport: transport);

      final result = await service.generate(requestFor(openAiAccount()));

      expect(result.provider, GenerationProvider.openai);
      expect(result.model, 'gpt-test');
      expect(result.promptVersion, 'gen-ru-v2');
      expect(result.cards, hasLength(1));
      expect(result.cards.single.front, 'Вопрос');
      expect(adapter.buildArgs!.apiKey, 'test-key-openai');
      expect(adapter.buildArgs!.model, 'gpt-test');
      expect(adapter.buildArgs!.baseUrl, 'https://api.openai.com/v1');
      expect(adapter.buildArgs!.systemPrompt, 'СИСТЕМНЫЙ ПРОМПТ');
      expect(adapter.buildArgs!.maxOutputTokens, 1234);
      expect(
        adapter.buildArgs!.userContent,
        contains('<materials>\nМатериал лекции\n</materials>'),
      );
      expect(
        adapter.buildArgs!.userContent,
        contains('<wishes>\nАкцент на датах\n</wishes>'),
      );
      expect(adapter.buildArgs!.userContent, endsWith('<limit>10</limit>'));
      expect(transport.calls, 1);
    },
  );

  test(
    'ключ не задан у аккаунта, который его требует → missingApiKey',
    () async {
      final adapter = FakeProviderAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
      );

      await expectLater(
        service.generate(requestFor(openAiAccount())),
        throwsGeneration(GenerationErrorCode.missingApiKey),
      );
      expect(adapter.buildCalls, 0);
      expect(transport.calls, 0);
    },
  );

  test('ключ из пробелов → missingApiKey', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
      apiKeyStore: FakeApiKeyStore(<String, String>{'openai': '   '}),
    );
    await expectLater(
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.missingApiKey),
    );
  });

  test('аккаунт без адреса → providerNotConfigured, без запроса', () async {
    final adapter = FakeProviderAdapter();
    final service = serviceWith(
      adapter: adapter,
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(requestFor(compatibleAccount(baseUrl: '  '))),
      throwsGeneration(GenerationErrorCode.providerNotConfigured),
    );
    expect(adapter.buildCalls, 0);
  });

  test('ошибка разбора адаптера пробрасывается как есть', () async {
    final adapter = FakeProviderAdapter(
      error: const GenerationException(GenerationErrorCode.truncated),
    );
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = serviceWith(adapter: adapter, transport: transport);

    await expectLater(
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.truncated),
    );
    expect(transport.calls, 1);
  });

  test('ошибка транспорта пробрасывается как есть', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(),
      transport: FakeGenerationTransport(
        error: const GenerationException(GenerationErrorCode.serverUnavailable),
      ),
    );
    await expectLater(
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.serverUnavailable),
    );
  });

  test('не-JSON ответ модели → invalidResponse', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(cardsJson: 'не json'),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.invalidResponse),
    );
  });

  test('JSON не по схеме A8.4 → invalidResponse (back отсутствует)', () async {
    final card = validCardJson()..remove('back');
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[card]),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    await expectLater(
      service.generate(requestFor(openAiAccount())),
      throwsGeneration(GenerationErrorCode.invalidResponse),
    );
  });

  test('пустой массив cards — валидный результат без карточек', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final result = await service.generate(requestFor(openAiAccount()));
    expect(result.cards, isEmpty);
  });

  test('контентные пометки A8.4 доходят до результата', () async {
    final card = validCardJson()..['front'] = '';
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[card]),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final result = await service.generate(requestFor(openAiAccount()));
    expect(result.cards.single.hasIssues, isTrue);
  });

  test('используется адаптер протокола аккаунта и ключ его id', () async {
    final openAi = FakeProviderAdapter(provider: GenerationProvider.openai);
    final gemini = FakeProviderAdapter(provider: GenerationProvider.gemini);
    final transport = FakeGenerationTransport(response: <String, Object?>{});
    final service = CardGenerationService(
      adapters: <FakeProviderAdapter>[openAi, gemini],
      apiKeyStore: FakeApiKeyStore(<String, String>{'gemini': 'key-gemini'}),
      httpClient: transport,
    );
    final ProviderAccount geminiAccount = ProviderAccount(
      id: 'gemini',
      label: 'Gemini',
      presetId: 'gemini',
      protocol: ProviderProtocol.geminiGenerateContent,
      baseUrl: 'https://generativelanguage.googleapis.com',
      modelId: 'gemini-2.0-flash',
      contextTokens: 1048576,
      requiresApiKey: true,
    );

    await service.generate(requestFor(geminiAccount));
    expect(openAi.buildCalls, 0);
    expect(gemini.buildCalls, 1);
    expect(gemini.buildArgs!.apiKey, 'key-gemini');
    expect(gemini.buildArgs!.model, 'gemini-2.0-flash');
  });

  test('нет адаптера для протокола аккаунта → ArgumentError', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(provider: GenerationProvider.openai),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final ProviderAccount anthropicAccount = ProviderAccount(
      id: 'anthropic',
      label: 'Anthropic',
      presetId: 'anthropic',
      protocol: ProviderProtocol.anthropicMessages,
      baseUrl: 'https://api.anthropic.com',
      modelId: 'claude-3-5-haiku-latest',
      contextTokens: 200000,
      requiresApiKey: true,
    );
    await expectLater(
      service.generate(requestFor(anthropicAccount)),
      throwsArgumentError,
    );
  });

  test('расход токенов из ответа попадает в результат', () async {
    final service = serviceWith(
      adapter: FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
        usage: const TokenUsage(
          promptTokens: 3,
          completionTokens: 4,
          totalTokens: 7,
        ),
      ),
      transport: FakeGenerationTransport(response: <String, Object?>{}),
    );
    final result = await service.generate(requestFor(openAiAccount()));
    expect(
      result.usage,
      const TokenUsage(promptTokens: 3, completionTokens: 4, totalTokens: 7),
    );
  });

  group('OpenAI-совместимый протокол (ADR-013, ADR-020)', () {
    FakeProviderAdapter compatibleAdapter({
      String cardsJson = '{"cards":[]}',
    }) => FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson,
    );

    test('адрес и модель из аккаунта, ключ опционален', () async {
      final adapter = compatibleAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
      );

      final result = await service.generate(
        requestFor(compatibleAccount(baseUrl: 'http://localhost:11434/v1')),
      );

      expect(result.provider, GenerationProvider.openaiCompatible);
      expect(result.model, 'deepseek-chat');
      expect(adapter.buildArgs!.baseUrl, 'http://localhost:11434/v1');
      expect(adapter.buildArgs!.model, 'deepseek-chat');
      expect(adapter.buildArgs!.apiKey, isEmpty);
      expect(adapter.buildArgs!.strictSchema, isTrue);
      expect(transport.calls, 1);
    });

    test('аккаунт, требующий ключ, без ключа → missingApiKey', () async {
      final adapter = compatibleAdapter();
      final service = serviceWith(
        adapter: adapter,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
      );

      await expectLater(
        service.generate(requestFor(compatibleAccount(requiresApiKey: true))),
        throwsGeneration(GenerationErrorCode.missingApiKey),
      );
      expect(adapter.buildCalls, 0);
    });

    test(
      'strict 400 → один fallback без response_format, но с max_tokens',
      () async {
        final fenced = '```json\n${cardsJson(<Map<String, Object?>>[])}\n```';
        final adapter = compatibleAdapter(cardsJson: fenced);
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
          errorsBeforeResponse: <Object?>[
            const GenerationException(GenerationErrorCode.badRequest),
          ],
        );
        final service = serviceWith(
          adapter: adapter,
          transport: transport,
          apiKeyStore: FakeApiKeyStore(),
        );

        final result = await service.generate(
          requestFor(compatibleAccount(baseUrl: 'http://localhost:11434/v1')),
        );

        expect(result.cards, isEmpty);
        expect(transport.calls, 2);
        expect(adapter.buildCalls, 2);
        expect(adapter.buildArgs!.strictSchema, isFalse);
        expect(adapter.buildArgs!.sendMaxTokens, isTrue);
        expect(adapter.buildArgs!.baseUrl, 'http://localhost:11434/v1');
      },
    );

    test(
      'fallback с max_tokens тоже 400 → третий запрос без max_tokens (ADR-021)',
      () async {
        final adapter = compatibleAdapter(
          cardsJson: cardsJson(<Map<String, Object?>>[validCardJson()]),
        );
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
          errorsBeforeResponse: <Object?>[
            const GenerationException(GenerationErrorCode.badRequest),
            const GenerationException(GenerationErrorCode.badRequest),
          ],
        );
        final service = serviceWith(
          adapter: adapter,
          transport: transport,
          apiKeyStore: FakeApiKeyStore(),
        );

        final result = await service.generate(requestFor(compatibleAccount()));

        expect(result.cards, hasLength(1));
        expect(transport.calls, 3);
        expect(adapter.buildArgs!.strictSchema, isFalse);
        expect(adapter.buildArgs!.sendMaxTokens, isFalse);
      },
    );

    test('все три запроса 400 → badRequest, не больше трёх', () async {
      final transport = FakeGenerationTransport(
        response: <String, Object?>{},
        errorsBeforeResponse: <Object?>[
          const GenerationException(GenerationErrorCode.badRequest),
          const GenerationException(GenerationErrorCode.badRequest),
          const GenerationException(GenerationErrorCode.badRequest),
        ],
      );
      final service = serviceWith(
        adapter: compatibleAdapter(),
        transport: transport,
        apiKeyStore: FakeApiKeyStore(),
      );

      await expectLater(
        service.generate(requestFor(compatibleAccount())),
        throwsGeneration(GenerationErrorCode.badRequest),
      );
      expect(transport.calls, 3);
    });

    test(
      'без fallback-кода поведение прежнее: 5xx не повторяется сервисом',
      () async {
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
          errorsBeforeResponse: <Object?>[
            const GenerationException(GenerationErrorCode.serverUnavailable),
          ],
        );
        final service = serviceWith(
          adapter: compatibleAdapter(),
          transport: transport,
          apiKeyStore: FakeApiKeyStore(),
        );

        await expectLater(
          service.generate(requestFor(compatibleAccount())),
          throwsGeneration(GenerationErrorCode.serverUnavailable),
        );
        expect(transport.calls, 1);
      },
    );

    test(
      'нативный протокол: badRequest не повторяется fallback-логикой',
      () async {
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
          errorsBeforeResponse: <Object?>[
            const GenerationException(GenerationErrorCode.badRequest),
          ],
        );
        final service = serviceWith(
          adapter: FakeProviderAdapter(provider: GenerationProvider.openai),
          transport: transport,
        );

        await expectLater(
          service.generate(requestFor(openAiAccount())),
          throwsGeneration(GenerationErrorCode.badRequest),
        );
        expect(transport.calls, 1);
      },
    );

    test('markdown вокруг JSON извлекается только у compatible-протокола', () async {
      final tolerant = compatibleAdapter(
        cardsJson:
            'Вот карточки:\n```json\n${cardsJson(<Map<String, Object?>>[])}\n```',
      );
      final service = serviceWith(
        adapter: tolerant,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
        apiKeyStore: FakeApiKeyStore(),
      );
      final result = await service.generate(requestFor(compatibleAccount()));
      expect(result.cards, isEmpty);

      final strict = FakeProviderAdapter(
        provider: GenerationProvider.openai,
        cardsJson:
            'Вот карточки:\n```json\n${cardsJson(<Map<String, Object?>>[])}\n```',
      );
      final openAiService = serviceWith(
        adapter: strict,
        transport: FakeGenerationTransport(response: <String, Object?>{}),
      );
      await expectLater(
        openAiService.generate(requestFor(openAiAccount())),
        throwsGeneration(GenerationErrorCode.invalidResponse),
      );
    });
  });

  group('Итерация 7.8: вложения и Vision', () {
    GenerationAttachment pngAttachment({String fileName = 'схема.png'}) {
      return GenerationAttachment(
        fileName: fileName,
        mediaType: AttachmentMediaType.png,
        bytes: Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          1,
          2,
          3,
        ]),
      );
    }

    GenerationAttachment pdfAttachment() {
      return GenerationAttachment(
        fileName: 'скан.pdf',
        mediaType: AttachmentMediaType.pdf,
        bytes: Uint8List.fromList(<int>[0x25, 0x50, 0x44, 0x46, 0x2D]),
      );
    }

    GenerationAttachment pdfPageAttachment({int pageNumber = 1}) {
      return GenerationAttachment(
        fileName: 'скан.pdf',
        mediaType: AttachmentMediaType.png,
        pageNumber: pageNumber,
        groupKey: '/tmp/скан.pdf',
        bytes: Uint8List.fromList(<int>[
          0x89,
          0x50,
          0x4E,
          0x47,
          0x0D,
          0x0A,
          0x1A,
          0x0A,
          1,
          2,
          3,
        ]),
      );
    }

    test(
      'пустой текст без вложений → noMaterials, без адаптера и сети',
      () async {
        final adapter = FakeProviderAdapter();
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
        );
        final service = serviceWith(adapter: adapter, transport: transport);

        await expectLater(
          service.generate(
            requestFor(openAiAccount(), materialsText: ' \u0000\n\n '),
          ),
          throwsGeneration(GenerationErrorCode.noMaterials),
        );
        expect(adapter.buildCalls, 0);
        expect(transport.calls, 0);
      },
    );

    test('управляющие символы в материалах и пожеланиях удаляются', () async {
      final adapter = FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      );
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(adapter: adapter, transport: transport);

      await service.generate(
        requestFor(
          openAiAccount(),
          materialsText: 'Текст\u0000лекции\u000B',
          wishes: 'Акцент\u0000на датах',
        ),
      );

      expect(adapter.buildArgs!.userContent, contains('Текстлекции'));
      expect(adapter.buildArgs!.userContent, contains('Акцентна датах'));
      expect(adapter.buildArgs!.userContent, isNot(contains('\u0000')));
      expect(adapter.buildArgs!.userContent, isNot(contains('\u000B')));
    });

    test('vision=true + картинка → image part в запросе адаптера', () async {
      final adapter = FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      );
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(adapter: adapter, transport: transport);

      await service.generate(
        requestFor(
          openAiAccount(supportsVision: true),
          materialsText: '',
          images: <GenerationAttachment>[pngAttachment()],
        ),
      );

      expect(adapter.buildArgs!.images, hasLength(1));
      expect(adapter.buildArgs!.images.single.fileName, 'схема.png');
      expect(
        adapter.buildArgs!.userContent,
        contains('Приложенные изображения'),
        reason: 'для image-only запроса нужен непустой блок materials',
      );
      expect(transport.calls, 1);
    });

    test('vision=false + картинка → visionUnsupported, без запроса', () async {
      final adapter = FakeProviderAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(adapter: adapter, transport: transport);

      await expectLater(
        service.generate(
          requestFor(
            openAiAccount(supportsVision: false),
            materialsText: '',
            images: <GenerationAttachment>[pngAttachment()],
          ),
        ),
        throwsGeneration(GenerationErrorCode.visionUnsupported),
      );
      expect(adapter.buildCalls, 0);
      expect(transport.calls, 0);
    });

    test('PDF-скан без PDF-vision → pdfScanUnsupported, без запроса', () async {
      final adapter = FakeProviderAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(adapter: adapter, transport: transport);

      await expectLater(
        service.generate(
          requestFor(
            openAiAccount(supportsVision: true),
            materialsText: '',
            images: <GenerationAttachment>[pdfAttachment()],
          ),
        ),
        throwsGeneration(GenerationErrorCode.pdfScanUnsupported),
      );
      expect(adapter.buildCalls, 0);
      expect(transport.calls, 0);
    });

    test(
      'страницы PDF-скана без Vision → pdfScanVisionRequired, без запроса',
      () async {
        final adapter = FakeProviderAdapter();
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
        );
        final service = serviceWith(adapter: adapter, transport: transport);

        await expectLater(
          service.generate(
            requestFor(
              openAiAccount(supportsVision: false),
              materialsText: '',
              images: <GenerationAttachment>[pdfPageAttachment()],
            ),
          ),
          throwsGeneration(GenerationErrorCode.pdfScanVisionRequired),
        );
        expect(adapter.buildCalls, 0);
        expect(transport.calls, 0);
      },
    );

    test('страницы PDF-скана при Vision → image parts, один запрос', () async {
      final adapter = FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      );
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(adapter: adapter, transport: transport);

      await service.generate(
        requestFor(
          openAiAccount(supportsVision: true),
          materialsText: '',
          images: <GenerationAttachment>[
            pdfPageAttachment(pageNumber: 1),
            pdfPageAttachment(pageNumber: 2),
          ],
        ),
      );

      expect(adapter.buildArgs!.images, hasLength(2));
      expect(transport.calls, 1);
      expect(
        adapter.buildArgs!.userContent,
        contains('Приложенный PDF-скан (страницы)'),
      );
    });

    test('вложение больше 10 МБ → attachmentTooLarge, без запроса', () async {
      final adapter = FakeProviderAdapter();
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final service = serviceWith(adapter: adapter, transport: transport);
      final GenerationAttachment huge = GenerationAttachment(
        fileName: 'огромная.png',
        mediaType: AttachmentMediaType.png,
        bytes: Uint8List(kMaxInlineAttachmentBytes + 1),
      );

      await expectLater(
        service.generate(
          requestFor(
            openAiAccount(supportsVision: true),
            materialsText: '',
            images: <GenerationAttachment>[huge],
          ),
        ),
        throwsGeneration(GenerationErrorCode.attachmentTooLarge),
      );
      expect(adapter.buildCalls, 0);
      expect(transport.calls, 0);
    });

    test(
      'модель без Vision: причина «нет изображений» важнее размера',
      () async {
        final adapter = FakeProviderAdapter();
        final transport = FakeGenerationTransport(
          response: <String, Object?>{},
        );
        final service = serviceWith(adapter: adapter, transport: transport);
        final GenerationAttachment huge = GenerationAttachment(
          fileName: 'огромная.png',
          mediaType: AttachmentMediaType.png,
          bytes: Uint8List(kMaxInlineAttachmentBytes + 1),
        );

        await expectLater(
          service.generate(
            requestFor(
              openAiAccount(supportsVision: false),
              materialsText: '',
              images: <GenerationAttachment>[huge],
            ),
          ),
          throwsGeneration(GenerationErrorCode.visionUnsupported),
        );
        expect(adapter.buildCalls, 0);
        expect(transport.calls, 0);
      },
    );

    test('PDF-скан + Anthropic (PDF-vision) → вложение передаётся', () async {
      final adapter = FakeProviderAdapter(
        provider: GenerationProvider.anthropic,
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      );
      final transport = FakeGenerationTransport(response: <String, Object?>{});
      final ProviderAccount account = ProviderAccount(
        id: 'anthropic',
        label: 'Anthropic',
        presetId: 'anthropic',
        protocol: ProviderProtocol.anthropicMessages,
        baseUrl: 'https://api.anthropic.com',
        modelId: 'claude-3-5-haiku-latest',
        contextTokens: 200000,
        requiresApiKey: true,
        supportsVision: true,
      );
      final service = serviceWith(
        adapter: adapter,
        transport: transport,
        apiKeyStore: FakeApiKeyStore(<String, String>{'anthropic': 'key'}),
      );

      await service.generate(
        requestFor(
          account,
          materialsText: '',
          images: <GenerationAttachment>[pdfAttachment()],
        ),
      );

      expect(adapter.buildArgs!.images.single.isPdf, isTrue);
      expect(transport.calls, 1);
    });

    test('400 с причиной провайдера доходит до GenerationException', () async {
      final adapter = FakeProviderAdapter(
        provider: GenerationProvider.openai,
        cardsJson: cardsJson(<Map<String, Object?>>[]),
      );
      final transport = FakeGenerationTransport(
        error: const GenerationException(
          GenerationErrorCode.badRequest,
          providerReason: 'invalid characters in content',
        ),
      );
      final service = serviceWith(adapter: adapter, transport: transport);

      await expectLater(
        service.generate(requestFor(openAiAccount())),
        throwsA(
          isA<GenerationException>()
              .having(
                (GenerationException error) => error.code,
                'code',
                GenerationErrorCode.badRequest,
              )
              .having(
                (GenerationException error) => error.providerReason,
                'providerReason',
                'invalid characters in content',
              ),
        ),
      );
    });
  });
}
