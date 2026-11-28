// Срез 16, часть 2: честный перемер **только решающих** ячеек —
// 2 материала × заказы 80/150/300 × 2 пути = 12 ячеек. Промпты и пороги
// валидатора заморожены; у каждой строки `matrix.jsonl` — `code_version`, у
// каждой ячейки — свой `cells/<cellId>.json` для пересчёта без повторных
// запросов.
//
// ВАЖНО: по умолчанию не делает ни одного запроса. Запуск — только явно:
//   CARDFLOW_LIVE_TESTS=1
//   CARDFLOW_LIVE_PROVIDER=deepseek
//   CARDFLOW_LIVE_MODEL=deepseek-flash
//   CARDFLOW_LIVE_MAX_REQUESTS=180
//   CARDFLOW_LIVE_MAX_COST_USD=1.00
//   DEEPSEEK_API_KEY=…                       (значение не печатается)
// Отчёт: journal/generation-v3/live-s16/{matrix.jsonl,matrix.md,run.json,cells/}.
//
// Потолок расхода — 1,00 USD: при исчерпании ячейка пишется `not_run` с
// причиной, а не «успешной». Нерешающие ячейки 20/40 в перемер не входят
// (TASK: «не пересчитывать нерешающие ячейки»).
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/generation_v3_path.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/metrics_collector.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';
import 'support/code_version.dart';
import 'support/live_budget.dart';
import 'support/live_pricing.dart';
import 'support/live_test_config.dart';
import 'support/s12_bench.dart';
import 'support/s15_materials.dart';

/// Заказы решающих ячеек: 20/40 в перемер не входят (TASK Срез 16, п. 4).
const List<int> kS16Sizes = <int>[80, 150, 300];

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
    'перемер S16: 2 материала × 80/150/300 × legacy/v3 (12 ячеек)',
    () async {
      final DateTime startedAt = DateTime.now();
      final Stopwatch matrixWatch = Stopwatch()..start();
      final int deadlineMinutes =
          int.tryParse(
            Platform.environment['CARDFLOW_S16_DEADLINE_MIN'] ?? '',
          ) ??
          50;
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
        transport: probe,
        runStore: DriftGenerationRunStore(database),
        knowledgeMapCache: DriftKnowledgeMapCache(database),
        importer: (String runId, String? deckId, String deckName) async => 0,
      );
      final S12Bench bench = S12Bench(
        outputDir:
            Platform.environment['CARDFLOW_S16_OUT_DIR'] ??
            'journal/generation-v3/live-s16',
        provider: config.provider,
        model: config.model,
        title: 'Срез 16 — честный перемер решающих ячеек (80/150/300)',
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

      Future<void> runCell({
        required String materialId,
        required String materialName,
        required int sections,
        required ParsedDocument document,
        required int requested,
        required bool v3Path,
      }) async {
        final String path = v3Path ? 'v3' : 'legacy';
        final String cellId = '$materialId-$path-$requested';
        final String? reason = stopReason();
        if (reason != null) {
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: materialName,
              materialSections: sections,
              requested: requested,
              path: path,
              status: BenchCellStatus.notRun,
              reason: reason,
            ),
          );
          return;
        }
        // Резерв стоимости на запрос — по ожидаемому выходу этого прогона.
        costGuard?.outputTokensPerRequest = 1000 + requested * 80;
        final Stopwatch watch = Stopwatch()..start();
        try {
          final GenerationRunResult result;
          if (v3Path) {
            result = await v3.run(
              GenerationRunRequest(
                documents: <ParsedDocument>[document],
                account: config.account,
                deckName: 'S15 $materialId $requested',
                requestedCards: requested,
              ),
              runId: 's16-$materialId-$path-$requested',
              cancellation: GenerationCancellation(),
            );
          } else {
            result = await legacy.run(
              GenerationRunRequest(
                documents: <ParsedDocument>[document],
                account: config.account,
                deckName: 'S15 $materialId $requested',
                requestedCards: requested,
              ),
            );
          }
          watch.stop();
          await bench.add(
            BenchCell(
              cellId: cellId,
              codeVersion: code.value,
              material: materialName,
              materialSections: sections,
              requested: requested,
              path: path,
              status: BenchCellStatus.ran,
              durationMs: watch.elapsedMilliseconds,
              stage: result.report?.stage.name,
              reportAccepted: result.report?.accepted ?? result.cards.length,
              reportRequested: result.report?.requested ?? requested,
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
              material: materialName,
              materialSections: sections,
              requested: requested,
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
              material: materialName,
              materialSections: sections,
              requested: requested,
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
              material: materialName,
              materialSections: sections,
              requested: requested,
              path: path,
              status: BenchCellStatus.failed,
              reason: 'исключение до отчёта',
              errorCode: error.runtimeType.toString(),
              durationMs: watch.elapsedMilliseconds,
            ),
          );
        }
      }

      try {
        for (final S15Material material in s15Materials()) {
          for (final int size in kS16Sizes) {
            for (final bool v3Path in <bool>[false, true]) {
              await runCell(
                materialId: material.id,
                materialName: material.name,
                sections: material.sections,
                document: material.document,
                requested: size,
                v3Path: v3Path,
              );
            }
          }
        }
      } finally {
        matrixWatch.stop();
        await bench.writeRunSummary(<String, Object?>{
          'srez': 16,
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
        });
        await bench.writeMarkdown();
        await database.close();
        dio.close(force: true);
      }

      final int ran = bench.cells
          .where((BenchCell cell) => cell.status == BenchCellStatus.ran)
          .length;
      final int failed = bench.cells
          .where((BenchCell cell) => cell.status == BenchCellStatus.failed)
          .length;
      final String markdown = await File('${bench.outputDir}/matrix.md')
          .readAsString();
      // ignore: avoid_print — таблица снимается из вывода теста.
      print(markdown);
      expect(
        bench.cellCount,
        s15Materials().length * kS16Sizes.length * 2,
        reason: '12 решающих ячеек: 2 материала × 3 заказа × 2 пути',
      );
      if (Platform.environment['CARDFLOW_S16_REQUIRE_ALL'] == '1') {
        expect(failed, 0, reason: 'у ячейки — ran или not_run с причиной');
        expect(ran, 12, reason: 'DoD: перемерены все 12 решающих ячеек');
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(hours: 4)),
  );
}
