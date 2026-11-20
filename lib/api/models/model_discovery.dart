/// Discovery характеристик модели: резолвер на протокол/провайдера
/// (ADR-039 §3).
///
/// У каждого провайдера свой ответ и своя семантика полей, поэтому здесь нет
/// универсального JSON-парсера: DeepSeek/Groq/Moonshot/OpenRouter имеют свои
/// политики доверия к полям, OpenAI и generic — только список id, Anthropic и
/// Gemini — свои лимиты и пагинация, Ollama — нативные `/api/tags` и
/// `/api/show`.
///
/// Ключ API читается через инжектированный провайдер (secure storage) и не
/// попадает ни в ошибки, ни в `sourceRef` (ссылки без query-параметров).
/// HTTP идёт через общий Dio (`generationDioProvider`), генерационные
/// эндпоинты не вызываются.
library;

import 'dart:async';

import 'package:dio/dio.dart';

import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capability_discovery.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Чтение ключа API по id аккаунта (present/absent; значение не логируется).
typedef ApiKeyReader = Future<String?> Function(String accountId);

/// Политика доверия к полям OpenAI-совместимого `/models`.
enum OpenAiModelFieldPolicy {
  /// Только `id` (OpenAI, generic compatible).
  idsOnly,

  /// Документированные поля конкретного провайдера.
  documented,
}

/// Общая база HTTP-резолверов: таймауты, ошибки без тел, отмена.
abstract class _HttpDiscovery {
  _HttpDiscovery(this.dio, this.readApiKey);

  final Dio dio;
  final ApiKeyReader readApiKey;

  static const Duration receiveTimeout = Duration(seconds: 20);

  /// Проверяет HTTP-статус явно: Dio-клиент приложения может быть настроен
  /// снисходительно к 4xx, но discovery обязан различать 401/403/404.
  Future<Response<T>> send<T>(Future<Response<T>> request) async {
    final Response<T> response = await request;
    final int status = response.statusCode ?? 200;
    if (status >= 400) throw _HttpStatusError(status);
    return response;
  }
  String joinBase(String baseUrl, String path) {
    final String base = baseUrl.trim().replaceAll(RegExp(r'/+$'), '');
    final String suffix = path.startsWith('/') ? path : '/$path';
    return '$base$suffix';
  }

  Future<DiscoveryResult> guard(
    ProviderAccount account, {
    required String sourceRef,
    required Future<DiscoveryResult> Function(String? apiKey) body,
  }) async {
    final String? key = account.requiresApiKey
        ? await readApiKey(account.id)
        : null;
    if (account.requiresApiKey && (key == null || key.isEmpty)) {
      return DiscoveryResult(
        status: DiscoveryStatus.unauthorized,
        accountId: account.id,
        model: account.modelId,
        errorCode: 'no_api_key',
        sourceRef: sourceRef,
      );
    }
    try {
      return await body(key);
    } on TimeoutException {
      return _error(account, DiscoveryStatus.timeout, 'timeout', sourceRef);
    } on _HttpStatusError catch (error) {
      if (error.status == 401 || error.status == 403) {
        return _error(account, DiscoveryStatus.unauthorized, 'unauthorized', sourceRef);
      }
      if (error.status == 404) {
        return _error(account, DiscoveryStatus.notFound, 'not_found', sourceRef);
      }
      return _error(account, DiscoveryStatus.error, 'http_${error.status}', sourceRef);
    } on DioException catch (error) {
      final int? code = error.response?.statusCode;
      if (code == 401 || code == 403) {
        return _error(account, DiscoveryStatus.unauthorized, 'unauthorized', sourceRef);
      }
      if (code == 404) {
        return _error(account, DiscoveryStatus.notFound, 'not_found', sourceRef);
      }
      if (error.type == DioExceptionType.connectionTimeout ||
          error.type == DioExceptionType.receiveTimeout ||
          error.type == DioExceptionType.sendTimeout) {
        return _error(account, DiscoveryStatus.timeout, 'timeout', sourceRef);
      }
      return _error(account, DiscoveryStatus.error, 'http_${code ?? 'network'}', sourceRef);
    } on Object {
      return _error(account, DiscoveryStatus.error, 'parse_error', sourceRef);
    }
  }

