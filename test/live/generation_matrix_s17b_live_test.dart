// Срез 17B, части 2–3: один замер гипотезы «контекст „уже создано“ снижает долю
// дублей» (TASK ч. 2) и сохранение карточек обоих путей для слепой выборки (ч. 3).
//
// Ячейки:
//   1) `textbook-v3-150-context` — путь v3, учебный материал, заказ 150: движок
//      теперь шлёт `<already_created>` (утверждения принятых единиц прогона и
//      занятые unit_id). Сравнение — с уже оплаченной `textbook-v3-150` среза 16
//      (контекста не было).
//   2) `textbook-legacy-150-cards` — прежний путь на том же материале: его
//      карточки нужны для слепой выборки 30 + 30 (в ячейках среза 16 текстов нет).
//
// ВАЖНО: по умолчанию не делает ни одного запроса. Запуск — только явно:
//   CARDFLOW_LIVE_TESTS=1
//   CARDFLOW_LIVE_PROVIDER=deepseek
//   CARDFLOW_LIVE_MODEL=deepseek-flash
//   CARDFLOW_LIVE_MAX_REQUESTS=20
//   CARDFLOW_LIVE_MAX_COST_USD=0.30        (потолок TASK ч. 2)
//   DEEPSEEK_API_KEY=…                     (значение не печатается)
// Отчёт: journal/generation-v3/live-s17b/{matrix.jsonl,matrix.md,run.json,cells/}.
//
// Потолок расхода — 0,30 USD на обе ячейки (строже TASK: там потолок на одну);
// при исчерпании ячейка пишется `not_run` с причиной, а не «успешной».
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/generation_v3_path.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/metrics_collector.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';
import 'support/code_version.dart';
import 'support/live_budget.dart';
import 'support/live_payload_probe.dart';
import 'support/live_pricing.dart';
import 'support/live_test_config.dart';
import 'support/s12_bench.dart';
import 'support/s15_materials.dart';

/// Заказ замера: 150 карточек учебного материала (TASK ч. 2, п. 4).
const int kS17bRequested = 150;

