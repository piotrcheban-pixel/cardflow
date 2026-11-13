import 'package:dio/dio.dart';

import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// In-memory хранилище ключей API для тестов (без платформы).
class FakeApiKeyStore implements ApiKeyStore {
  /// Создаёт хранилище; [keys] — начальные ключи.
  FakeApiKeyStore([Map<GenerationProvider, String>? keys])
    : _keys = <GenerationProvider, String>{...?keys};

  final Map<GenerationProvider, String> _keys;

  /// Сколько раз читали ключ.
  int readCalls = 0;

  /// Сколько раз писали ключ.
  int writeCalls = 0;

  /// Сколько раз удаляли ключ.
  int deleteCalls = 0;

  /// Текущее содержимое хранилища (открыто для проверок в тестах).
  Map<GenerationProvider, String> get keys => _keys;

  @override
  Future<String?> read(GenerationProvider provider) async {
    readCalls++;
    return _keys[provider];
  }

  @override
  Future<void> write(GenerationProvider provider, String apiKey) async {
    writeCalls++;
    _keys[provider] = apiKey;
  }

  @override
  Future<void> delete(GenerationProvider provider) async {
    deleteCalls++;
    _keys.remove(provider);
  }
}

/// Аргументы, с которыми фейковый адаптер строил запрос.
class RecordedBuildArgs {
  /// Создаёт запись аргументов.
  RecordedBuildArgs({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.userContent,
    required this.maxOutputTokens,
  });

  /// Переданный ключ.
  final String apiKey;

  /// Переданная модель.
  final String model;

  /// Переданный системный промпт.
  final String systemPrompt;

  /// Переданное пользовательское сообщение.
  final String userContent;

  /// Переданный лимит ответа.
  final int maxOutputTokens;
}

/// Фейковый адаптер провайдера: запоминает аргументы и отдаёт заданный ответ.
class FakeProviderAdapter implements GenerationProviderAdapter {
  /// Создаёт адаптер.
  FakeProviderAdapter({
    this.provider = GenerationProvider.openai,
    this.cardsJson = '{"cards":[]}',
    this.usage = const TokenUsage(),
    this.error,
    this.request,
  });

  @override
  final GenerationProvider provider;

  /// JSON-строка ответа модели.
  final String cardsJson;

  /// Расход токенов в ответе.
  final TokenUsage usage;

  /// Если задано — `parseResponse` бросит это исключение.
  final Object? error;

  /// Если задано — `buildRequest` вернёт этот запрос.
  final ProviderRequest? request;

  /// Последние аргументы `buildRequest`.
  RecordedBuildArgs? buildArgs;

  /// Сколько раз строили запрос.
  int buildCalls = 0;

  /// Сколько раз разбирали ответ.
  int parseCalls = 0;

  @override
  ProviderRequest buildRequest({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContent,
    required int maxOutputTokens,
  }) {
    buildCalls++;
    buildArgs = RecordedBuildArgs(
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      userContent: userContent,
      maxOutputTokens: maxOutputTokens,
    );
    return request ??
        ProviderRequest(
          uri: Uri.parse('https://provider.test/v1/generate'),
          headers: <String, String>{'x-test-key': apiKey},
          body: <String, Object?>{'model': model},
        );
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    parseCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return ProviderRawResponse(cardsJson: cardsJson, usage: usage);
  }
}

/// Фейковый HTTP-транспорт: запоминает запросы и отдаёт заданный JSON/ошибку.
class FakeGenerationTransport implements GenerationTransport {
  /// Создаёт транспорт.
  FakeGenerationTransport({
    this.response,
    this.error,
    this.callsBeforeResponse = 0,
  });

  /// JSON-ответ по умолчанию.
  final Map<String, Object?>? response;

  /// Если задано — будут брошено это исключение.
  final Object? error;

  /// Сколько первых вызовов «падать» (для проверки, что сервис не ретраит сам).
  final int callsBeforeResponse;

  /// Все отправленные запросы.
  final List<ProviderRequest> requests = <ProviderRequest>[];

  /// Число вызовов транспорта.
  int calls = 0;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    requests.add(request);
    if (calls <= callsBeforeResponse) {
      throw const FormatException('fake transient failure');
    }
    final failure = error;
    if (failure != null) throw failure;
    return response ?? <String, Object?>{};
  }
}
