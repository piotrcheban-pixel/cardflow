/// Проводка live-прогона: production-адаптеры, транспорт с бюджетом, отчёт.
///
/// Один harness на файл теста: он собирает те же адаптеры, что приложение
/// (`generationAdapters`), тот же `CardGenerationService` и `GenerationPipeline`,
/// но с In-memory хранилищем заданий/карточек. Никаких production-ключей, БД
/// и пользовательских материалов: только материалы сценария и ключ из
/// окружения.
///
/// Всё, что может потратить деньги, проходит через [LiveRequestBudget] и
/// [LiveProbeTransport]; отчёт пишется в `build/live/` и содержит только числа
/// и машинные коды.
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
    required this.probe,
    required this.attemptLimiter,
    required this.pipeline,
    required this.diagnosticsLog,
  });

  /// Собирает harness из [config].
  ///
  /// Ключ берётся только из окружения; при его отсутствии вызывающая сторона
  /// обязана пропустить тест (`config.skipReason`).
  factory LiveHarness.create({
    required LiveTestConfig config,
    LiveRunRecorder? recorder,
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
    final LiveRequestBudget budget = LiveRequestBudget(
      maxRequests: config.maxRequests,
      label: '${config.provider}/${config.model}',
    );
    // Страховка: один логический запрос может дать несколько HTTP-попыток
    // (retry на 429/5xx). Лимит — с запасом 4×, но конечный.
    final LiveAttemptLimiter attemptLimiter = LiveAttemptLimiter(
      maxAttempts: config.maxRequests * RetryPolicy().maxAttempts,
    );
    dio.interceptors.add(attemptLimiter);

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
      budget: budget,
    );
    final CardGenerationService service = CardGenerationService(
      adapters: generationAdapters,
      apiKeyStore: FakeApiKeyStore(<String, String>{
        config.provider: apiKey ?? '',
      }),
      httpClient: probe,
      diagnostics: diagnostics,
    );
    final GenerationPipeline pipeline = GenerationPipeline(
      caller: service,
      jobRepository: FakeGenerationJobRepository(),
      cardStore: FakeGenerationCardStore(),
      diagnostics: diagnostics,
    );
    return LiveHarness._(
      config: config,
      recorder: recorder ?? LiveRunRecorder(reportPath: config.reportPath),
      dio: dio,
      budget: budget,
      probe: probe,
      attemptLimiter: attemptLimiter,
      pipeline: pipeline,
      diagnosticsLog: diagnosticsLog,
    );
  }

  /// Конфигурация прогона.
  final LiveTestConfig config;

  /// Рекордер отчёта.
  final LiveRunRecorder recorder;

  /// Dio (для закрытия после теста).
  final Dio dio;

  /// Бюджет логических запросов.
  final LiveRequestBudget budget;

  /// Транспорт-обёртка (размеры тел, время, счётчик).
  final LiveProbeTransport probe;

  /// Лимитер HTTP-попыток.
  final LiveAttemptLimiter attemptLimiter;

  /// Пайплайн (production-адаптеры, in-memory job/card store).
  final GenerationPipeline pipeline;

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
  /// [imageCount] — сколько изображений сценарий приложил к запросу: сервис
  /// отправляет их частями только при Vision, поэтому это входная величина, а
  /// не «сколько модель увидела».
  Future<LiveScenarioOutcome> run({
    required String scenario,
    required GenerationRunRequest request,
    int imageCount = 0,
    String? note,
  }) async {
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
      httpAttempts: attemptLimiter.attempts,
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
      ..writeln('budget: $budget')
      ..writeln(
        'attempts: ${attemptLimiter.attempts}, '
        'rejected: ${attemptLimiter.rejected}',
      )
      ..writeln(
        'requests: ${probe.exchanges.length}, '
        'bytes: ${probe.totalBytes}, '
        'duration: ${probe.totalDuration.inMilliseconds} ms',
      );
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
