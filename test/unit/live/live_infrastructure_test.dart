import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

import '../../helpers/fake_http_adapter.dart';
import '../../helpers/generation_fakes.dart';
import '../../live/support/live_budget.dart';
import '../../live/support/live_cost.dart';
import '../../live/support/live_pricing.dart';
import '../../live/support/live_quality.dart';
import '../../live/support/live_run_report.dart';
import '../../live/support/live_scenarios.dart';
import '../../live/support/live_test_config.dart';

/// TASK 04, раздел 5: инфраструктура live-тестов безопасна по умолчанию.
///
/// Здесь проверяется то, что можно проверить без сети и без денег: значения по
/// умолчанию исключают запросы, явное разрешение обязательно, бюджет и
/// стоимость ограничивают прогон, неизвестный тариф не превращается в ноль,
/// отчёт калибровки не выдумывает отсутствующие поля.
void main() {
  group('LiveTestConfig: значения по умолчанию', () {
    test('выключенная конфигурация не разрешает ни одного запроса', () {
      const config = LiveTestConfig.disabled();
      expect(config.enabled, isFalse);
      expect(config.maxRequests, 0);
      expect(config.maxEstimatedCostUsd, 0);
      expect(config.skipReason, contains(kLiveTestsVariable));
      expect(config.skipReason, contains('не тратит деньги'));
    });

    test('пустое окружение — live-тесты пропускаются', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{});
      expect(config.enabled, isFalse);
      expect(config.skipReason, isNotNull);
      expect(config.apiKey, isNull);
    });

    test('флаг без бюджета запросов — пропуск, а не запуск', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        'DEEPSEEK_API_KEY': 'test-key-value',
      });
      expect(config.enabled, isTrue);
      expect(config.maxRequests, 0);
      expect(config.skipReason, contains(kLiveMaxRequestsVariable));
    });

    test('без ключа — безопасный skip с именем переменной, без значения', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '2',
      });
      expect(config.skipReason, contains('DEEPSEEK_API_KEY'));
      expect(config.hasApiKey, isFalse);
    });

    test('явное разрешение + бюджет + ключ — можно запускать', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '3',
        kLiveMaxCostVariable: '0.05',
        'DEEPSEEK_API_KEY': 'secret-value',
      });
      expect(config.skipReason, isNull);
      expect(config.maxRequests, 3);
      expect(config.maxEstimatedCostUsd, 0.05);
      expect(config.apiKey, 'secret-value');
      // Ключ не попадает в сводку конфигурации.
      expect(config.toString(), isNot(contains('secret-value')));
      expect(config.toString(), contains('present'));
    });

    test('модель из окружения не подменяется моделью пресета', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '1',
        kLiveModelVariable: 'deepseek-flash',
        'DEEPSEEK_API_KEY': 'k',
      });
      expect(config.model, 'deepseek-flash');
      expect(config.account.modelId, 'deepseek-flash');
      expect(config.account.baseUrl, 'https://api.deepseek.com');
      expect(config.account.requiresApiKey, isTrue);
    });

    test('провайдерское переопределение модели (DEEPSEEK_MODEL) уважается', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '1',
        'DEEPSEEK_MODEL': 'deepseek-v4-pro',
        'DEEPSEEK_API_KEY': 'k',
      });
      expect(config.model, 'deepseek-v4-pro');
    });

    test('неизвестный провайдер — пропуск без запроса', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '1',
        kLiveProviderVariable: 'unknown-provider',
        'DEEPSEEK_API_KEY': 'k',
      });
      expect(config.skipReason, contains('Неизвестный провайдер'));
    });
  });

  group('LiveTestConfig: сценарии включаются отдельно', () {
    test('по умолчанию все сценарии выключены', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '3',
        'DEEPSEEK_API_KEY': 'k',
      });
      for (final LiveScenario scenario in LiveScenario.values) {
        expect(
          config.scenarioSkipReason(scenario),
          isNotNull,
          reason: scenario.name,
        );
      }
    });

    test('флаг сценария включает только его', () {
      final config = LiveTestConfig.fromEnvironment(const <String, String>{
        kLiveTestsVariable: '1',
        kLiveMaxRequestsVariable: '3',
        kLiveEnablePromptOnlyVariable: '1',
        'DEEPSEEK_API_KEY': 'k',
      });
      expect(config.scenarioSkipReason(LiveScenario.promptOnly), isNull);
      expect(config.scenarioSkipReason(LiveScenario.smallDocument), isNotNull);
      expect(config.scenarioSkipReason(LiveScenario.images), isNotNull);
    });
  });

  group('Стоимость: неизвестный тариф не ноль', () {
    test('подтверждённый тариф считается по официальной цене', () {
      final estimate = estimateLiveCost(
        provider: 'deepseek',
        model: 'deepseek-flash',
        requests: 2,
        inputTokensPerRequest: 10000,
        outputTokensPerRequest: 1000,
      );
      expect(estimate.isKnown, isTrue);
      // 20000 входных × $0.30/1M + 2000 выходных × $1.20/1M.
      expect(estimate.amount, closeTo(0.0084, 1e-9));
      expect(estimate.currency, 'USD');
      expect(estimate.price?.verifiedOn, '2026-11-19');
    });

    test('неизвестный тариф даёт null и причину, а не 0', () {
      final estimate = estimateLiveCost(
        provider: 'deepseek',
        model: 'deepseek-chat',
        requests: 1,
        inputTokensPerRequest: 1000,
        outputTokensPerRequest: 100,
      );
      expect(estimate.amount, isNull);
      expect(estimate.isKnown, isFalse);
      expect(estimate.unknownReason, kLivePriceUnknownReason);
      expect(estimate.formatAmount(), 'неизвестна');
      expect(estimate.toJson()['amount'], isNull);
    });

    test('неизвестная стоимость блокирует прогон без явного разрешения', () {
      final estimate = estimateLiveCost(
        provider: 'deepseek',
        model: 'deepseek-chat',
        requests: 1,
        inputTokensPerRequest: 1000,
        outputTokensPerRequest: 100,
      );
      final config = liveConfigForTests(maxRequests: 2);
      expect(estimate.blockReason(config), contains('неизвестна'));
      expect(
        estimate.blockReason(
          liveConfigForTests(
            maxRequests: 2,
            allowUnknownCost: true,
            maxEstimatedCostUsd: 0,
          ),
        ),
        contains(kLiveMaxCostVariable),
      );
      expect(
        estimate.blockReason(
          liveConfigForTests(
            maxRequests: 2,
            allowUnknownCost: true,
            maxEstimatedCostUsd: 0.05,
          ),
        ),
        isNull,
      );
    });

    test('известная стоимость проверяется по лимиту', () {
      final estimate = estimateLiveCost(
        provider: 'deepseek',
        model: 'deepseek-flash',
        requests: 1,
        inputTokensPerRequest: 10000,
        outputTokensPerRequest: 1000,
      );
      expect(
        estimate.blockReason(liveConfigForTests(maxEstimatedCostUsd: 0.001)),
        contains('превышает лимит'),
      );
      expect(
        estimate.blockReason(liveConfigForTests(maxEstimatedCostUsd: 0.05)),
        isNull,
      );
    });

    test('лимит запросов проверяется до стоимости', () {
      final estimate = estimateLiveCost(
        provider: 'deepseek',
        model: 'deepseek-flash',
        requests: 3,
        inputTokensPerRequest: 1000,
        outputTokensPerRequest: 100,
      );
      expect(
        estimate.blockReason(liveConfigForTests(maxRequests: 2)),
        contains('требует 3 запросов'),
      );
    });
  });

  group('План сценариев', () {
    test('число запросов считается по лимиту вывода', () {
      expect(kLiveCardsPerRequest, 7);
      expect(liveScenarioPlanById('prompt_only_many_20')!.expectedRequests, 3);
      expect(liveScenarioPlanById('big_document_30')!.expectedRequests, 5);
      expect(liveScenarioPlanById('prompt_only_short')!.expectedRequests, 1);
    });

    test('стоимость сценария известна/неизвестна по тарифу модели', () {
      final known = liveScenarioPlanById('prompt_only_short')!
          .costFor(liveConfigForTests(model: 'deepseek-flash'));
      expect(known.isKnown, isTrue);
      final unknown = liveScenarioPlanById('prompt_only_short')!
          .costFor(liveConfigForTests(model: 'deepseek-chat'));
      expect(unknown.isKnown, isFalse);
    });
  });

  group('Бюджет и транспорт', () {
    test('бюджет не допускает запрос сверх лимита', () {
      final budget = LiveRequestBudget(maxRequests: 2);
      budget.reserve();
      budget.reserve();
      expect(budget.isExhausted, isTrue);
      expect(budget.used, 2);
      expect(() => budget.reserve(), throwsA(isA<LiveBudgetExceeded>()));
      expect(
        budget.used,
        2,
        reason: 'неудачная попытка не увеличивает счётчик',
      );
    });

    test('нулевой бюджет недоступен с первого запроса', () {
      final budget = LiveRequestBudget(maxRequests: 0);
      expect(() => budget.reserve(), throwsA(isA<LiveBudgetExceeded>()));
    });

    test(
      'обёртка считает запросы, размер тела и время; ошибка — с кодом',
      () async {
        final FakeGenerationTransport inner = FakeGenerationTransport(
          response: <String, Object?>{'ok': true},
        );
        final LiveProbeTransport probe = LiveProbeTransport(
          inner: inner,
          budget: LiveRequestBudget(maxRequests: 4),
        );
        final ProviderRequest request = ProviderRequest(
          uri: Uri.parse('https://provider.test/v1/generate'),
          headers: const <String, String>{'Authorization': 'Bearer SECRET'},
          body: <String, Object?>{'model': 'm', 'text': 'привет'},
        );

        await probe.postJson(request);
        await probe.postJson(request);

        expect(inner.calls, 2);
        expect(probe.exchanges, hasLength(2));
        expect(probe.totalBytes, greaterThan(0));
        expect(probe.totalDuration, isNot(Duration.zero));
      },
    );

    test('обёртка фиксирует код ошибки и не маскирует исключение', () async {
      final LiveProbeTransport probe = LiveProbeTransport(
        inner: FakeGenerationTransport(
          error: const GenerationException(GenerationErrorCode.rateLimited),
        ),
        budget: LiveRequestBudget(maxRequests: 2),
      );
      await expectLater(
        probe.postJson(
          ProviderRequest(
            uri: Uri.parse('https://provider.test/v1/generate'),
            headers: const <String, String>{},
            body: const <String, Object?>{'model': 'm'},
          ),
        ),
        throwsA(isA<GenerationException>()),
      );
      expect(probe.exchanges.single.success, isFalse);
      expect(probe.exchanges.single.errorCode, 'rateLimited');
    });

    test('лимитер HTTP-попыток отклоняет лишние запросы', () async {
      final LiveAttemptLimiter limiter = LiveAttemptLimiter(maxAttempts: 1);
      final dio = dioWithAdapter(
        FakeHttpAdapter(
          (RequestOptions options) =>
              jsonResponse(<String, Object?>{'ok': true}),
        ),
      );
      dio.interceptors.add(limiter);

      await dio.post<dynamic>('https://api.test/v1');
      expect(limiter.attempts, 1);

      await expectLater(
        dio.post<dynamic>('https://api.test/v1'),
        throwsA(isA<DioException>()),
      );
      expect(limiter.rejected, 1);
    });
  });

  group('Отчёт калибровки', () {
    GenerationRunResult runWith({
      required TokenValue actualInput,
      required TokenValue actualOutput,
    }) {
      return GenerationRunResult(
        jobId: 'job',
        status: GenerationJobStatus.done,
        cards: const <GeneratedCard>[],
        failures: const <GenerationChunkFailure>[],
        tokensUsed: 0,
        estimatedTokens: 0,
        duplicatesRemoved: 0,
        chunkCount: 1,
        cancelled: false,
        calibration: TokenCalibrationReport(
          samples: <TokenCalibrationSample>[
            TokenCalibrationSample(
              chunkIndex: 1,
              attempt: 1,
              recovered: false,
              plannedInput: TokenValue.estimate(9000, source: 'plan'),
              requestInput: TokenValue.estimate(9500, source: 'request'),
              actualInput: actualInput,
              actualOutput: actualOutput,
              reservedOutput: TokenValue.reserve(3000, source: 'request'),
              estimatorVersion: 'heuristic/1/request-1',
            ),
          ],
          failedRequests: 0,
        ),
        recoveryRequestsUsed: 2,
      );
    }

    test('заполняет факты, когда провайдер вернул usage', () {
      final FakeGenerationTransport inner = FakeGenerationTransport();
      final LiveProbeTransport probe = LiveProbeTransport(
        inner: inner,
        budget: LiveRequestBudget(maxRequests: 2),
      );
      final LiveRunRecord record = LiveRunRecord.fromRun(
        scenario: 'prompt_only_short',
        startedAt: DateTime.utc(2026, 11, 19, 6, 0),
        provider: 'deepseek',
        model: 'deepseek-flash',
        result: runWith(
          actualInput: const TokenValue.exact(10000, source: 'usage'),
          actualOutput: const TokenValue.exact(1200, source: 'usage'),
        ),
        probe: probe,
        imageCount: 0,
        httpAttempts: 2,
      );
      final Map<String, Object?> json = record.toJson();
      expect(json['provider'], 'deepseek');
      expect(json['model'], 'deepseek-flash');
      expect(json['estimatorVersion'], 'heuristic/1/request-1');
      expect(json['estimatedInputTokens'], 9500);
      expect(json['actualInputTokens'], 10000);
      expect(json['actualOutputTokens'], 1200);
      expect(json['estimatedOutputTokens'], 3000);
      expect(json['resultStatus'], 'done');
      expect(json['recoveryCount'], 2);
      expect(json['httpAttempts'], 2);
      expect(json['note'], isNull);
      expect(json['startedAt'], startsWith('2026-11-19'));
    });

    test('отсутствующий usage остаётся null, а не 0', () {
      final LiveRunRecord record = LiveRunRecord.fromRun(
        scenario: 'prompt_only_short',
        startedAt: DateTime.utc(2026, 11, 19),
        provider: 'deepseek',
        model: 'deepseek-flash',
        result: runWith(
          actualInput: const TokenValue.unknown(source: 'usage.prompt_tokens'),
          actualOutput: const TokenValue.unknown(
            source: 'usage.completion_tokens',
          ),
        ),
        probe: LiveProbeTransport(
          inner: FakeGenerationTransport(),
          budget: LiveRequestBudget(maxRequests: 1),
        ),
        imageCount: 0,
        note: 'провайдер не сообщил usage',
      );
      final Map<String, Object?> json = record.toJson();
      expect(json['actualInputTokens'], isNull);
      expect(json['actualOutputTokens'], isNull);
      expect(json['estimatedInputTokens'], 9500);
      expect(json['note'], 'провайдер не сообщил usage');
    });

    test('рекордер пишет JSON Lines без значений ключей', () async {
      final recorder = LiveRunRecorder(
        reportPath: 'build/live/test-runs.jsonl',
      );
      recorder.add(
        LiveRunRecord.fromRun(
          scenario: 'test',
          startedAt: DateTime.utc(2026, 11, 19),
          provider: 'deepseek',
          model: 'deepseek-flash',
          result: runWith(
            actualInput: const TokenValue.exact(1, source: 'usage'),
            actualOutput: const TokenValue.exact(1, source: 'usage'),
          ),
          probe: LiveProbeTransport(
            inner: FakeGenerationTransport(),
            budget: LiveRequestBudget(maxRequests: 1),
          ),
          imageCount: 0,
        ),
      );
      expect(recorder.summary(), contains('test: done'));
      expect(recorder.totalRequests, 0);
    });
  });

  group('Качество карточек', () {
    test('находит дубли, пустые поля, превышение лимитов и теги', () {
      final List<GeneratedCard> cards = <GeneratedCard>[
        makeGeneratedCard(front: 'A', back: 'B', tags: const <String>['t']),
        makeGeneratedCard(front: 'A', back: 'B', tags: const <String>['t']),
        makeGeneratedCard(front: '', back: ''),
        makeGeneratedCard(
          front: 'x' * (kQualityMaxFrontLength + 1),
          back: 'y' * (kQualityMaxBackLength + 1),
          tags: const <String>['1', '2', '3', '4'],
        ),
      ];
      final LiveCardQualityReport report = LiveCardQualityReport.evaluate(
        cards,
      );
      expect(report.cardCount, 4);
      expect(report.duplicateCards, 1);
      expect(report.emptyFront, 1);
      expect(report.emptyBack, 1);
      expect(report.tooLongFront, 1);
      expect(report.tooLongBack, 1);
      expect(report.tooManyTags, 1);
      expect(report.isClean, isFalse);
      expect(report.toMarkdown(), contains('повторов'));
    });

    test('чистый набор проходит и сохраняет счётчики', () {
      final List<GeneratedCard> cards = <GeneratedCard>[
        makeGeneratedCard(front: 'Что такое FSRS?', back: 'Алгоритм.'),
        makeGeneratedCard(
          front: 'Что такое интервал?',
          back: 'Промежуток между повторениями.',
        ),
      ];
      final LiveCardQualityReport report = LiveCardQualityReport.evaluate(
        cards,
      );
      expect(report.isClean, isTrue);
      expect(report.duplicateCards, 0);
      expect(report.withImage, 0);
      expect(report.toJson()['cardCount'], 2);
    });
  });

  group('Тарифы', () {
    test('таблица содержит источник и дату проверки', () {
      for (final MapEntry<String, LivePrice> entry in kLivePrices.entries) {
        expect(
          entry.value.sourceUrl,
          startsWith('https://'),
          reason: entry.key,
        );
        expect(entry.value.verifiedOn, '2026-11-19', reason: entry.key);
        expect(entry.value.currency, 'USD', reason: entry.key);
        expect(entry.value.inputPerMillion, greaterThanOrEqualTo(0));
        expect(entry.value.outputPerMillion, greaterThanOrEqualTo(0));
      }
      expect(livePriceFor('deepseek', 'deepseek-flash'), isNotNull);
      expect(livePriceFor('deepseek', 'deepseek-chat'), isNull);
      expect(livePriceFor('gemini', 'gemini-2.0-flash'), isNull);
    });
  });
}
