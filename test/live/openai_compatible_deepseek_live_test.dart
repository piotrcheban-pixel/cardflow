import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
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
}

/// Непустое (после trim) значение переменной окружения или null.
String? _envValue(Map<String, String> env, String name) {
  final value = env[name]?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
