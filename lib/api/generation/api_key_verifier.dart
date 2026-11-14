/// Проверка подключения провайдера минимальным запросом (SPEC A6.6, ADR-019 §5,
/// ADR-020).
///
/// Использует те же адаптеры и транспорт, что и генерация (A8.2): заголовки,
/// адреса и формат запроса не дублируются. Тела ответов и ключи наружу не
/// попадают — только [ApiKeyCheckStatus]; сервер не пишет `generation_jobs`.
library;

import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/provider_account.dart';

/// Результат проверки подключения.
enum ApiKeyCheckStatus {
  /// Провайдер принял запрос (HTTP 2xx).
  valid,

  /// Провайдер отверг ключ (401/403).
  invalidKey,

  /// Ключ не сохранён, а провайдер требует ключ.
  missingKey,

  /// Нет сети/таймаут.
  noConnection,

  /// Лимит запросов (429).
  rateLimited,

  /// Аккаунт не настроен (адрес/модель).
  providerNotConfigured,

  /// Прочие ошибки (4xx/5xx/неожиданные).
  unexpected,
}

/// Итог проверки; без ключей и тел ответов.
class ApiKeyCheckResult {
  /// Создаёт результат.
  const ApiKeyCheckResult(this.status);

  /// Статус для маппинга в ARB.
  final ApiKeyCheckStatus status;
}

/// Проверяет провайдера одним синтетическим запросом.
class ApiKeyVerifier {
  /// Создаёт проверяльщик.
  ApiKeyVerifier({
    required this.adapters,
    required this.apiKeyStore,
    required this.transport,
  });

  /// Адаптеры провайдеров (те же, что у генерации).
  final List<GenerationProviderAdapter> adapters;

  /// Хранилище ключей (только secure storage).
  final ApiKeyStore apiKeyStore;

  /// Транспорт генерации (Dio + retry + redaction).
  final GenerationTransport transport;

  /// Минимальный запрос: ответ не разбирается, важен только HTTP-успех.
  Future<ApiKeyCheckResult> check(ProviderAccount account) async {
    if (!account.isConfigured) {
      return const ApiKeyCheckResult(ApiKeyCheckStatus.providerNotConfigured);
    }
    final String? apiKey = (await apiKeyStore.read(account.id))?.trim();
    if (account.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      return const ApiKeyCheckResult(ApiKeyCheckStatus.missingKey);
    }

    final GenerationProviderAdapter adapter = _adapterFor(
      account.protocol.adapterProvider,
    );
    final ProviderRequest request = adapter.buildRequest(
      apiKey: apiKey ?? '',
      model: account.modelId.trim(),
      systemPrompt: 'Answer with a single short word.',
      userContent: 'OK',
      maxOutputTokens: 8,
      baseUrl: account.baseUrl.trim(),
      strictSchema: false,
    );

    try {
      await transport.postJson(request);
      return const ApiKeyCheckResult(ApiKeyCheckStatus.valid);
    } on GenerationException catch (error) {
      return ApiKeyCheckResult(_statusFor(error.code));
    } on Object {
      return const ApiKeyCheckResult(ApiKeyCheckStatus.unexpected);
    }
  }

  GenerationProviderAdapter _adapterFor(GenerationProvider provider) {
    for (final GenerationProviderAdapter adapter in adapters) {
      if (adapter.provider == provider) return adapter;
    }
    throw ArgumentError.value(provider.wireName, 'provider');
  }

  static ApiKeyCheckStatus _statusFor(GenerationErrorCode code) {
    return switch (code) {
      GenerationErrorCode.missingApiKey => ApiKeyCheckStatus.missingKey,
      GenerationErrorCode.invalidApiKey => ApiKeyCheckStatus.invalidKey,
      GenerationErrorCode.rateLimited => ApiKeyCheckStatus.rateLimited,
      GenerationErrorCode.timeout ||
      GenerationErrorCode.network => ApiKeyCheckStatus.noConnection,
      GenerationErrorCode.providerNotConfigured =>
        ApiKeyCheckStatus.providerNotConfigured,
      _ => ApiKeyCheckStatus.unexpected,
    };
  }
}
