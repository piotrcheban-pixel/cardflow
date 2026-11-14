/// Сервис генерации карточек: аккаунт → запрос → HTTP → ответ → валидация.
///
/// Один вызов модели на один фрагмент (чанкинг и `generation_jobs` — пайплайн).
/// Аккаунт провайдера (ADR-020) задаёт протокол, базовый адрес, модель и id
/// ключа: ключ читается только из `ApiKeyStore`, адрес и модель — из аккаунта.
/// Для OpenAI-совместимого протокола при отказе сервера от strict-схемы
/// выполняется один fallback-запрос без `response_format` с той же локальной
/// валидацией (ADR-013).
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/text_sanitizer.dart';

/// Вызов модели и локальная валидация ответа (SPEC A8.2, A8.4–A8.6).
class CardGenerationService implements GenerationCaller {
  /// Создаёт сервис.
  CardGenerationService({
    required this.adapters,
    required this.apiKeyStore,
    required this.httpClient,
    CardResponseSchema? responseSchema,
    CardContentValidator? contentValidator,
    this.jsonExtractor = const CardsJsonExtractor(),
    this.systemPrompt = systemPromptGenRuV2,
    this.promptVersion = systemPromptVersion,
    this.maxOutputTokens = 8192,
    this.textSanitizer = const TextSanitizer(),
  }) : responseSchema = responseSchema ?? CardResponseSchema(),
       contentValidator = contentValidator ?? const CardContentValidator();

  /// Адаптеры провайдеров (по одному на протокол).
  final List<GenerationProviderAdapter> adapters;

  /// Хранилище ключей API (только secure storage).
  final ApiKeyStore apiKeyStore;

  /// Транспорт HTTP (Dio + retry + redaction в production-проводке).
  final GenerationTransport httpClient;

  /// Локальная проверка схемы ответа A8.4.
  final CardResponseSchema responseSchema;

  /// Локальная проверка контентных правил A8.4.
  final CardContentValidator contentValidator;

  /// Разбор текста ответа модели в JSON (markdown-обёртка, BOM).
  final CardsJsonExtractor jsonExtractor;

  /// Системный промпт (скрыт от UI).
  final String systemPrompt;

  /// Версия системного промпта для `generation_jobs`.
  final String promptVersion;

  /// Верхняя граница ответа модели (Anthropic требует `max_tokens`).
  final int maxOutputTokens;

  /// Санитайзер локально извлечённого текста (итерация 7.8).
  final TextSanitizer textSanitizer;

  /// Генерирует карточки для одного фрагмента материалов.
  ///
  /// Бросает [GenerationException] с кодом из `lib/domain/generation/generation_error.dart`;
  /// сырые исключения провайдеров и ключи наружу не попадают.
  @override
  Future<GenerationResult> generate(
    GenerationRequest request, {
    CancelToken? cancelToken,
  }) async {
    final ProviderAccount account = request.account;
    if (!account.isConfigured) {
      throw const GenerationException(
        GenerationErrorCode.providerNotConfigured,
        details: 'Провайдер не настроен: нет адреса или модели',
      );
    }

    final GenerationProviderAdapter adapter = _adapterFor(
      account.protocol.adapterProvider,
    );
    final String? apiKey = (await apiKeyStore.read(account.id))?.trim();
    if (account.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw const GenerationException(GenerationErrorCode.missingApiKey);
    }
    final String model = account.modelId.trim();
    final String baseUrl = account.baseUrl.trim();
    final bool tolerantFallback =
        account.protocol == ProviderProtocol.openaiCompletions;

    _validateAttachments(account, request.images);

    final String materialsText = textSanitizer.sanitize(request.materialsText);
    if (materialsText.isEmpty && request.images.isEmpty) {
      throw const GenerationException(
        GenerationErrorCode.noMaterials,
        details: 'После санитизации текст пуст, вложений нет',
      );
    }
    final String materials = materialsText.isEmpty
        ? _attachmentMaterials(request.images)
        : materialsText;
    final String userContent = buildGenerationUserContent(
      materialsText: materials,
      wishes: _sanitizedWishes(request.wishes),
      limit: request.limit,
    );

    final ProviderRawResponse rawResponse = await _postWithFallbacks(
      adapter: adapter,
      apiKey: apiKey ?? '',
      model: model,
      baseUrl: baseUrl,
      userContent: userContent,
      images: request.images,
      tolerantFallback: tolerantFallback,
      cancelToken: cancelToken,
    );

    final decoded = jsonExtractor.decode(
      rawResponse.cardsJson,
      tolerant: tolerantFallback,
    );

    final schemaErrors = responseSchema.validate(decoded);
    if (schemaErrors.isNotEmpty) {
      throw GenerationException(
        GenerationErrorCode.invalidResponse,
        details:
            'Ответ модели не соответствует схеме A8.4 '
            '(${schemaErrors.length} нарушений)',
      );
    }

    final cards = contentValidator.validateResponse(
      decoded,
      sourceText: materialsText,
    );
    return GenerationResult(
      provider: account.protocol.adapterProvider,
      model: model,
      promptVersion: promptVersion,
      cards: cards,
      usage: rawResponse.usage,
    );
  }