  DiscoveryResult _error(
    ProviderAccount account,
    DiscoveryStatus status,
    String code,
    String sourceRef,
  ) => DiscoveryResult(
    status: status,
    accountId: account.id,
    model: account.modelId,
    errorCode: code,
    sourceRef: sourceRef,
  );

  Options options({
    String? apiKey,
    Map<String, String> headers = const <String, String>{},
  }) => Options(
    receiveTimeout: receiveTimeout,
    headers: <String, String>{
      'Accept': 'application/json',
      if (apiKey != null && apiKey.isNotEmpty) ...<String, String>{
        'Authorization': 'Bearer $apiKey',
      },
      ...headers,
    },
  );
}

/// OpenAI-совместимый `GET {base}/models` с политикой доверия к полям.
///
/// [defaultSemantics] — семантика окна у провайдера (total/inputOnly/unknown).
class OpenAiCompatibleModelsDiscovery extends _HttpDiscovery
    implements ModelCapabilityDiscovery {
  /// Создаёт резолвер.
  OpenAiCompatibleModelsDiscovery(
    Dio dio, {
    required ApiKeyReader readApiKey,
    this.fieldPolicy = OpenAiModelFieldPolicy.idsOnly,
    this.defaultSemantics = ContextSemantics.unknown,
    this.pricingIsPerToken = false,
  }) : super(dio, readApiKey);

  /// Политика доверия полям ответа.
  final OpenAiModelFieldPolicy fieldPolicy;

  /// Семантика окна провайдера (если известна).
  final ContextSemantics defaultSemantics;

  /// true — `pricing` OpenRouter в USD за токен (перевести в 1M).
  final bool pricingIsPerToken;

  @override
  Future<DiscoveryResult> discover(ProviderAccount account) async {
    final String path = '/models';
    final String url = joinBase(account.baseUrl, path);
    final String sourceRef = url;
    return guard(
      account,
      sourceRef: sourceRef,
      body: (String? apiKey) async {
        final Response<Object?> response = await send(dio.getUri<Object?>(
          Uri.parse(url),
          options: options(apiKey: apiKey),
        ));
        final Object? data = response.data;
        if (data is! Map) {
          return DiscoveryResult(
            status: DiscoveryStatus.error,
            accountId: account.id,
            model: account.modelId,
            errorCode: 'invalid_body',
            sourceRef: sourceRef,
          );
        }
        final Object? rawModels = data['data'];
        if (rawModels is! List) {
          return DiscoveryResult(
            status: DiscoveryStatus.error,
            accountId: account.id,
            model: account.modelId,
            errorCode: 'no_data',
            sourceRef: sourceRef,
          );
        }
        final List<String> ids = <String>[];
        Map<String, Object?>? target;
        for (final Object? item in rawModels) {
          if (item is! Map) continue;
          final Object? id = item['id'];
          if (id is! String || id.isEmpty) continue;
          ids.add(id);
          if (id == account.modelId) target = item.cast<String, Object?>();
        }
        final DateTime now = DateTime.now().toUtc();
        final ModelLimits limits = target == null
            ? const ModelLimits.absent()
            : _limitsOf(target, sourceRef, now);
        return DiscoveryResult(
          status: DiscoveryStatus.success,
          accountId: account.id,
          model: account.modelId,
          limits: limits,
          models: List<String>.unmodifiable(ids),
          fetchedAt: now,
          sourceRef: sourceRef,
          warnings: List<String>.unmodifiable(<String>[
            if (target == null) 'model_not_in_list',
            if (fieldPolicy == OpenAiModelFieldPolicy.idsOnly)
              'provider_fields_not_documented',
          ]),
        );
      },
    );
  }

  ModelLimits _limitsOf(
    Map<String, Object?> item,
    String sourceRef,
    DateTime now,
  ) {
    if (fieldPolicy == OpenAiModelFieldPolicy.idsOnly) {
      return const ModelLimits.absent();
    }
    Sourced<int> intField(Object? raw) {
      final int? value = _positiveInt(raw);
      return value == null
          ? const Sourced<int>.absent()
          : Sourced<int>(value, source: CapabilitySource.providerApi, observedAt: now, sourceRef: sourceRef);
    }

    Sourced<bool> boolField(Object? raw) {
      if (raw is! bool) return const Sourced<bool>.absent();
      return Sourced<bool>(raw, source: CapabilitySource.providerApi, observedAt: now, sourceRef: sourceRef);
    }

    // Разные провайдеры используют разные имена полей; неизвестные — absent.
    final Object? topProvider = item['top_provider'];
    final Object? architecture = item['architecture'];
    final Object? modalities = architecture is Map
        ? architecture['input_modalities']
        : null;
    final Map<String, Object?>? pricing = item['pricing'] is Map
        ? (item['pricing']! as Map).cast<String, Object?>()
        : null;
    int? context = _positiveInt(item['context_window']) ??
        _positiveInt(item['context_length']);
    final int? topContext = topProvider is Map
        ? _positiveInt(topProvider['context_length'])
        : null;
    if (topContext != null) {
      context = context == null ? topContext : (context < topContext ? context : topContext);
    }
    final int? maxOutput = _positiveInt(item['max_completion_tokens']) ??
        _positiveInt(item['max_output_tokens']) ??
        (topProvider is Map ? _positiveInt(topProvider['max_completion_tokens']) : null);
    GenerationPricing? price;
    if (pricing != null) {
      final double? prompt = _priceFrom(pricing['prompt']);
      final double? completion = _priceFrom(pricing['completion']);
      if (prompt != null && completion != null) {
        final double factor = pricingIsPerToken ? 1000000 : 1;
        price = GenerationPricing(
          inputPerMillion: prompt * factor,
          outputPerMillion: completion * factor,
          currency: 'USD',
        );
      }
    }
    return ModelLimits(
      contextTokens: intField(context),
      contextSemantics: defaultSemantics,
      maxOutputTokens: intField(maxOutput),
      supportsImageInput: modalities is List
          ? boolField(modalities.map((Object? v) => v?.toString()).contains('image'))
          : const Sourced<bool>.absent(),
      pricing: price == null
          ? const Sourced<GenerationPricing>.absent()
          : Sourced<GenerationPricing>(price, source: CapabilitySource.providerApi, observedAt: now, sourceRef: sourceRef),
    );
  }

  int? _positiveInt(Object? raw) {
    if (raw is num && raw.isFinite && raw > 0) return raw.toInt();
    if (raw is String) {
      final int? parsed = int.tryParse(raw.trim());
      if (parsed != null && parsed > 0) return parsed;
    }
    return null;
  }

  double? _priceFrom(Object? raw) {
    if (raw is num && raw.isFinite && raw >= 0) return raw.toDouble();
    if (raw is String) {
      final double? parsed = double.tryParse(raw.trim());
      if (parsed != null && parsed >= 0) return parsed;
    }
    return null;
  }
}

