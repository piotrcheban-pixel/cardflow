/// Проводка live-прогона: production-адаптеры, транспорт с бюджетом, отчёт.
///
/// Один harness на сценарий: он собирает те же адаптеры, что приложение
/// (`generationAdapters`), тот же `CardGenerationService` и `GenerationPipeline`,
/// но с In-memory хранилищем заданий/карточек. Никаких production-ключей, БД
/// и пользовательских материалов: только материалы сценария и ключ из
/// окружения.
///
/// Всё, что может потратить деньги, проходит через общий [LiveRequestBudget]
/// (логические запросы), [LiveProbeTransport] (HTTP-обмены), [LiveAttemptLimiter]
/// (физические попытки) и [LiveCostGuard] (предварительная стоимость).
/// Бюджеты можно передать общими на весь файл — тогда A–C делят один лимит.
library;

import 'dart:io';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/redacting_log_interceptor.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/domain/generation/generation_run.dart';

import '../../helpers/generation_fakes.dart';
import 'live_budget.dart';
import 'live_run_report.dart';
import 'live_test_config.dart';

/// Результат одного сценария вместе с записью отчёта.
class LiveScenarioOutcome {
  /// Создаёт результат.
  const LiveScenarioOutcome({
    required this.result,
    required this.record,
    required this.elapsed,
  });

  /// Результат пайплайна (карточки, ошибки, калибровка).
  final GenerationRunResult result;

  /// Запись отчёта (числа, без материалов).
  final LiveRunRecord record;

  /// Длительность сценария по стенным часам.
  final Duration elapsed;
}

/// Проводка live-тестов.
class LiveHarness {
  LiveHarness._({
    required this.config,
    required this.recorder,
    required this.dio,
    required this.budget,
    required this.httpBudget,
    required this.probe,
    required this.attemptLimiter,
    required this.pipeline,
    required this.calls,
    required this.diagnosticsLog,
    this.costGuard,
  });

  /// Собирает harness из [config].
  ///
  /// [budget]/[httpBudget]/[attemptLimiter]/[costGuard] можно передать общими
  /// на весь файл тестов; иначе создаются с лимитами из [config].
  factory LiveHarness.create({
    required LiveTestConfig config,
    LiveRunRecorder? recorder,
    LiveRequestBudget? budget,
    LiveRequestBudget? httpBudget,
    LiveAttemptLimiter? attemptLimiter,
    LiveCostGuard? costGuard,
  }) {
    final String? apiKey = config.apiKey;
    if (config.requiresApiKey && (apiKey == null || apiKey.isEmpty)) {
      throw StateError(
        'LiveHarness без ключа: тест обязан пропуститься по config.skipReason',
      );
    }
    final Dio dio = Dio(
      BaseOptions(
        connectTimeout: _min(config.timeout, const Duration(seconds: 15)),
        sendTimeout: _min(config.timeout, const Duration(seconds: 60)),
        receiveTimeout: config.timeout,
      ),
    );
    final LiveRequestBudget logicalBudget =
        budget ??
        LiveRequestBudget(
          maxRequests: config.maxRequests,
          label: '${config.provider}/${config.model}',
        );
    // Один логический запрос в худшем случае даёт strict + tolerant обмен.
    final int defaultHttpRequests = config.maxRequests * 2;
    final LiveRequestBudget sharedHttpBudget =
        httpBudget ??
        LiveRequestBudget(
          maxRequests: defaultHttpRequests,
          label: '${config.provider}/${config.model} http',
        );
    // Физические попытки: до RetryPolicy.maxAttempts на HTTP-обмен. Лимит
    // конечный; стоимость дополнительно ограничена [LiveCostGuard].
    final LiveAttemptLimiter limiter =
        attemptLimiter ??
        LiveAttemptLimiter(
          maxAttempts: sharedHttpBudget.maxRequests * RetryPolicy().maxAttempts,
          costGuard: costGuard,
        );
    dio.interceptors.add(limiter);

    final List<String> diagnosticsLog = <String>[];
    final GenerationDiagnostics diagnostics = GenerationDiagnostics(
      enabled: true,
      sink: diagnosticsLog.add,
    );
    final GenerationHttpClient httpClient = GenerationHttpClient(
      dio: dio,
      retryPolicy: RetryPolicy(),
      diagnostics: diagnostics,
    );
    final LiveProbeTransport probe = LiveProbeTransport(
      inner: httpClient,
      budget: sharedHttpBudget,
    );
    final CardGenerationService service = CardGenerationService(
      adapters: generationAdapters,
      apiKeyStore: FakeApiKeyStore(<String, String>{
        config.provider: apiKey ?? '',
      }),
      httpClient: probe,
      diagnostics: diagnostics,
    );
    final List<LiveCallRecord> calls = <LiveCallRecord>[];
    final LiveRecordingCaller caller = LiveRecordingCaller(
      inner: service,
      budget: logicalBudget,
      records: calls,
    );
    final GenerationPipeline pipeline = GenerationPipeline(
      caller: caller,
      jobRepository: FakeGenerationJobRepository(),
      cardStore: FakeGenerationCardStore(),
      diagnostics: diagnostics,
    );
    return LiveHarness._(
      config: config,
      recorder: recorder ?? LiveRunRecorder(reportPath: config.reportPath),
      dio: dio,
      budget: logicalBudget,
      httpBudget: sharedHttpBudget,
      probe: probe,
      attemptLimiter: limiter,
      pipeline: pipeline,
      calls: calls,
      diagnosticsLog: diagnosticsLog,
      costGuard: costGuard,
    );
  }

