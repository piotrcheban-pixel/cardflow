/// Проверка ключа API минимальным запросом (SPEC A6.6, ADR-019 §5).
///
/// Использует те же адаптеры и транспорт, что и генерация (A8.2): заголовки,
/// адреса и формат запроса не дублируются. Тела ответов и ключи наружу не
/// попадают — только [ApiKeyCheckStatus]; сервер не пишет `generation_jobs`.
library;

import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_endpoint.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_model.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

/// Результат проверки ключа.
enum ApiKeyCheckStatus {
  /// Провайдер принял ключ (HTTP 2xx).
  valid,

  /// Провайдер отверг ключ (401/403).
  invalidKey,

  /// Ключ не сохранён.
  missingKey,

  /// Нет сети/таймаут.
  noConnection,

  /// Лимит запросов (429).
  rateLimited,

  /// OpenAI-совместимый сервер не настроен (адрес/модель).
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

/// Проверяет ключ одним синтетическим запросом провайдера.
class ApiKeyVerifier {
  /// Создаёт проверяльщик.
  ApiKeyVerifier({
    required this.adapters,
    required this.apiKeyStore,
    required this.transport,
    this.generationSettingsStore,
  });

  /// Адаптеры провайдеров (те же, что у генерации).
  final List<GenerationProviderAdapter> adapters;

  /// Хранилище ключей (только secure storage).
  final ApiKeyStore apiKeyStore;

  /// Транспорт генерации (Dio + retry + redaction).
  final GenerationTransport transport;

  /// Настройки OpenAI-совместимого сервера (ADR-013); может быть `null` в срезах.
  final GenerationSettingsStore? generationSettingsStore;

  /// Минимальный запрос: ответ не разбирается, важен только HTTP-успех.
  Future<ApiKeyCheckResult> check(GenerationProvider provider) async {
    final bool isCompatible = provider == GenerationProvider.openaiCompatible;
    final String? rawKey = await apiKeyStore.read(provider);
    final String? apiKey = rawKey?.trim();
    String? baseUrl;
    String model;

    if (isCompatible) {
      final GenerationSettingsStore? store = generationSettingsStore;
      final OpenAiCompatibleSettings settings = store == null
          ? const OpenAiCompatibleSettings()
          : await store.readOpenAiCompatible();
      final OpenAiCompatibleEndpoint endpoint = OpenAiCompatibleEndpoint.parse(
        settings.baseUrl,
      );
      if (!endpoint.isValid || settings.model.trim().isEmpty) {
        return const ApiKeyCheckResult(ApiKeyCheckStatus.providerNotConfigured);
      }
      baseUrl = settings.baseUrl;
      model = settings.model.trim();
    } else {
      if (apiKey == null || apiKey.isEmpty) {
        return const ApiKeyCheckResult(ApiKeyCheckStatus.missingKey);
      }
      final List<GenerationModel> models = generationModelsFor(provider);
      if (models.isEmpty) {
        return const ApiKeyCheckResult(ApiKeyCheckStatus.unexpected);
      }
      model = models.first.id;
    }

    final GenerationProviderAdapter adapter = _adapterFor(provider);
    final ProviderRequest request = adapter.buildRequest(
      apiKey: apiKey ?? '',
      model: model,
      systemPrompt: 'Answer with a single short word.',
      userContent: 'OK',
      maxOutputTokens: 8,
      baseUrl: baseUrl,
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