/// Anthropic `GET /v1/models` с пагинацией `after_id`/`has_more`/`last_id`.
class AnthropicModelsDiscovery extends _HttpDiscovery
    implements ModelCapabilityDiscovery {
  /// Создаёт резолвер.
  AnthropicModelsDiscovery(Dio dio, {required ApiKeyReader readApiKey})
    : super(dio, readApiKey);

  @override
  Future<DiscoveryResult> discover(ProviderAccount account) async {
    final String url = joinBase(account.baseUrl, '/v1/models');
    return guard(
      account,
      sourceRef: url,
      body: (String? apiKey) async {
        final List<String> ids = <String>[];
        Map<String, Object?>? target;
        String? afterId;
        for (var page = 0; page < 10; page++) {
          final Uri uri = Uri.parse(url).replace(
            queryParameters: <String, String>{
              'limit': '100',
              'after_id': ?afterId,
            },
          );
          final Response<Object?> response = await send(dio.getUri<Object?>(
            uri,
            options: options(
              apiKey: apiKey,
              headers: <String, String>{
                'x-api-key': apiKey ?? '',
                'anthropic-version': '2023-06-01',
              },
            ),
          ));
          final Object? data = response.data;
          if (data is! Map) break;
          final Object? rawModels = data['data'];
          if (rawModels is! List) break;
          for (final Object? item in rawModels) {
            if (item is! Map) continue;
            final Object? id = item['id'];
            if (id is! String || id.isEmpty) continue;
            ids.add(id);
            if (id == account.modelId) target = item.cast<String, Object?>();
          }
          final bool hasMore = data['has_more'] == true;
          final Object? lastId = data['last_id'];
          if (!hasMore || lastId is! String || lastId.isEmpty) break;
          afterId = lastId;
        }
        final DateTime now = DateTime.now().toUtc();
        return DiscoveryResult(
          status: DiscoveryStatus.success,
          accountId: account.id,
          model: account.modelId,
          limits: target == null
              ? const ModelLimits.absent()
              : _limitsOf(target, url, now),
          models: List<String>.unmodifiable(ids),
          fetchedAt: now,
          sourceRef: url,
          warnings: target == null
              ? const <String>['model_not_in_list']
              : const <String>[],
        );
      },
    );
  }

  ModelLimits _limitsOf(
    Map<String, Object?> item,
    String sourceRef,
    DateTime now,
  ) {
    Sourced<int> intField(Object? raw) {
      if (raw is! num || !raw.isFinite || raw <= 0) {
        return const Sourced<int>.absent();
      }
      return Sourced<int>(raw.toInt(), source: CapabilitySource.providerApi, observedAt: now, sourceRef: sourceRef);
    }

    final Object? capabilities = item['capabilities'];
    bool? vision;
    bool? pdf;
    if (capabilities is Map) {
      if (capabilities['vision'] is bool) vision = capabilities['vision']! as bool;
      if (capabilities['pdf_input'] is bool) {
        pdf = capabilities['pdf_input']! as bool;
      } else if (capabilities['pdf'] is bool) {
        pdf = capabilities['pdf']! as bool;
      }
    }
    Sourced<bool> boolField(bool? value) => value == null
        ? const Sourced<bool>.absent()
        : Sourced<bool>(value, source: CapabilitySource.providerApi, observedAt: now, sourceRef: sourceRef);
    return ModelLimits(
      contextTokens: intField(item['max_input_tokens']),
      contextSemantics: ContextSemantics.inputOnly,
      maxInputTokens: intField(item['max_input_tokens']),
      maxOutputTokens: intField(item['max_tokens']),
      supportsImageInput: boolField(vision),
      supportsPdfInput: boolField(pdf),
    );
  }
}