void main() {
  final LiveTestConfig config = LiveTestConfig.fromEnvironment(
    Platform.environment,
  );
  final LivePrice? price = livePriceFor(config.provider, config.model);
  final String? skipReason =
      config.skipReason ??
      (price == null && !config.allowUnknownCost
          ? 'Тариф ${config.provider}/${config.model} неизвестен: '
                '$kLiveAllowUnknownCostVariable=1 для осознанного риска'
          : null);

  test(
    'S17B: v3 с контекстом 150 + legacy 150 (карточки для слепой выборки)',
    () async {
      final DateTime startedAt = DateTime.now();
      final Stopwatch matrixWatch = Stopwatch()..start();
      final int deadlineMinutes =
          int.tryParse(
            Platform.environment['CARDFLOW_S17B_DEADLINE_MIN'] ?? '',
          ) ??
          40;
      final DateTime deadline = DateTime.now().add(
        Duration(minutes: deadlineMinutes),
      );
      final CodeVersion code = CodeVersion.detect();

      final Dio dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 15),
          sendTimeout: const Duration(seconds: 60),
          receiveTimeout: config.timeout,
        ),
      );
      final LiveRequestBudget logicalBudget = LiveRequestBudget(
        maxRequests: config.maxRequests,
        label: '${config.provider}/${config.model} logical',
      );
      final LiveRequestBudget httpBudget = LiveRequestBudget(
        maxRequests: config.maxRequests,
        label: '${config.provider}/${config.model} http',
      );
      final LiveCostGuard? costGuard =
          price != null && config.maxEstimatedCostUsd > 0
          ? LiveCostGuard(
              price: price,
              maxCostUsd: config.maxEstimatedCostUsd,
              label: '${config.provider}/${config.model}',
            )
          : null;
      final LiveAttemptLimiter limiter = LiveAttemptLimiter(
        maxAttempts: httpBudget.maxRequests * RetryPolicy().maxAttempts,
        costGuard: costGuard,
      );
      dio.interceptors.add(limiter);
      final GenerationDiagnostics diagnostics = GenerationDiagnostics(
        enabled: true,
        sink: (_) {},
      );
      final GenerationHttpClient httpClient = GenerationHttpClient(
        dio: dio,
        retryPolicy: RetryPolicy(),
        diagnostics: diagnostics,
      );
      final LiveProbeTransport probe = LiveProbeTransport(
        inner: httpClient,
        budget: httpBudget,
      );
      // Наблюдатель формы запроса: только числа (байты, маркеры контекста).
      final LivePayloadProbe payload = LivePayloadProbe(inner: probe);
      final FakeApiKeyStore apiKeys = FakeApiKeyStore(<String, String>{
        config.provider: config.apiKey ?? '',
      });
      final CardGenerationService service = CardGenerationService(
        adapters: generationAdapters,
        apiKeyStore: apiKeys,
        httpClient: probe,
        diagnostics: diagnostics,
      );
      final LiveRecordingCaller caller = LiveRecordingCaller(
        inner: service,
        budget: logicalBudget,
      );
      final GenerationPipeline legacy = GenerationPipeline(
        caller: caller,
        jobRepository: FakeGenerationJobRepository(),
        cardStore: FakeGenerationCardStore(),
        diagnostics: diagnostics,
      );
      final AppDatabase database = AppDatabase.inMemory();
      final GenerationV3PathRunner v3 = GenerationV3PathRunner(
        apiKeyStore: apiKeys,
        transport: payload,
        runStore: DriftGenerationRunStore(database),
        knowledgeMapCache: DriftKnowledgeMapCache(database),
        importer: (String runId, String? deckId, String deckName) async => 0,
      );
      final S12Bench bench = S12Bench(
        outputDir:
            Platform.environment['CARDFLOW_S17B_OUT_DIR'] ??
            'journal/generation-v3/live-s17b',
        provider: config.provider,
        model: config.model,
        title: 'Срез 17B — v3 с контекстом «уже создано» и legacy для выборки',
      );

      String? stopReason() {
        if (httpBudget.isExhausted) return 'бюджет матрицы исчерпан';
        if (costGuard != null && costGuard.isExhausted) {
          return 'потолок расхода матрицы исчерпан '
              '(${costGuard.maxCostUsd.toStringAsFixed(2)} USD)';
        }
        if (DateTime.now().isAfter(deadline)) {
          return 'дедлайн матрицы ($deadlineMinutes мин)';
        }
        return null;
      }

      // Форма каждого запроса по ячейкам (только числа; в run.json).
      final Map<String, List<Map<String, Object?>>> shapes =
          <String, List<Map<String, Object?>>>{};
      final S15Material textbook = s15Materials().first;

      Future<void> runCell({
        required String cellId,
        required S15Material material,
        required bool v3Path,
      }) async {
        final String path = v3Path ? 'v3' : 'legacy';
        final String? reason = stopReason();
        if (reason != null) {
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: material.name,
              materialSections: material.sections,
              requested: kS17bRequested,
              path: path,
              status: BenchCellStatus.notRun,
              reason: reason,
            ),
          );
          return;
        }
        costGuard?.outputTokensPerRequest = 1000 + kS17bRequested * 80;
        final int probeFrom = payload.requests.length;
        final Stopwatch watch = Stopwatch()..start();
        try {
          final GenerationRunResult result;
          if (v3Path) {
            result = await v3.run(
              GenerationRunRequest(
                documents: <ParsedDocument>[material.document],
                account: config.account,
                deckName: 'S17B ${material.id}',
                requestedCards: kS17bRequested,
              ),
              runId: 's17b-${material.id}-$path',
              cancellation: GenerationCancellation(),
            );
          } else {
            result = await legacy.run(
              GenerationRunRequest(
                documents: <ParsedDocument>[material.document],
                account: config.account,
                deckName: 'S17B ${material.id}',
                requestedCards: kS17bRequested,
              ),
            );
          }
          watch.stop();
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: material.name,
              materialSections: material.sections,
              requested: kS17bRequested,
              path: path,
              status: BenchCellStatus.ran,
              durationMs: watch.elapsedMilliseconds,
              stage: result.report?.stage.name,
              reportAccepted: result.report?.accepted ?? result.cards.length,
              reportRequested: result.report?.requested ?? kS17bRequested,
              understandingFailures:
                  result.report?.understandingFailures ?? const <String>[],
              promptVersions:
                  result.report?.promptVersions ?? const <String, String>{},
              savedCards: <BenchSavedCard>[
                for (final GeneratedCard card in result.cards)
                  BenchSavedCard.fromGeneratedCard(card),
              ],
              metrics: result.report == null
                  ? null
                  : const MetricsCollector().collect(result.report!),
            ),
          );
        } on LiveBudgetExceeded catch (error) {
          watch.stop();
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: material.name,
              materialSections: material.sections,
              requested: kS17bRequested,
              path: path,
              status: BenchCellStatus.notRun,
              reason: error.message,
              durationMs: watch.elapsedMilliseconds,
            ),
          );
        } on GenerationException catch (error) {
          watch.stop();
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: material.name,
              materialSections: material.sections,
              requested: kS17bRequested,
              path: path,
              status: BenchCellStatus.failed,
              reason: 'ошибка провайдера',
              errorCode: error.code.name,
              durationMs: watch.elapsedMilliseconds,
            ),
          );
        } on Object catch (error) {
          watch.stop();
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: material.name,
              materialSections: material.sections,
              requested: kS17bRequested,
              path: path,
              status: BenchCellStatus.failed,
              reason: 'исключение до отчёта',
              errorCode: error.runtimeType.toString(),
              durationMs: watch.elapsedMilliseconds,
            ),
          );
        } finally {
          // Форма каждого запроса — в run.json; тексты и ключи не пишутся.
          shapes[cellId] = <Map<String, Object?>>[
            for (final LiveRequestShape shape in payload.requests.skip(
              probeFrom,
            ))
              shape.toJson(),
          ];
        }
      }

      try {
        // 1) Ячейка гипотезы: v3 с контекстом «уже создано».
        await runCell(
          cellId: 'textbook-v3-150-context',
          material: textbook,
          v3Path: true,
        );
        // 2) Карточки прежнего пути для слепой выборки 30 + 30.
        await runCell(
          cellId: 'textbook-legacy-150-cards',
          material: textbook,
          v3Path: false,
        );
      } finally {
        matrixWatch.stop();
        await bench.writeRunSummary(<String, Object?>{
          'srez': '17B',
          'code_version': code.value,
          'code_dirty': code.dirty,
          'started_at': startedAt.toUtc().toIso8601String(),
          'finished_at': DateTime.now().toUtc().toIso8601String(),
          'matrix_duration_ms': matrixWatch.elapsedMilliseconds,
          'logical_requests': logicalBudget.used,
          'http_requests': httpBudget.used,
          'attempts': limiter.attempts,
          'attempts_rejected': limiter.rejected,
          'cost_guard': costGuard?.toJson(),
          'deadline_minutes': deadlineMinutes,
          'cells': bench.cellCount,
          'request_shapes': shapes,
        });
        await bench.writeMarkdown();
        await database.close();
        dio.close(force: true);
      }

      // Форма запросов — в отчёт: сколько было запросов с контекстом.
      for (final MapEntry<String, List<Map<String, Object?>>> entry
          in shapes.entries) {
        final int withContext = entry.value
            .where(
              (Map<String, Object?> shape) =>
                  (shape['already_created'] as int) > 0,
            )
            .length;
        // ignore: avoid_print — числа замера снимаются из вывода теста.
        print(
          '${entry.key}: запросов ${entry.value.length}, '
          'с <already_created> $withContext, '
          'байты ${entry.value.map((Map<String, Object?> s) => s['bytes']).join('/')}',
        );
      }

      final int ran = bench.cells
          .where((BenchCell cell) => cell.status == BenchCellStatus.ran)
          .length;
      // DoD ч. 2, п. 6: стенд обязан записать карточки — пустой файл это блокер.
      for (final BenchCell cell in bench.cells) {
        if (cell.status != BenchCellStatus.ran) continue;
        final String path = '${bench.outputDir}/cells/${cell.cellId}.json';
        final File file = File(path);
        expect(file.existsSync(), isTrue, reason: 'нет файла ячейки $path');
        final String raw = file.readAsStringSync();
        expect(raw.length, greaterThan(0), reason: 'файл ячейки пуст: $path');
        expect(
          raw.contains('"cards"'),
          isTrue,
          reason: 'ячейка ${cell.cellId} не записала карточки (ключ cards)',
        );
      }
      expect(ran, 2, reason: 'обе ячейки замера выполнены');
    },
    skip: skipReason,
    timeout: const Timeout(Duration(hours: 3)),
  );
}