  /// Конфигурация прогона.
  final LiveTestConfig config;

  /// Рекордер отчёта.
  final LiveRunRecorder recorder;

  /// Dio (для закрытия после теста).
  final Dio dio;

  /// Бюджет логических запросов (вызовы генерации).
  final LiveRequestBudget budget;

  /// Бюджет HTTP-обменов (вызовы транспорта).
  final LiveRequestBudget httpBudget;

  /// Транспорт-обёртка (размеры тел, время, стоимость обменов).
  final LiveProbeTransport probe;

  /// Лимитер физических HTTP-попыток.
  final LiveAttemptLimiter attemptLimiter;

  /// Пайплайн (production-адаптеры, in-memory job/card store).
  final GenerationPipeline pipeline;

  /// Журнал логических запросов сценария (без текстов).
  final List<LiveCallRecord> calls;

  /// Учёт стоимости; `null` — guard не создан (цена неизвестна).
  final LiveCostGuard? costGuard;

  /// Debug-диагностика прогона (без ключей; используется только при разборе).
  final List<String> diagnosticsLog;

  /// Журнал HTTP-заголовков/URI без секретов (redaction-перехватчик).
  final List<String> httpLog = <String>[];

  /// Включает логирование HTTP без секретов (для разбора провала).
  void enableHttpLog() {
    dio.interceptors.insert(0, RedactingLogInterceptor(sink: httpLog.add));
  }

  /// Выполняет сценарий и записывает отчёт.
  ///
  /// [expectedOutputTokens] — ожидаемый выход одного запроса из плана сценария:
  /// по нему [LiveCostGuard] проверяет бюджет **до** отправки. [imageCount] —
  /// сколько изображений сценарий передаёт модели (входная величина).
  Future<LiveScenarioOutcome> run({
    required String scenario,
    required GenerationRunRequest request,
    int imageCount = 0,
    int expectedOutputTokens = 3000,
    String? note,
  }) async {
    final int attemptsBefore = attemptLimiter.attempts;
    final double spentBefore = costGuard?.spentUsd ?? 0;
    costGuard?.outputTokensPerRequest = expectedOutputTokens;
    final DateTime startedAt = DateTime.now();
    final Stopwatch stopwatch = Stopwatch()..start();
    final GenerationRunResult result = await pipeline.run(request);
    stopwatch.stop();
    final LiveRunRecord record = LiveRunRecord.fromRun(
      scenario: scenario,
      startedAt: startedAt,
      provider: config.provider,
      model: config.model,
      result: result,
      probe: probe,
      imageCount: imageCount,
      httpAttempts: attemptLimiter.attempts - attemptsBefore,
      logicalRequests: calls.length,
      httpBudget: httpBudget,
      costGuard: costGuard,
      guardSpentUsd: (costGuard?.spentUsd ?? 0) - spentBefore,
      elapsed: stopwatch.elapsed,
      note: note,
    );
    recorder.add(record);
    return LiveScenarioOutcome(
      result: result,
      record: record,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Пишет отчёт прогона; возвращает путь файла.
  Future<String> writeReport() => recorder.write();

  /// Закрывает соединения.
  void close() => dio.close(force: true);

  /// Краткая диагностика для `print` при падении: без материалов и ключей.
  String diagnosticsSummary() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('logical budget: $budget')
      ..writeln('http budget: $httpBudget')
      ..writeln(
        'attempts: ${attemptLimiter.attempts}, '
        'rejected: ${attemptLimiter.rejected}',
      )
      ..writeln(
        'http exchanges: ${probe.exchanges.length}, '
        'bytes: ${probe.totalBytes}, '
        'duration: ${probe.totalDuration.inMilliseconds} ms',
      );
    if (costGuard != null) {
      buffer.writeln('cost: $costGuard');
    }
    for (final LiveCallRecord call in calls) {
      buffer.writeln('call: ${call.toJson()}');
    }
    for (final String line in diagnosticsLog) {
      buffer.writeln('diag: $line');
    }
    for (final String line in httpLog) {
      buffer.writeln('http: $line');
    }
    return buffer.toString();
  }

  static Duration _min(Duration a, Duration b) => a < b ? a : b;

  /// Проверяет, что каталог отчёта существует (не обязательное условие).
  static Future<void> ensureReportDirectory(String path) async {
    await File(path).parent.create(recursive: true);
  }
}
