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
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/generation_request_estimator.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart'
    show GenerationChunkPlannerConfig;
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_request_limits.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
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
    this.systemPrompt = systemPromptGenRuV7,
    this.promptVersion = systemPromptVersion,
    this.maxOutputTokens = 8192,
    this.textSanitizer = const TextSanitizer(),
    this.estimator = const HeuristicContentTokenEstimator(),
    this.requestEstimator,
    this.limitsConfig = const GenerationChunkPlannerConfig(),
    GenerationDiagnostics? diagnostics,
  }) : responseSchema = responseSchema ?? CardResponseSchema(),
       contentValidator = contentValidator ?? const CardContentValidator(),
       diagnostics = diagnostics ?? const GenerationDiagnostics();

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

  /// Оценщик единиц (тот же, что у планировщика; TASK 03).
  final ContentTokenEstimator estimator;

  /// Оценка собранного запроса; `null` — собрать из [estimator] и [systemPrompt].
  final GenerationRequestEstimator? requestEstimator;

  /// Конфигурация допущений лимитов запроса (та же, что у планировщика).
  ///
  /// Один источник значений для плана и исполнителя: если аккаунт не сообщает
  /// `max_images_per_request`/`max_image_bytes`/`max_request_bytes`, обе стороны
  /// берут консервативные значения отсюда, а не из разных констант.
  final GenerationChunkPlannerConfig limitsConfig;

  /// Debug-диагностика ответа модели (ADR-024, итерация 7.10).
  final GenerationDiagnostics diagnostics;

  /// Оценщик собранного запроса (ленивая сборка, если не инжектирован).
  GenerationRequestEstimator get _requestEstimator =>
      requestEstimator ??
      GenerationRequestEstimator(
        estimator: estimator,
        systemPrompt: systemPrompt,
      );

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

    final ModelCapabilities capabilities = resolveModelCapabilities(account);
    final GenerationRequestLimits limits = resolveGenerationRequestLimits(
      capabilities,
      assumedMaxImagesPerRequest: limitsConfig.assumedMaxImagesPerChunk,
      assumedMaxImageBytesPerImage: limitsConfig.assumedMaxImageBytesPerImage,
      assumedMaxImageBytesPerChunk: limitsConfig.assumedMaxImageBytesPerChunk,
      assumedMaxRequestBytes: limitsConfig.assumedMaxRequestBytes,
    );
    _validateAttachments(account, request.images, limits);

    final String materialsText = textSanitizer.sanitize(request.materialsText);
    final String? wishes = _sanitizedWishes(request.wishes);
    // Сводка продолжения prompt-only идёт отдельным блоком после пожеланий:
    // исходные требования пользователя не переписываются (TASK 03, раздел 4).
    final String? continuation = _sanitizedContinuation(request.continuation);
    final String? effectiveWishes = _mergeWishes(wishes, continuation);
    // «Генерация по теме» (итерация 7.10, ADR-024): без файлов тема задана в
    // пожеланиях, поэтому пустой текст допустим.
    if (materialsText.isEmpty &&
        request.images.isEmpty &&
        effectiveWishes == null) {
      throw const GenerationException(
        GenerationErrorCode.noMaterials,
        details: 'После санитизации нет текста, вложений и пожеланий',
      );
    }
    final String materials = materialsText.isEmpty
        ? request.images.isEmpty
              ? ''
              : _attachmentMaterials(request.images)
        : materialsText;
    final List<DocumentImage> documentImages = withCatalogIds(
      request.documentImages,
    );
    final _DocumentPartsResult parts = _withDocumentImages(
      account,
      request.images,
      documentImages,
      request.documentImageParts,
      limits: limits,
    );
    final String userContent = buildGenerationUserContent(
      materialsText: materials,
      wishes: effectiveWishes,
      limit: request.limit,
      imagesCatalog: documentImages.isEmpty
          ? null
          : buildImageCatalog(documentImages),
    );
    // Vision (ADR-037): модель должна ВИДЕТЬ изображения из документов, а не
    // только их идентификаторы. Байты уходят отдельными частями с подписью
    // каталога; каталог при этом остаётся полным.
    final List<GenerationAttachment> visionParts = parts.attachments;
    final int maxOutputTokens =
        request.maxOutputTokens ??
        account.maxOutputTokens ??
        this.maxOutputTokens;
    // Оценка собранного запроса тем же оценщиком, что у плана (TASK 03):
    // сохраняется в результате для калибровки по `usage`; это не факт.
    final GenerationRequestEstimate estimate = _requestEstimator.estimate(
      userContent: userContent,
      attachments: visionParts,
      maxOutputTokens: maxOutputTokens,
      unknownFields: capabilities.unknownFields,
    );

    final ProviderRawResponse rawResponse = await _postWithFallbacks(
      adapter: adapter,
      apiKey: apiKey ?? '',
      model: model,
      baseUrl: baseUrl,
      userContent: userContent,
      images: visionParts,
      maxOutputTokens: maxOutputTokens,
      tolerantFallback: tolerantFallback,
      cancelToken: cancelToken,
    );

    // Debug-диагностика (ADR-024): сырой ответ — чтобы видеть поля вроде
    // image_query; в release метод — no-op.
    diagnostics.modelResponse(rawResponse.cardsJson);

    final decoded = jsonExtractor.decode(
      rawResponse.cardsJson,
      tolerant: tolerantFallback,
    );

    // Поштучная проверка схемы (fix-gen, Д6): одна невалидная карточка не
    // отбрасывает весь фрагмент.
    final CardPayloadValidation payload = responseSchema.splitValid(decoded);
    if (payload.rootInvalid) {
      throw GenerationException(
        GenerationErrorCode.invalidResponse,
        details: 'Ответ модели не соответствует схеме A8.4',
        failureReason: GenerationFailureReason.schemaInvalid,
      );
    }
    final CardValidationOutcome outcome = contentValidator
        .validateResponseWithRejects(
          <String, Object?>{'cards': payload.cards},
          sourceText: materialsText,
          imageIds: <String>{
            for (final DocumentImage image in documentImages) image.id,
          },
        );
    return GenerationResult(
      provider: account.protocol.adapterProvider,
      model: model,
      promptVersion: promptVersion,
      cards: outcome.cards,
      usage: rawResponse.usage,
      rejectedCards: payload.rejectedCards + outcome.rejectedCards,
      estimatedInputTokens: estimate.inputTotal.tokens,
      estimatedOutputTokens: estimate.outputReserve.tokens,
      estimatorVersion: estimate.estimatorVersion,
      sentDocumentImageIds: parts.sentIds,
      skippedDocumentImageIds: parts.skippedIds,
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
    required int maxOutputTokens,
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
          maxOutputTokens: maxOutputTokens,
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
    required int maxOutputTokens,
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

  /// Изображения документов как image-parts запроса (ADR-037, TASK 03).
  ///
  /// Если план передал `documentImageParts` (явный префикс каталога), сервис
  /// отправляет **ровно эти** части: он не переранжирует и не урезает их
  /// повторно, иначе план и запрос расходятся (D4/D7/D11). Легаси-режим
  /// (`null`) сохраняет прежний отбор [selectVisionDocumentImages].
  ///
  /// Лимиты числа/байт — из [resolveGenerationRequestLimits] (один источник с
  /// планировщиком). Дубли байтов не отправляются дважды; исключённые id
  /// возвращаются в [skippedIds] для диагностики, а не теряются молча.
  _DocumentPartsResult _withDocumentImages(
    ProviderAccount account,
    List<GenerationAttachment> attachments,
    List<DocumentImage> images,
    List<DocumentImage>? explicitParts, {
    required GenerationRequestLimits limits,
  }) {
    if (images.isEmpty) {
      return _DocumentPartsResult(
        attachments: attachments,
        sentIds: const <String>[],
        skippedIds: const <String>[],
      );
    }
    if (!account.supportsVision) {
      if (explicitParts != null && explicitParts.isNotEmpty) {
        // План не должен был отправлять части без Vision; это ошибка
        // согласования, а не молчаливая потеря изображения.
        throw const GenerationException(
          GenerationErrorCode.visionUnsupported,
          details: 'План содержит image-части, а модель без Vision',
          failureReason: GenerationFailureReason.unsupportedModality,
        );
      }
      return _DocumentPartsResult(
        attachments: attachments,
        sentIds: const <String>[],
        skippedIds: const <String>[],
      );
    }
    final int? explicitCount = explicitParts?.length;
    if (explicitCount != null && explicitCount > images.length) {
      throw ArgumentError.value(
        explicitCount,
        'documentImageParts',
        'Частей больше, чем изображений каталога',
      );
    }
    final List<DocumentImage> selected = explicitCount != null
        ? images.take(explicitCount).toList(growable: false)
        : selectVisionDocumentImages(
            images,
            maxImages: limits.maxImagesPerRequest,
            maxBytes: limits.maxImageBytesPerRequest,
          );
    final List<GenerationAttachment> parts = <GenerationAttachment>[];
    final List<String> sentIds = <String>[];
    final List<String> skippedIds = <String>[];
    final Set<String> digests = <String>{};
    for (final DocumentImage image in selected) {
      if (image.bytes.isEmpty) {
        skippedIds.add(image.id);
        continue;
      }
      final String digest = documentImageDigest(image.bytes);
      if (!digests.add(digest)) {
        skippedIds.add(image.id);
        continue;
      }
      // Легаси-отбор не знает per-image лимит — проверяем его здесь; явный
      // план уже учёл этот лимит, поэтому его части не фильтруем.
      if (explicitCount == null &&
          image.bytes.length > limits.maxImageBytesPerImage) {
        skippedIds.add(image.id);
        continue;
      }
      parts.add(
        GenerationAttachment(
          fileName: image.fileName,
          mediaType: image.mediaType,
          bytes: image.bytes,
          // Подпись каталога идёт текстом перед частью: модель однозначно
          // сопоставляет изображение с `image_id`.
          label: imageCatalogLine(image),
        ),
      );
      sentIds.add(image.id);
    }
    return _DocumentPartsResult(
      attachments: <GenerationAttachment>[...attachments, ...parts],
      sentIds: List<String>.unmodifiable(sentIds),
      skippedIds: List<String>.unmodifiable(skippedIds),
    );
  }

  /// Проверяет вложения до сборки запроса (итерация 7.8).
  ///
  /// Порядок важен: сначала vision модели, затем PDF-возможность протокола и
  /// лимит; ошибка не доходит до сети и не тратит токены. Лимит байт — из
  /// единого резолвера лимитов [GenerationRequestLimits] (TASK 03), чтобы
  /// сервис и план не расходились; при неизвестности — консервативное
  /// допущение приложения (инфраструктура, не характеристика модели).
  void _validateAttachments(
    ProviderAccount account,
    List<GenerationAttachment> images,
    GenerationRequestLimits limits,
  ) {
    final int maxBytes = limits.maxImageBytesPerImage;
    for (final GenerationAttachment image in images) {
      if (!account.supportsVision) {
        throw GenerationException(
          image.isPdfPage
              ? GenerationErrorCode.pdfScanVisionRequired
              : image.isPdf
              ? GenerationErrorCode.fileWithoutTextAndVision
              : GenerationErrorCode.visionUnsupported,
          details: 'Модель не поддерживает изображения',
          failureReason: GenerationFailureReason.unsupportedModality,
        );
      }
      if (image.bytes.length > maxBytes) {
        throw GenerationException(
          GenerationErrorCode.attachmentTooLarge,
          details: 'Вложение больше лимита $maxBytes байт',
          failureReason: GenerationFailureReason.unsupportedModality,
        );
      }
      if (image.isPdf && !account.protocol.supportsPdfAttachments) {
        throw const GenerationException(
          GenerationErrorCode.pdfScanUnsupported,
          details: 'Протокол не принимает PDF как документ',
          failureReason: GenerationFailureReason.unsupportedModality,
        );
      }
    }
  }

  /// Текст блока `<materials>` для image-only запроса.
  ///
  /// Каждый файл начинается со строки «Файл: <имя>» (SPEC A8.1, промпт v5);
  /// сами изображения/страницы передаются провайдеру отдельными частями.
  String _attachmentMaterials(List<GenerationAttachment> images) {
    final List<String> names = <String>[];
    for (final GenerationAttachment image in images) {
      if (!names.contains(image.fileName)) names.add(image.fileName);
    }
    return names.map((String name) => 'Файл: $name').join('\n');
  }

  /// Пожелания после санитизации; пустые — не передаются.
  String? _sanitizedWishes(String? wishes) {
    if (wishes == null) return null;
    final String sanitized = textSanitizer.sanitize(wishes);
    return sanitized.isEmpty ? null : sanitized;
  }

  /// Сводка продолжения после санитизации; пустая — не передаётся.
  ///
  /// Текст адресован модели и не содержит пользовательских данных сверх уже
  /// созданных карточек (front/back/теги этого запуска).
  String? _sanitizedContinuation(String? continuation) {
    if (continuation == null) return null;
    final String sanitized = textSanitizer.sanitize(continuation);
    return sanitized.isEmpty ? null : sanitized;
  }

  /// Пожелания + сводка продолжения: исходный текст пользователя не меняется.
  String? _mergeWishes(String? wishes, String? continuation) {
    if (continuation == null) return wishes;
    if (wishes == null) return continuation;
    return '$wishes\n\n$continuation';
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

/// Результат отбора image-частей документа: вложения запроса и id частей.
class _DocumentPartsResult {
  const _DocumentPartsResult({
    required this.attachments,
    required this.sentIds,
    required this.skippedIds,
  });

  /// Вложения пользователя + image-части документов.
  final List<GenerationAttachment> attachments;

  /// id (`img1…`) каталога, реально ушедшие частями.
  final List<String> sentIds;

  /// id, исключённые сервисом (пустые байты/дубли/размер) — для диагностики.
  final List<String> skippedIds;
}
