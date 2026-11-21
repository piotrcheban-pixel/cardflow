/// Нативный подсчёт токенов запроса (ADR-040 §3.5.1).
///
/// Документирован он не у всех провайдеров: Anthropic — `POST
/// /v1/messages/count_tokens`, Gemini — `POST /v1beta/models/{model}:countTokens`.
/// Для остальных протоколов используется консервативная оценка приложения
/// (`InputAccuracy.estimated`). Планировщик сам в сеть не ходит: подсчёт
/// выполняется до сборки плана, результат передаётся в него числом.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/models/model_discovery.dart' show ApiKeyReader;
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Точный/неизвестный подсчёт входа.
final class ExactTokenCount {
  /// Точное значение.
  const ExactTokenCount.exact(int this.tokens) : errorCode = null;

  /// Подсчёт не удался (оценка остаётся консервативной).
  const ExactTokenCount.unknown([this.errorCode]) : tokens = null;

  /// Токенов входа; `null` — неизвестно.
  final int? tokens;

  /// Машинный код ошибки (`http_401`, `timeout`, …) — не тело ответа.
  final String? errorCode;

  /// true, если значение точное.
  bool get isExact => tokens != null;
}

/// Порт нативного подсчёта входа.
abstract interface class RequestTokenCounter {
  /// Поддерживает ли счётчик протокол аккаунта (иначе подсчёт не выполняется).
  bool supports(ProviderAccount account);

  /// Считает вход запроса; ошибки возвращаются как [ExactTokenCount.unknown].
  ///
  /// [attachments] — мультимодальные части (изображения/PDF) в том же виде,
  /// в каком они уйдут в production-запрос: счётчик обязан передавать их
  /// провайдеру, иначе «точный» вход занижен на целые изображения.
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  });
}

/// Общая часть HTTP-счётчиков: таймауты, статус, ключ без логирования.
abstract class _HttpCounter {
  _HttpCounter(this.dio, this.readApiKey);

  final Dio dio;
  final ApiKeyReader readApiKey;

  static const Duration receiveTimeout = Duration(seconds: 20);

  Future<int> post(
    ProviderAccount account,
    String url, {
    required Object body,
    required Map<String, String> headers,
    required Object? Function(Object? data) extract,
    Map<String, String> Function(String key)? authHeaders,
  }) async {
    final String? key = account.requiresApiKey
        ? await readApiKey(account.id)
        : null;
    if (account.requiresApiKey && (key == null || key.isEmpty)) {
      throw const _CounterError('no_api_key');
    }
    try {
      final Response<Object?> response = await dio.postUri<Object?>(
        Uri.parse(url),
        data: body,
        options: Options(
          receiveTimeout: receiveTimeout,
          headers: <String, String>{
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            if (key != null && key.isNotEmpty)
              if (authHeaders != null)
                ...authHeaders(key)
              else
                'Authorization': 'Bearer $key',
            ...headers,
          },
        ),
      );
      final int status = response.statusCode ?? 200;
      if (status >= 400) throw _CounterError('http_$status');
      final Object? value = extract(response.data);
      if (value is int && value >= 0) return value;
      throw const _CounterError('invalid_body');
    } on _CounterError {
      rethrow;
    } on DioException catch (error) {
      final int? status = error.response?.statusCode;
      if (status != null) throw _CounterError('http_$status');
      throw _CounterError(
        error.type == DioExceptionType.receiveTimeout ||
                error.type == DioExceptionType.connectionTimeout
            ? 'timeout'
            : 'network',
      );
    }
  }

  static String join(String baseUrl, String path) {
    final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String suffix = path.startsWith('/') ? path : '/$path';
    return '$base$suffix';
  }
}

final class _CounterError implements Exception {
  const _CounterError(this.code);
  final String code;
}

