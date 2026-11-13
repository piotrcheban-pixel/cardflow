/// Сервис генерации карточек: ключ → запрос → HTTP → ответ → валидация.
///
/// Один вызов модели на один фрагмент (чанкинг и `generation_jobs` — итерация 3c).
library;

import 'dart:convert';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/generation_prompt.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// Вызов модели и локальная валидация ответа (SPEC A8.2, A8.4–A8.6).
class CardGenerationService {
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

  /// Адаптеры провайдеров (по одному на провайдер).
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
  Future<GenerationResult> generate(
    GenerationRequest request, {
    CancelToken? cancelToken,
  }) async {
    final adapter = _adapterFor(request.provider);
    final apiKey = (await apiKeyStore.read(request.provider))?.trim();
    if (apiKey == null || apiKey.isEmpty) {
      throw const GenerationException(GenerationErrorCode.missingApiKey);
    }

    final userContent = buildGenerationUserContent(
      materialsText: request.materialsText,
      wishes: request.wishes,
      limit: request.limit,
    );
    final providerRequest = adapter.buildRequest(
      apiKey: apiKey,
      model: request.model,
      systemPrompt: systemPrompt,
      userContent: userContent,
      maxOutputTokens: maxOutputTokens,
    );

    final rawJson = await httpClient.postJson(
      providerRequest,
      cancelToken: cancelToken,
    );
    final rawResponse = adapter.parseResponse(rawJson);
    final decoded = _decodeCardsJson(rawResponse.cardsJson);

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
      provider: request.provider,
      model: request.model,
      promptVersion: promptVersion,
      cards: cards,
      usage: rawResponse.usage,
    );
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

  Object? _decodeCardsJson(String cardsJson) {
    try {
      return jsonDecode(cardsJson);
    } on FormatException {
      throw const GenerationException(
        GenerationErrorCode.invalidResponse,
        details: 'Ответ модели не является JSON',
      );
    }
  }
}