/// Gemini `GET v1beta/models` с `pageToken`/`nextPageToken`.
class GeminiModelsDiscovery extends _HttpDiscovery
    implements ModelCapabilityDiscovery {
  /// Создаёт резолвер.
  GeminiModelsDiscovery(Dio dio, {required ApiKeyReader readApiKey})
    : super(dio, readApiKey);

  @override
  Future<DiscoveryResult> discover(ProviderAccount account) async {
    final String url = joinBase(account.baseUrl, '/v1beta/models');
    return guard(
      account,
      sourceRef: url,
      body: (String? apiKey) async {
        final List<String> ids = <String>[];
        Map<String, Object?>? target;
        String? pageToken;
        for (var page = 0; page < 10; page++) {
          final Uri uri = Uri.parse(url).replace(
            queryParameters: <String, String>{
              'pageSize': '100',
              'pageToken': ?pageToken,
            },
          );
          final Response<Object?> response = await send(dio.getUri<Object?>(
            uri,
            options: options(
              apiKey: null,
              headers: <String, String>{
                if (apiKey != null && apiKey.isNotEmpty)
                  'x-goog-api-key': apiKey,
              },
            ),
          ));
          final Object? data = response.data;
          if (data is! Map) break;
          final Object? rawModels = data['models'];
          if (rawModels is! List) break;
          for (final Object? item in rawModels) {
            if (item is! Map) continue;
            final Object? rawName = item['name'];
            if (rawName is! String) continue;
            final String id = rawName.replaceFirst('models/', '');
            final Object? methods = item['supportedGenerationMethods'];
            if (methods is List && !methods.contains('generateContent')) {
              continue;
            }
            ids.add(id);
            if (id == account.modelId) target = item.cast<String, Object?>();
          }
          final Object? next = data['nextPageToken'];
          if (next is! String || next.isEmpty) break;
          pageToken = next;
        }
        final DateTime now = DateTime.now().toUtc();
        return DiscoveryResult(
          status: DiscoveryStatus.success,
          accountId: account.id,
          model: account.modelId,
          limits: target == null
              ? const ModelLimits.absent()
              : _limitsOf(target, url, now),
          models: List<String>.unmodifiable(ids),
          fetchedAt: now,
          sourceRef: url,
          warnings: target == null
              ? const <String>['model_not_in_list']
              : const <String>[],
        );
      },
    );
  }

  ModelLimits _limitsOf(
    Map<String, Object?> item,
    String sourceRef,
    DateTime now,
  ) {
    Sourced<int> intField(Object? raw) {
      if (raw is! num || !raw.isFinite || raw <= 0) {
        return const Sourced<int>.absent();
      }
      return Sourced<int>(raw.toInt(), source: CapabilitySource.providerApi, observedAt: now, sourceRef: sourceRef);
    }

    return ModelLimits(
      contextTokens: intField(item['inputTokenLimit']),
      contextSemantics: ContextSemantics.inputOnly,
      maxInputTokens: intField(item['inputTokenLimit']),
      maxOutputTokens: intField(item['outputTokenLimit']),
    );
  }
}

