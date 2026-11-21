/// Контракт адаптера провайдера (SPEC A8.2): чистые построение запроса и
/// разбор ответа, без сети и UI.
library;

import 'dart:convert';

import 'package:cardflow/domain/generation/generation_attachment.dart';
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

/// Фактические байты тела запроса: UTF-8 сериализованного JSON (§3.4).
///
/// Это единственная корректная мера «размера запроса»: адаптер добавляет
/// системный промпт, JSON-схему ответа, ключи протокола и экранирование,
/// поэтому оценка «текст + base64» всегда занижена.
int serializedRequestBytes(ProviderRequest request) =>
    utf8.encode(jsonEncode(request.body)).length;

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
  ///
  /// [baseUrl] — базовый адрес OpenAI-совместимого сервера (ADR-013);
  /// используется только адаптером `OpenAiCompatibleAdapter`, остальные
  /// адаптеры его игнорируют.
  ///
  /// [strictSchema] — включать ли `response_format` со strict-схемой; только
  /// для OpenAI-совместимого провайдера (fallback для серверов без поддержки
  /// strict), остальные адаптеры игнорируют.
  ///
  /// [sendMaxTokens] — передавать ли `max_tokens` (`maxOutputTokens`); только
  /// для OpenAI-совместимого провайдера: часть таких серверов требует
  /// `max_completion_tokens` и отклоняет `max_tokens` (ADR-021). Anthropic и
  /// Gemini передают лимит всегда, OpenAI — не передаёт (устаревшее поле).
  ///
  /// [images] — вложения фрагмента (итерация 7.8). Адаптер сам строит
  /// провайдерские image/document-части; PDF, который протокол не принимает,
  /// отвергается `GenerationException(pdfScanUnsupported)`.
  ProviderRequest buildRequest({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContent,
    required int maxOutputTokens,
    String? baseUrl,
    bool strictSchema = true,
    bool sendMaxTokens = true,
    List<GenerationAttachment> images = const <GenerationAttachment>[],
  });

  /// Разбирает ответ провайдера; причины остановки/отказы → `GenerationException`.
  ProviderRawResponse parseResponse(Map<String, Object?> json);
}
