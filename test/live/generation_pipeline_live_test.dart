import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';

import '../helpers/generation_fakes.dart';
import 'support/live_test_config.dart';

/// Live-интеграция пайплайна генерации: реальный DeepSeek, production-сборка
/// промпта и плана, тема «трансформаторы», 10 карточек.
///
/// Запуск — только по явному разрешению и с ключом (иначе skip):
///   $env:DEEPSEEK_API_KEY = ...
///   $env:CARDFLOW_LIVE_TESTS = '1'
///   $env:CARDFLOW_LIVE_MAX_REQUESTS = '4'
///   $env:CARDFLOW_LIVE_MAX_COST_USD = '0.1'
///   fvm flutter test --no-pub test/live --tags live
///
/// Без `CARDFLOW_LIVE_TESTS=1` (обычный `flutter test` и CI) запросов нет.
void main() {
  final Map<String, String> env = Platform.environment;
  final String? apiKey = env['DEEPSEEK_API_KEY'];
  final String? liveSkip = liveDetailedTestsSkipReason(
    apiKey: apiKey,
    keyVariable: 'DEEPSEEK_API_KEY',
    environment: env,
  );
  final String baseUrl = env['DEEPSEEK_BASE_URL'] ?? 'https://api.deepseek.com';
  final String model = env['DEEPSEEK_MODEL'] ?? 'deepseek-flash';

  test(
    'живой пайплайн: тема «трансформаторы», 10 карточек, production-промпт',
    () async {
      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          receiveTimeout: const Duration(seconds: 180),
        ),
      );
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final GenerationDiagnostics diag = GenerationDiagnostics(
        enabled: true,
        sink: diagnostics.add,
      );

      final ProviderAccount account = ProviderAccount.fromPreset(
        providerPresetById('deepseek')!,
        id: 'deepseek',
      );
      final CardGenerationService service = CardGenerationService(
        adapters: generationAdapters,
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          diagnostics: diag,
        ),
        diagnostics: diag,
        // baseUrl/модель live-прогона: DEEPSEEK_BASE_URL/DEEPSEEK_MODEL.
        maxOutputTokens: 8192,
      );
      final FakeGenerationJobRepository jobs = FakeGenerationJobRepository();
      final GenerationPipeline pipeline = GenerationPipeline(
        caller: service,
        jobRepository: jobs,
        cardStore: FakeGenerationCardStore(),
        imageFinder: null,
        diagnostics: diag,
      );

      final GenerationRunResult result = await pipeline.run(
        GenerationRunRequest(
          documents: const <Never>[],
          account: account.copyWith(baseUrl: baseUrl, modelId: model),
          deckName: 'Трансформаторы (live)',
          wishes: 'трансформаторы',
          requestedCards: 10,
        ),
      );

      // ignore: avoid_print — evidence без ключа и тел ответа.
      print(
        'LIVE pipeline: model=$model, status=${result.status.name}, '
        'cards=${result.cards.length}, failures=${result.failures.length}, '
        'tokens=${result.tokensUsed}, prompt=$systemPromptVersion',
      );
      for (final GenerationChunkFailure failure in result.failures) {
        // ignore: avoid_print
        print(
          'LIVE pipeline failure: code=${failure.code.name}, '
          'reason=${failure.reason?.code ?? '-'}',
        );
      }

      expect(result.status, isNot(GenerationJobStatus.error));
      expect(result.cards, isNotEmpty);
      expect(result.cards.length, lessThanOrEqualTo(10));
      for (final GeneratedCard card in result.cards) {
        expect(card.front.trim(), isNotEmpty);
        expect(card.back.trim(), isNotEmpty);
      }
      // Последнее задание журнала — не ошибка, карточки учтены.
      expect(jobs.saved.last.cardsCount, result.cards.length);
      expect(jobs.saved.last.promptVersion, 'gen-ru-v9');
      expect(
        result.failures.where(
          (GenerationChunkFailure f) => f.code.name == 'storageUnavailable',
        ),
        isEmpty,
      );
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );
}
