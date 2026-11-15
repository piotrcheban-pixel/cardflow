import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../helpers/generation_fakes.dart';

/// Live-проверка OpenAI-совместимого адаптера на реальном DeepSeek (ADR-013).
///
/// Запуск — только при наличии ключа в окружении (иначе skip):
///   set DEEPSEEK_API_KEY=...            (значение не выводить в терминал)
///   fvm flutter test test/live --tags live
/// Необязательно: DEEPSEEK_BASE_URL (по умолчанию `https://api.deepseek.com`),
/// DEEPSEEK_MODEL (по умолчанию `deepseek-chat`).
void main() {
  final Map<String, String> env = Platform.environment;
  final String? apiKey = _envValue(env, 'DEEPSEEK_API_KEY');
  final String baseUrl =
      _envValue(env, 'DEEPSEEK_BASE_URL') ?? 'https://api.deepseek.com';
  final String model = _envValue(env, 'DEEPSEEK_MODEL') ?? 'deepseek-chat';

  test(
    'реальный вызов DeepSeek через OpenAI-compatible: один запрос, '
    'карточки по канонической схеме A8.4',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));

      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        promptVersion: 'gen-ru-v2',
        maxOutputTokens: 4096,
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
          ),
          materialsText:
              'FSRS — алгоритм интервального повторения. Он прогнозирует '
              'вероятность вспоминания карточки и выбирает дату следующего '
              'повторения. CardFlow использует FSRS для планирования.',
          limit: 3,
        ),
      );

      // Успешный ответ доказывает: живой endpoint, разбор ответа, локальная
      // валидация схемы A8.4 и контентные правила пройдены.
      expect(result.provider, GenerationProvider.openaiCompatible);
      expect(result.model, model);
      expect(result.cards, isNotEmpty);
      expect(result.cards.length, lessThanOrEqualTo(3));
      for (final card in result.cards) {
        expect(card.front.trim(), isNotEmpty);
      }
      // ignore: avoid_print — evidence в логе прогона без ключа/материалов.
      print(
        'LIVE DeepSeek OK: model=$model, cards=${result.cards.length}, '
        'tokens=${result.usage.totalTokens}',
      );
    },
    skip: apiKey == null
        ? 'Нет DEEPSEEK_API_KEY — live-тест пропущен (L30)'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );

  test(
    'живой DeepSeek отклоняет strict response_format → fallback с max_tokens '
    '(ADR-021)',
    () async {
      // Запоминаем только метаданные запросов: ключ, тела и ответ модели в
      // лог не попадают (AGENTS: тела генерации не логируются).
      final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
      final List<int?> statuses = <int?>[];
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler next) {
            final data = options.data;
            if (data is String) {
              final decoded = jsonDecode(data);
              if (decoded is Map<String, Object?>) bodies.add(decoded);
            }
            next.next(options);
          },
          onResponse:
              (Response<dynamic> response, ResponseInterceptorHandler next) {
                statuses.add(response.statusCode);
                next.next(response);
              },
          onError: (DioException error, ErrorInterceptorHandler next) {
            statuses.add(error.response?.statusCode);
            next.next(error);
          },
        ),
      );

      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
          ),
          materialsText:
              'Минералы делятся на классы по химическому составу. Кварц — '
              'минерал класса оксидов, твердость 7, блеск стеклянный.',
          limit: 2,
        ),
      );

      expect(result.cards, isNotEmpty);
      expect(
        bodies,
        hasLength(2),
        reason: 'strict-запрос отклонён, затем fallback',
      );
      expect(statuses, <int?>[400, 200]);
      final strictFormat = bodies.first['response_format'];
      expect(strictFormat, isA<Map<String, Object?>>());
      expect(bodies.first['max_tokens'], 8192);
      expect(bodies.last.containsKey('response_format'), isFalse);
      expect(bodies.last['max_tokens'], 8192);
      // ignore: avoid_print — evidence без ключа, тел и ответа модели.
      print(
        'LIVE DeepSeek fallback: strict=${statuses.first}, '
        'tolerant=${statuses.last}, max_tokens=${bodies.last['max_tokens']}, '
        'cards=${result.cards.length}',
      );
    },
    skip: apiKey == null
        ? 'Нет DEEPSEEK_API_KEY — live-тест пропущен (L30)'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );

  // Итерация 7.10, ADR-024: генерация по теме без файлов и проверка того, что
  // модель возвращает image_query по правилу 14 промпта `gen-ru-v4`.
  test(
    'живой DeepSeek: prompt-only без файлов и image_query (gen-ru-v4)',
    () async {
      final List<String> diagnostics = <String>[];
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));

      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
        diagnostics: GenerationDiagnostics(
          enabled: true,
          sink: diagnostics.add,
        ),
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
          ),
          materialsText: '',
          wishes: 'Животные Африки: слон, жираф и лев. 3 карточки',
          limit: 3,
        ),
      );

      expect(result.cards, isNotEmpty);
      expect(result.promptVersion, systemPromptVersion);
      final int withQuery = result.cards
          .where((card) => (card.imageQuery ?? '').isNotEmpty)
          .length;
      // ignore: avoid_print — evidence без ключа и тел ответа.
      print(
        'LIVE DeepSeek prompt-only: cards=${result.cards.length}, '
        'image_query=$withQuery, prompt=${result.promptVersion}, '
        'tokens=${result.usage.totalTokens}',
      );
      expect(
        withQuery,
        greaterThan(0),
        reason: 'промпт v4 требует image_query для предметных basic/cloze',
      );
      expect(diagnostics, isNotEmpty);
      expect(diagnostics.single, contains('image_query'));
    },
    skip: apiKey == null
        ? 'Нет DEEPSEEK_API_KEY — live-тест пропущен (L30)'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );
}

/// Непустое (после trim) значение переменной окружения или null.
String? _envValue(Map<String, String> env, String name) {
  final value = env[name]?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
