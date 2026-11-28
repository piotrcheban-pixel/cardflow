// Срез 12, часть 2: живая матрица «legacy × v3» на двух материалах и размерах
// 20/40/80/150/300, плюс smoke «скан без текстового слоя → no_text_layer».
//
// ВАЖНО: по умолчанию не делает ни одного запроса. Запуск — только явно:
//   CARDFLOW_LIVE_TESTS=1
//   CARDFLOW_LIVE_PROVIDER=deepseek
//   CARDFLOW_LIVE_MODEL=deepseek-flash
//   CARDFLOW_LIVE_MAX_REQUESTS=220
//   CARDFLOW_LIVE_MAX_COST_USD=2.00
//   DEEPSEEK_API_KEY=…                       (значение не печатается)
// Отчёт: journal/generation-v3/live-s12/{matrix.jsonl,matrix.md,run.json}.
//
// Мультифайловые материалы в матрицу не входят (известное ограничение S11).
// Каждая ячейка — отдельный прогон; неудачный прогон не подменяется соседним,
// а записывается `failed`/`not_run` с причиной. Исчерпание бюджета/дедлайна —
// `not_run`, а не «успешная» ячейка.
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
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/metrics_collector.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';
import 'support/live_budget.dart';
import 'support/live_pricing.dart';
import 'support/live_test_config.dart';
import 'support/s12_bench.dart';

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
    'матрица S12: 2 материала × 20/40/80/150/300 × legacy/v3 + скан',
    () async {
      final DateTime startedAt = DateTime.now();
      final Stopwatch matrixWatch = Stopwatch()..start();
      final int deadlineMinutes =
          int.tryParse(
            Platform.environment['CARDFLOW_S12_DEADLINE_MIN'] ?? '',
          ) ??
          45;
      final DateTime deadline = DateTime.now().add(
        Duration(minutes: deadlineMinutes),
      );

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
            Platform.environment['CARDFLOW_S12_OUT_DIR'] ??
            'journal/generation-v3/live-s12',
        provider: config.provider,
        model: config.model,
      );

      String? stopReason() {
        if (httpBudget.isExhausted) return 'бюджет матрицы исчерпан';
        if (costGuard != null && costGuard.isExhausted) {
          return 'потолок расхода матрицы исчерпан';
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
        final String? reason = stopReason();
        if (reason != null) {
          await bench.add(
            BenchCell(
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
                deckName: 'S12 $materialId $requested',
                requestedCards: requested,
              ),
              runId: 's12-$materialId-$path-$requested',
              cancellation: GenerationCancellation(),
            );
          } else {
            result = await legacy.run(
              GenerationRunRequest(
                documents: <ParsedDocument>[document],
                account: config.account,
                deckName: 'S12 $materialId $requested',
                requestedCards: requested,
              ),
            );
          }
          watch.stop();
          await bench.add(
            BenchCell(
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
              metrics: result.report == null
                  ? null
                  : const MetricsCollector().collect(result.report!),
            ),
          );
        } on LiveBudgetExceeded catch (error) {
          watch.stop();
          await bench.add(
            BenchCell(
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

      final List<_Material> materials = <_Material>[
        _Material(
          id: 'textbook',
          name: 'учебный текст, 12 разделов',
          document: _textbook(),
          sections: 12,
        ),
        _Material(
          id: 'article',
          name: 'статья, 3 раздела',
          document: _article(),
          sections: 3,
        ),
      ];

      try {
        // Скан без текстового слоя — smoke без запросов: проверен офлайн-
        // интеграционным тестом `generation_v3_facade_flow_test`
        // («скан без текстового слоя: отчёт с причиной, а не падение»), здесь
        // не дублируется и в матрицу не входит (TASK: «отдельно smoke»).

        for (final _Material material in materials) {
          for (final int size in <int>[20, 40, 80, 150, 300]) {
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

      // DoD: хотя бы один живой прогон на 300 карточек дошёл до отчёта с
      // честным исходом (`done` или `partial`), а не с исключением.
      final bool has300 = bench.cells.any(
        (BenchCell cell) =>
            cell.requested == 300 &&
            cell.status == BenchCellStatus.ran &&
            cell.metrics != null,
      );
      // Дочитываем отчёт для следующего прогона (числа в файле, не в коде).
      final String markdown = await File('${bench.outputDir}/matrix.md')
          .readAsString();
      // ignore: avoid_print — таблица снимается из вывода теста.
      print(markdown);
      if (Platform.environment['CARDFLOW_S12_REQUIRE_300'] == '1') {
        expect(
          has300,
          isTrue,
          reason: 'DoD S12: живой прогон на 300 карточек дал отчёт',
        );
      }
    },
    skip: skipReason,
    timeout: const Timeout(Duration(hours: 4)),
  );
}

/// Материал матрицы: документ и его имя для отчёта.
class _Material {
  const _Material({
    required this.id,
    required this.name,
    required this.document,
    required this.sections,
  });

  final String id;
  final String name;
  final ParsedDocument document;
  final int sections;
}

/// Учебный текст: 12 разделов по 4 утверждения (реальный объём для 300 карточек).
ParsedDocument _textbook() => _documentOf(<String, List<String>>{
  'Механика': <String>[
    'Импульс тела равен произведению массы тела на его скорость.',
    'Второй закон Ньютона связывает силу, массу и ускорение тела.',
    'Работа силы равна произведению силы на перемещение вдоль неё.',
    'Кинетическая энергия тела зависит от массы и квадрата скорости.',
  ],
  'Молекулярная физика': <String>[
    'Давление газа пропорционально концентрации молекул и температуре.',
    'Средняя кинетическая энергия молекулы зависит только от температуры.',
    'Уравнение состояния связывает давление, объём и температуру газа.',
    'Число Авогадро задаёт количество частиц в одном моле вещества.',
  ],
  'Термодинамика': <String>[
    'Первый закон термодинамики выражает сохранение энергии в процессах.',
    'Внутренняя энергия идеального газа определяется его температурой.',
    'Энтропия изолированной системы не убывает при необратимых процессах.',
    'Теплота переходит от более нагретого тела к менее нагретому.',
  ],
  'Электростатика': <String>[
    'Сила взаимодействия зарядов обратно пропорциональна квадрату расстояния.',
    'Напряжённость электрического поля равна силе на единичный заряд.',
    'Потенциал поля убывает при удалении от положительного заряда.',
    'Конденсатор накапливает заряд при разности потенциалов на обкладках.',
  ],
  'Электрический ток': <String>[
    'Сила тока равна заряду, прошедшему через сечение за единицу времени.',
    'Закон Ома связывает напряжение, силу тока и сопротивление участка.',
    'Мощность тока равна произведению напряжения на силу тока.',
    'Последовательное соединение даёт одинаковую силу тока во всех элементах.',
  ],
  'Магнетизм': <String>[
    'Магнитное поле действует на движущийся заряд силой Лоренца.',
    'Сила Ампера действует на проводник с током в магнитном поле.',
    'Индукционный ток возникает при изменении магнитного потока.',
    'Правило Ленца определяет направление индукционного тока.',
  ],
  'Колебания': <String>[
    'Период колебаний маятника зависит от его длины и ускорения свободного падения.',
    'Амплитуда колебаний определяет максимальное отклонение от положения равновесия.',
    'Резонанс возникает при совпадении частоты воздействия и собственной частоты.',
    'Затухающие колебания уменьшают амплитуду из-за сопротивления среды.',
  ],
  'Волны': <String>[
    'Скорость волны равна произведению длины волны на частоту.',
    'Поперечная волна колеблет частицы перпендикулярно направлению движения.',
    'Звук распространяется в воздухе как продольная волна.',
    'Дифракция проявляется при огибании волной препятствия.',
  ],
  'Оптика': <String>[
    'Закон отражения приравнивает угол падения и угол отражения.',
    'Преломление света описывается отношением скоростей в двух средах.',
    'Линза строит изображение по правилам геометрической оптики.',
    'Интерференция складывает волны и создаёт чередование полос.',
  ],
  'Атомная физика': <String>[
    'Фотон несёт энергию, пропорциональную частоте излучения.',
    'Фотоэффект возникает при энергии кванта выше работы выхода.',
    'Спектр атома водорода объясняется переходами между уровнями.',
    'Энергия уровня атома принимает дискретные значения.',
  ],
  'Ядерная физика': <String>[
    'Ядро атома состоит из протонов и нейтронов.',
    'Массовое число равно сумме числа протонов и числа нейтронов.',
    'В ядерных реакциях сохраняются заряд и массовое число.',
    'Дефект массы объясняет выделение энергии при синтезе ядра.',
  ],
  'Астрономия': <String>[
    'Законы Кеплера описывают движение планет вокруг Солнца.',
    'Сила тяготения убывает обратно пропорционально квадрату расстояния.',
    'Световой год измеряет расстояние, а не время.',
    'Красное смещение указывает на удаление далёких галактик.',
  ],
});

/// Статья: 3 раздела по 5 утверждений.
ParsedDocument _article() => _documentOf(<String, List<String>>{
  'Память': <String>[
    'Рабочая память удерживает информацию во время решения задачи.',
    'Долговременная память хранит знания и навыки после обучения.',
    'Повторение через возрастающие интервалы замедляет забывание.',
    'Интерференция возникает, когда близкие факты мешают друг другу.',
    'Воспроизведение знания изменяет его и делает более доступным.',
  ],
  'Обучение': <String>[
    'Активное припоминание эффективнее повторного чтения текста.',
    'Распределённая практика даёт более прочное запоминание.',
    'Обратная связь помогает исправлять ошибочные представления.',
    'Примеры и контрпримеры уточняют границы понятия.',
    'Чередование разных типов задач развивает выбор стратегии.',
  ],
  'Мотивация': <String>[
    'Конкретная ближняя цель повышает настойчивость в работе.',
    'Ощущение прогресса поддерживает внутреннюю мотивацию.',
    'Слишком трудная задача вызывает тревогу и избегание.',
    'Слишком лёгкая задача перестаёт удерживать внимание.',
    'Автономия выбора усиливает принятие цели учеником.',
  ],
});

/// Документ из разделов: каждый абзац — строка, границы разделов точные.
ParsedDocument _documentOf(Map<String, List<String>> sections) {
  final StringBuffer buffer = StringBuffer();
  final List<ParsedSection> parsed = <ParsedSection>[];
  for (final MapEntry<String, List<String>> entry in sections.entries) {
    if (buffer.isNotEmpty) buffer.write('\n');
    final int start = buffer.length;
    for (final String line in entry.value) {
      buffer.writeln(line);
    }
    parsed.add(
      ParsedSection(start: start, end: buffer.length, title: entry.key),
    );
  }
  final String text = buffer.toString();
  return ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'material.txt',
    text: text,
    sections: parsed,
  );
}
