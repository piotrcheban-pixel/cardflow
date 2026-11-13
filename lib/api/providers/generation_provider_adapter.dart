/// Контракт адаптера провайдера (SPEC A8.2): чистые построение запроса и
/// разбор ответа, без сети и UI.
library;

import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// HTTP-запрос провайдера в терминах метода/URL/заголовков/JSON-тела.
class ProviderRequest {
  /// Создаёт запрос.
  const ProviderRequest({
    required this.uri,
    required this.headers,
    required this.body,
  });

  /// Полный URL запроса.
  final Uri uri;

  /// Заголовки (ключ API — только здесь, никогда в URL).
  final Map<String, String> headers;

  /// JSON-тело запроса.
  final Map<String, Object?> body;
}

/// Ответ провайдера после проверки причины остановки.
class ProviderRawResponse {
  /// Создаёт разобранный ответ.
  const ProviderRawResponse({required this.cardsJson, required this.usage});

  /// JSON-строка с ответом модели по канонической схеме A8.4.
  final String cardsJson;

  /// Расход токенов (если провайдер сообщил).
  final TokenUsage usage;
}

/// Адаптер одного провайдера.
abstract interface class GenerationProviderAdapter {
  /// Провайдер этого адаптера.
  GenerationProvider get provider;

  /// Строит запрос к provider API.
  ProviderRequest buildRequest({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContent,
    required int maxOutputTokens,
  });

  /// Разбирает ответ провайдера; причины остановки/отказы → `GenerationException`.
  ProviderRawResponse parseResponse(Map<String, Object?> json);
}