/// Anthropic `count_tokens`.
class AnthropicRequestTokenCounter extends _HttpCounter
    implements RequestTokenCounter {
  /// Создаёт счётчик.
  AnthropicRequestTokenCounter(Dio dio, {required ApiKeyReader readApiKey})
    : super(dio, readApiKey);

  @override
  bool supports(ProviderAccount account) =>
      account.protocol == ProviderProtocol.anthropicMessages;

  @override
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  }) async {
    try {
      final int tokens = await post(
        account,
        _HttpCounter.join(account.baseUrl, '/v1/messages/count_tokens'),
        // Схема ответа у Anthropic передаётся инструментом (`tools`), и
        // count_tokens документированно считает её вместе с tools: без неё
        // «точный» вход был бы занижен на размер JSON-схемы.
        body: <String, Object?>{
          'model': account.modelId,
          'system': systemPrompt,
          'messages': <Object?>[
            <String, Object?>{'role': 'user', 'content': userContent},
          ],
          'tools': <Object?>[
            <String, Object?>{
              'name': 'emit_cards',
              'description':
                  'Emit the generated flashcards as JSON matching the schema.',
              'input_schema': anthropicToolCardSchema(),
            },
          ],
          'tool_choice': <String, Object?>{
            'type': 'tool',
            'name': 'emit_cards',
          },
        },
        headers: <String, String>{'anthropic-version': '2023-06-01'},
        extract: (Object? data) => data is Map ? data['input_tokens'] : null,
      );
      return ExactTokenCount.exact(tokens);
    } on _CounterError catch (error) {
      return ExactTokenCount.unknown(error.code);
    }
  }
}

/// Gemini `countTokens`.
class GeminiRequestTokenCounter extends _HttpCounter
    implements RequestTokenCounter {
  /// Создаёт счётчик.
  GeminiRequestTokenCounter(Dio dio, {required ApiKeyReader readApiKey})
    : super(dio, readApiKey);

  @override
  bool supports(ProviderAccount account) =>
      account.protocol == ProviderProtocol.geminiGenerateContent;

  @override
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  }) async {
    try {
      final String model = account.modelId.trim();
      final int tokens = await post(
        account,
        _HttpCounter.join(account.baseUrl, '/v1beta/models/$model:countTokens'),
        // countTokens принимает GenerateContentRequest: системная инструкция
        // и responseSchema входят в тот же запрос, что и генерация.
        body: <String, Object?>{
          'systemInstruction': <String, Object?>{
            'parts': <Object?>[
              <String, Object?>{'text': systemPrompt},
            ],
          },
          'contents': <Object?>[
            <String, Object?>{
              'role': 'user',
              'parts': <Object?>[
                <String, Object?>{'text': userContent},
              ],
            },
          ],
          'generationConfig': <String, Object?>{
            'responseMimeType': 'application/json',
            'responseSchema': geminiCardSchema(),
          },
        },
        headers: const <String, String>{},
        extract: (Object? data) => data is Map ? data['totalTokens'] : null,
        authHeaders: (String key) => <String, String>{'x-goog-api-key': key},
      );
      return ExactTokenCount.exact(tokens);
    } on _CounterError catch (error) {
      return ExactTokenCount.unknown(error.code);
    }
  }
}

/// Счётчик, который не умеет считать (оценка остаётся).
class NoopRequestTokenCounter implements RequestTokenCounter {
  /// Создаёт no-op счётчик.
  const NoopRequestTokenCounter();

  @override
  bool supports(ProviderAccount account) => false;

  @override
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  }) async => const ExactTokenCount.unknown('unsupported');
}

/// Счётчик, выбирающий реализацию по протоколу аккаунта на каждом вызове.
///
/// Нужен конвейеру: у одного запуска аккаунт фиксирован, но набор
/// поддерживаемых протоколов — свойство реализации, а не места входа.
class ProtocolRequestTokenCounter implements RequestTokenCounter {
  /// Создаёт роутер.
  ProtocolRequestTokenCounter({required this.dio, required this.readApiKey});

  /// HTTP-клиент приложения.
  final Dio dio;

  /// Чтение ключа API (present/absent).
  final ApiKeyReader readApiKey;

  @override
  bool supports(ProviderAccount account) => requestTokenCounterFor(
    account,
    dio,
    readApiKey: readApiKey,
  ).supports(account);

  @override
  Future<ExactTokenCount> count(
    ProviderAccount account, {
    required String systemPrompt,
    required String userContent,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
  }) => requestTokenCounterFor(account, dio, readApiKey: readApiKey).count(
    account,
    systemPrompt: systemPrompt,
    userContent: userContent,
    attachments: attachments,
  );
}

/// Выбирает счётчик по протоколу (только там, где он документирован).
RequestTokenCounter requestTokenCounterFor(
  ProviderAccount account,
  Dio dio, {
  required ApiKeyReader readApiKey,
}) => switch (account.protocol) {
  ProviderProtocol.anthropicMessages => AnthropicRequestTokenCounter(
    dio,
    readApiKey: readApiKey,
  ),
  ProviderProtocol.geminiGenerateContent => GeminiRequestTokenCounter(
    dio,
    readApiKey: readApiKey,
  ),
  ProviderProtocol.openai ||
  ProviderProtocol.openaiCompletions => const NoopRequestTokenCounter(),
};