  /// Отправляет запрос с «лестницей совместимости» (ADR-021).
  ///
  /// OpenAI-совместимые серверы различаются поддержкой полей запроса, поэтому
  /// при `badRequest` сервис по одному упрощает запрос, не теряя локальной
  /// проверки схемы A8.4:
  /// 1) strict `response_format` + `max_tokens`;
  /// 2) без `response_format` (сервер не знает `json_schema` — DeepSeek);
  /// 3) без `max_tokens` (сервер требует `max_completion_tokens`).
  ///
  /// Нативные протоколы (`openai`, `gemini`, `anthropic`) повтор не делают:
  /// их контракт зафиксирован, ошибка отдаётся пользователю как есть.
  Future<ProviderRawResponse> _postWithFallbacks({
    required GenerationProviderAdapter adapter,
    required String apiKey,
    required String model,
    required String? baseUrl,
    required String userContent,
    required List<GenerationAttachment> images,
    required bool tolerantFallback,
    required CancelToken? cancelToken,
  }) async {
    final List<({bool strictSchema, bool sendMaxTokens})> attempts =
        <({bool strictSchema, bool sendMaxTokens})>[
          (strictSchema: true, sendMaxTokens: true),
          if (tolerantFallback) (strictSchema: false, sendMaxTokens: true),
          if (tolerantFallback) (strictSchema: false, sendMaxTokens: false),
        ];
    GenerationException? lastError;
    for (final attempt in attempts) {
      try {
        return await _postAndParse(
          adapter: adapter,
          apiKey: apiKey,
          model: model,
          baseUrl: baseUrl,
          userContent: userContent,
          images: images,
          strictSchema: attempt.strictSchema,
          sendMaxTokens: attempt.sendMaxTokens,
          cancelToken: cancelToken,
        );
      } on GenerationException catch (error) {
        lastError = error;
        if (!tolerantFallback || error.code != GenerationErrorCode.badRequest) {
          rethrow;
        }
      }
    }
    throw lastError!;
  }

  /// Строит запрос адаптером и разбирает ответ провайдера.
  Future<ProviderRawResponse> _postAndParse({
    required GenerationProviderAdapter adapter,
    required String apiKey,
    required String model,
    required String? baseUrl,
    required String userContent,
    required List<GenerationAttachment> images,
    required bool strictSchema,
    required bool sendMaxTokens,
    required CancelToken? cancelToken,
  }) async {
    final providerRequest = adapter.buildRequest(
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      userContent: userContent,
      maxOutputTokens: maxOutputTokens,
      baseUrl: baseUrl,
      strictSchema: strictSchema,
      sendMaxTokens: sendMaxTokens,
      images: images,
    );
    final rawJson = await httpClient.postJson(
      providerRequest,
      cancelToken: cancelToken,
    );
    return adapter.parseResponse(rawJson);
  }

  /// Проверяет вложения до сборки запроса (итерация 7.8).
  ///
  /// Порядок важен: сначала vision модели, затем PDF-возможность протокола и
  /// лимит; ошибка не доходит до сети и не тратит токены.
  void _validateAttachments(
    ProviderAccount account,
    List<GenerationAttachment> images,
  ) {
    for (final GenerationAttachment image in images) {
      if (!account.supportsVision) {
        throw GenerationException(
          image.isPdf
              ? GenerationErrorCode.fileWithoutTextAndVision
              : GenerationErrorCode.visionUnsupported,
          details: 'Модель не поддерживает изображения',
        );
      }
      if (image.bytes.length > kMaxInlineAttachmentBytes) {
        throw const GenerationException(
          GenerationErrorCode.attachmentTooLarge,
          details: 'Вложение больше 10 МБ',
        );
      }
      if (image.isPdf && !account.protocol.supportsPdfAttachments) {
        throw const GenerationException(
          GenerationErrorCode.pdfScanUnsupported,
          details: 'Протокол не принимает PDF как документ',
        );
      }
    }
  }

  /// Текст блока `<materials>` для image-only запроса.
  String _attachmentMaterials(List<GenerationAttachment> images) {
    final String names = images
        .map((GenerationAttachment image) => image.fileName)
        .join(', ');
    if (images.every((GenerationAttachment image) => image.isPdf)) {
      return 'Приложенный документ (скан): $names';
    }
    if (images.every((GenerationAttachment image) => !image.isPdf)) {
      return 'Приложенные изображения: $names';
    }
    return 'Приложенные файлы: $names';
  }

  /// Пожелания после санитизации; пустые — не передаются.
  String? _sanitizedWishes(String? wishes) {
    if (wishes == null) return null;
    final String sanitized = textSanitizer.sanitize(wishes);
    return sanitized.isEmpty ? null : sanitized;
  }

  GenerationProviderAdapter _adapterFor(GenerationProvider provider) {
    for (final adapter in adapters) {
      if (adapter.provider == provider) return adapter;
    }
    throw ArgumentError.value(
      provider.wireName,
      'provider',
      'Для провайдера не собран адаптер генерации',
    );
  }
}
