/// HTTP-реализация порта [KnowledgeMapCaller] поверх существующих адаптеров
/// провайдеров (TASK «Срез 11», часть 2, п. 5).
///
/// Ничего не переписано: запрос строится тем же `buildRequest` адаптера, что и
/// карточки, отправляется существующим [GenerationTransport] (таймауты,
/// отмена, редактирование логов), ответ нормализуется
/// [ProviderResponseNormalizer]. Промпт — `gen-map-v1`
/// (`lib/api/prompts/understanding_prompt.dart`), схема ответа — каноническая
/// карта знаний (`canonicalKnowledgeMapSchema`), спроецированная под протокол
/// той же машинерией, что и схема карточек A8.4.
///
/// Повторы — [RetryPolicy] этапа (429 `Retry-After`, 5xx, таймаут/сеть);
/// решение принимается здесь, потому что у Understanding один фрагмент = один
/// запрос, и движку батчей его журнал не подходит. 400/401/403 не повторяются.
///
/// `usage` каждого ответа возвращается в [KnowledgeMapRawResponse.usage] —
/// Understanding суммирует его в отчёт прогона. Ответ, оборванный по
/// `max_tokens` (`finish_reason: length`), помечается
/// [KnowledgeMapRawResponse.truncated]; деление на части — забота сервиса
/// Understanding, который знает блоки раздела.
library;

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/generation/knowledge_map_caller.dart';
import 'package:cardflow/api/generation/provider_result.dart';
import 'package:cardflow/api/generation/provider_schema.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Схема ответа карты знаний под протокол аккаунта.
///
/// Канон живёт в домене (`canonicalKnowledgeMapSchema`), проекции — та же
/// функция, что у карточек A8.4: адаптеры не получают второго набора правил.
Map<String, Object?> knowledgeMapSchemaFor(ProviderSchemaFlavor flavor) =>
    projectCardSchema(flavor, canonicalSchema: canonicalKnowledgeMapSchema);

/// Порт Understanding поверх адаптеров, транспорта и [RetryPolicy].
class HttpKnowledgeMapCaller implements KnowledgeMapCaller {
  /// Создаёт вызов для аккаунта [account].
  ///
  /// [transport] — существующий HTTP-транспорт генерации; [apiKeyStore] —
  /// ключи аккаунтов (значение в логи не попадает); [adapters] — production
  /// набор `generationAdapters`; [maxOutputTokens] — лимит вывода по умолчанию
  /// (запрос может задать свой).
  HttpKnowledgeMapCaller({
    required this.transport,
    required this.apiKeyStore,
    required this.account,
    this.adapters = generationAdapters,
    this.normalizer = const ProviderResponseNormalizer(),
    RetryPolicy? retryPolicy,
    Future<void> Function(Duration duration)? delay,
    this.maxOutputTokens = defaultMaxOutputTokens,
  }) : retryPolicy = retryPolicy ?? RetryPolicy(),
       delay = delay ?? Future<void>.delayed;

  /// Лимит вывода одного запроса Understanding по умолчанию.
  static const int defaultMaxOutputTokens = 4096;

  /// Транспорт запросов провайдера.
  final GenerationTransport transport;

  /// Хранилище ключей API по аккаунтам.
  final ApiKeyStore apiKeyStore;

  /// Аккаунт провайдера: протокол, адрес, модель, id ключа.
  final ProviderAccount account;

  /// Адаптеры провайдеров.
  final List<GenerationProviderAdapter> adapters;

  /// Нормализация ответа адаптера в единый [ProviderResult].
  final ProviderResponseNormalizer normalizer;

  /// Политика повторов (`Retry-After`, 5xx, таймаут).
  final RetryPolicy retryPolicy;

  /// Пауза перед повтором (инжектируется в тестах).
  final Future<void> Function(Duration duration) delay;

  /// Лимит вывода, если запрос его не задал.
  final int maxOutputTokens;

  @override
  Future<KnowledgeMapRawResponse> extract(KnowledgeMapRequest request) async {
    final GenerationProviderAdapter adapter = _adapterFor(account.protocol);
    final String apiKey = await apiKeyStore.read(account.id) ?? '';
    final ProviderRequest providerRequest = adapter.buildRequest(
      apiKey: apiKey,
      model: account.modelId,
      systemPrompt: request.systemPrompt,
      userContent: request.userContent,
      maxOutputTokens: request.maxOutputTokens ?? maxOutputTokens,
      baseUrl: account.baseUrl,
      responseSchema: knowledgeMapSchemaFor(_flavorOf(account.protocol)),
    );

    var attempt = 1;
    while (true) {
      try {
        final Map<String, Object?> json = await transport.postJson(
          providerRequest,
        );
        final ProviderResult result = normalizer.normalize(adapter, json);
        if (result.isTruncated) {
          // Оборванный ответ — не сбой: сервис Understanding делит фрагмент по
          // блокам в пределах max_tokens (TASK п. 5), а не теряет весь раздел.
          return KnowledgeMapRawResponse(
            json: result.content,
            usage: result.usage,
            truncated: true,
          );
        }
        if (result.isError) {
          throw GenerationException(
            result.rawError ?? GenerationErrorCode.invalidResponse,
            details: result.detail,
          );
        }
        return KnowledgeMapRawResponse(
          json: result.content,
          usage: result.usage,
        );
      } on GenerationException catch (error) {
        if (error.code == GenerationErrorCode.cancelled) rethrow;
        final RetryDecision decision = retryPolicy.decide(
          attempt: attempt,
          statusCode: CardsBatchEngine.statusFor(error.code),
          isTimeout: error.code == GenerationErrorCode.timeout,
          isConnectionError: error.code == GenerationErrorCode.network,
          retryAfter: error.retryAfter,
        );
        if (!decision.shouldRetry) rethrow;
        await delay(decision.delay);
        attempt++;
      }
    }
  }

  /// Адаптер протокола аккаунта.
  GenerationProviderAdapter _adapterFor(ProviderProtocol protocol) {
    final GenerationProvider provider = protocol.adapterProvider;
    for (final GenerationProviderAdapter adapter in adapters) {
      if (adapter.provider == provider) return adapter;
    }
    throw ArgumentError.value(
      provider,
      'protocol',
      'Нет адаптера для протокола провайдера',
    );
  }

  /// Проекция схемы под протокол аккаунта.
  static ProviderSchemaFlavor _flavorOf(ProviderProtocol protocol) =>
      switch (protocol) {
        ProviderProtocol.openai ||
        ProviderProtocol.openaiCompletions => ProviderSchemaFlavor.openAi,
        ProviderProtocol.geminiGenerateContent => ProviderSchemaFlavor.gemini,
        ProviderProtocol.anthropicMessages => ProviderSchemaFlavor.anthropic,
      };
}