/// Ollama: `GET /api/tags` (модели) и `POST /api/show` (`model_info`).
///
/// `model_info["<arch>.context_length"]` — максимум обучения; рабочий `num_ctx`
/// может быть меньше, поэтому эффективный контекст остаётся допущением
/// (`ollama_num_ctx_assumption`), пока его не задал пользователь.
class OllamaModelsDiscovery extends _HttpDiscovery
    implements ModelCapabilityDiscovery {
  /// Создаёт резолвер.
  OllamaModelsDiscovery(Dio dio, {required ApiKeyReader readApiKey})
    : super(dio, readApiKey);

  @override
  Future<DiscoveryResult> discover(ProviderAccount account) async {
    final String tagsUrl = joinBase(account.baseUrl, '/api/tags');
    final String showUrl = joinBase(account.baseUrl, '/api/show');
    return guard(
      account,
      sourceRef: showUrl,
      body: (String? apiKey) async {
        final Response<Object?> tags = await send(dio.getUri<Object?>(
          Uri.parse(tagsUrl),
          options: options(apiKey: apiKey),
        ));
        final Object? tagsData = tags.data;
        final List<String> ids = <String>[];
        final bool targetLocal;
        {
          final Object? models = tagsData is Map ? tagsData['models'] : null;
          if (models is List) {
            for (final Object? item in models) {
              if (item is! Map) continue;
              final Object? name = item['model'] ?? item['name'];
              if (name is String && name.isNotEmpty) ids.add(name);
            }
          }
          targetLocal = ids.isEmpty || ids.contains(account.modelId);
        }
        if (!targetLocal) {
          return DiscoveryResult(
            status: DiscoveryStatus.success,
            accountId: account.id,
            model: account.modelId,
            limits: const ModelLimits.absent(),
            models: List<String>.unmodifiable(ids),
            fetchedAt: DateTime.now().toUtc(),
            sourceRef: tagsUrl,
            warnings: const <String>['model_not_in_list'],
          );
        }
        final Response<Object?> show = await send(dio.postUri<Object?>(
          Uri.parse(showUrl),
          data: <String, Object?>{'model': account.modelId},
          options: options(apiKey: apiKey),
        ));
        final Object? showData = show.data;
        final Object? info = showData is Map ? showData['model_info'] : null;
        final Object? capabilities = showData is Map
            ? showData['capabilities']
            : null;
        final DateTime now = DateTime.now().toUtc();
        int? context;
        if (info is Map) {
          for (final MapEntry<Object?, Object?> entry in info.entries) {
            final String key = entry.key.toString();
            if (!key.endsWith('.context_length')) continue;
            final Object? value = entry.value;
            if (value is num && value.isFinite && value > 0) {
              context = value.toInt();
              break;
            }
          }
        }
        bool? vision;
        if (capabilities is List) {
          vision = capabilities.contains('vision');
        }
        return DiscoveryResult(
          status: DiscoveryStatus.success,
          accountId: account.id,
          model: account.modelId,
          limits: ModelLimits(
            contextTokens: context == null
                ? const Sourced<int>.absent()
                : Sourced<int>(context, source: CapabilitySource.providerApi, observedAt: now, sourceRef: showUrl),
            contextSemantics: ContextSemantics.totalInputPlusOutput,
            supportsImageInput: vision == null
                ? const Sourced<bool>.absent()
                : Sourced<bool>(vision, source: CapabilitySource.providerApi, observedAt: now, sourceRef: showUrl),
          ),
          models: List<String>.unmodifiable(ids),
          fetchedAt: now,
          sourceRef: showUrl,
          warnings: const <String>['ollama_num_ctx_assumption'],
        );
      },
    );
  }
}

