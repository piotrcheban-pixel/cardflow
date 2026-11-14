/// Сервис генерации карточек: аккаунт → запрос → HTTP → ответ → валидация.
///
/// Один вызов модели на один фрагмент (чанкинг и `generation_jobs` — пайплайн).
/// Аккаунт провайдера (ADR-020) задаёт протокол, базовый адрес, модель и id
/// ключа: ключ читается только из `ApiKeyStore`, адрес и модель — из аккаунта.
/// Для OpenAI-совместимого протокола при отказе сервера от strict-схемы
/// выполняется один fallback-запрос без `response_format` с той же локальной
/// валидацией (ADR-013).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Вызов модели и локальная валидация ответа (SPEC A8.2, A8.4–A8.6).
class CardGenerationService implements GenerationCaller {
  /// Создаёт сервис.
  CardGenerationService({
    required this.adapters,
    required this.apiKeyStore,
    required this.httpClient,
    CardResponseSchema? responseSchema,
    CardContentValidator? contentValidator,
    this.systemPrompt = systemPromptGenRuV2,
    this.promptVersion = systemPromptVersion,
    this.maxOutputTokens = 8192,
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

  /// Системный промпт (скрыт от UI).
  final String systemPrompt;

  /// Версия системного промпта для `generation_jobs`.
  final String promptVersion;

  /// Верхняя граница ответа модели (Anthropic требует `max_tokens`).
  final int maxOutputTokens;

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

    final String userContent = buildGenerationUserContent(
      materialsText: request.materialsText,
      wishes: request.wishes,
      limit: request.limit,
    );

    ProviderRawResponse rawResponse;
    try {
      rawResponse = await _postAndParse(
        adapter: adapter,
        apiKey: apiKey ?? '',
        model: model,
        baseUrl: baseUrl,
        userContent: userContent,
        strictSchema: true,
        cancelToken: cancelToken,
      );
    } on GenerationException catch (error) {
      // Fallback для серверов без поддержки strict `response_format`
      // (ADR-013): один повтор без response_format, ответ всё равно
      // проверяется локальной схемой A8.4 ниже.
      if (!tolerantFallback || error.code != GenerationErrorCode.badRequest) {
        rethrow;
      }
      rawResponse = await _postAndParse(
        adapter: adapter,
        apiKey: apiKey ?? '',
        model: model,
        baseUrl: baseUrl,
        userContent: userContent,
        strictSchema: false,
        cancelToken: cancelToken,
      );
    }

    final decoded = _decodeCardsJson(
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
      sourceText: request.materialsText,
    );
    return GenerationResult(
      provider: account.protocol.adapterProvider,
      model: model,
      promptVersion: promptVersion,
      cards: cards,
      usage: rawResponse.usage,
    );
  }

  /// Строит запрос адаптером и разбирает ответ провайдера.
  Future<ProviderRawResponse> _postAndParse({
    required GenerationProviderAdapter adapter,
    required String apiKey,
    required String model,
    required String? baseUrl,
    required String userContent,
    required bool strictSchema,
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
    );
    final rawJson = await httpClient.postJson(
      providerRequest,
      cancelToken: cancelToken,
    );
    return adapter.parseResponse(rawJson);
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

  /// Декодирует JSON ответа модели.
  ///
  /// Для OpenAI-совместимого протокола допускается ответ, обёрнутый в
  /// markdown-ограждение или пояснительный текст (локальные модели часто так
  /// делают без strict-схемы); остальные — обязаны вернуть чистый JSON.
  Object? _decodeCardsJson(String cardsJson, {required bool tolerant}) {
    final direct = _tryDecode(cardsJson);
    if (direct.ok) return direct.value;
    if (tolerant) {
      final extracted = _extractJsonObject(cardsJson);
      if (extracted != null) {
        final second = _tryDecode(extracted);
        if (second.ok) return second.value;
      }
    }
    throw const GenerationException(
      GenerationErrorCode.invalidResponse,
      details: 'Ответ модели не является JSON',
    );
  }

  /// Пытается декодировать [value]; не бросает исключений.
  ({bool ok, Object? value}) _tryDecode(String value) {
    try {
      return (ok: true, value: jsonDecode(value));
    } on FormatException {
      return (ok: false, value: null);
    }
  }

  /// Извлекает JSON-объект из markdown-ограждения или текста вокруг него.
  String? _extractJsonObject(String raw) {
    var text = raw.trim();
    final fence = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
