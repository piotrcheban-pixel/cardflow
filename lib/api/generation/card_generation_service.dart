/// Сервис генерации карточек: ключ → запрос → HTTP → ответ → валидация.
///
/// Один вызов модели на один фрагмент (чанкинг и `generation_jobs` — итерация 3c).
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
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
  }) {
    throw UnimplementedError('CardGenerationService.generate');
  }
}