/// Выбирает резолвер по пресету аккаунта (политика полей различается).
ModelCapabilityDiscovery discoveryForAccount(
  ProviderAccount account,
  Dio dio, {
  required ApiKeyReader readApiKey,
}) {
  final String preset = account.presetId ?? '';
  switch (account.protocol) {
    case ProviderProtocol.anthropicMessages:
      return AnthropicModelsDiscovery(dio, readApiKey: readApiKey);
    case ProviderProtocol.geminiGenerateContent:
      return GeminiModelsDiscovery(dio, readApiKey: readApiKey);
    case ProviderProtocol.openai:
      return OpenAiCompatibleModelsDiscovery(
        dio,
        readApiKey: readApiKey,
        fieldPolicy: OpenAiModelFieldPolicy.idsOnly,
      );
    case ProviderProtocol.openaiCompletions:
      if (preset == 'ollama') {
        return OllamaModelsDiscovery(dio, readApiKey: readApiKey);
      }
      if (preset == 'deepseek') {
        return OpenAiCompatibleModelsDiscovery(
          dio,
          readApiKey: readApiKey,
          fieldPolicy: OpenAiModelFieldPolicy.documented,
          defaultSemantics: ContextSemantics.totalInputPlusOutput,
        );
      }
      if (preset == 'openrouter') {
        return OpenAiCompatibleModelsDiscovery(
          dio,
          readApiKey: readApiKey,
          fieldPolicy: OpenAiModelFieldPolicy.documented,
          defaultSemantics: ContextSemantics.totalInputPlusOutput,
          pricingIsPerToken: true,
        );
      }
      if (preset == 'groq' || preset == 'moonshot') {
        return OpenAiCompatibleModelsDiscovery(
          dio,
          readApiKey: readApiKey,
          fieldPolicy: OpenAiModelFieldPolicy.documented,
          defaultSemantics: ContextSemantics.unknown,
        );
      }
      // Произвольный OpenAI-совместимый: только список id, поля не доверяем.
      return OpenAiCompatibleModelsDiscovery(
        dio,
        readApiKey: readApiKey,
        fieldPolicy: OpenAiModelFieldPolicy.idsOnly,
      );
  }
}
/// HTTP-статус ошибки, которую Dio не бросил (validateStatus разрешил 4xx).
final class _HttpStatusError implements Exception {
  const _HttpStatusError(this.status);
  final int status;
}