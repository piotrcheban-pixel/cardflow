/// Стенд «было → стало» среза 12: записи матрицы и markdown-таблица.
///
/// Вход — только [GenerationReport] и числа бюджета; [MetricsCollector]
/// считает метрики из отчёта, поэтому ни одно число таблицы не набирается
/// руками (TASK «Срез 12», п. 4–5). Текстов материалов и ключей в отчёте нет:
/// только имена материалов, размеры, пути и машинные коды.
library;

import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/metrics_collector.dart';

/// Статус ячейки матрицы.
enum BenchCellStatus {
  /// Прогон выполнен (даже если результат `partial`/`failed` — это результат).
  ran,

  /// Ячейка не запускалась: причина в [BenchCell.reason].
  notRun,

  /// Прогон упал до отчёта (исключение транспорта/бюджета).
  failed,
}

/// Одна ячейка матрицы: материал × размер × путь.
class BenchCell {
  /// Создаёт запись ячейки.
  const BenchCell({
    required this.material,
    required this.materialSections,
    required this.requested,
    required this.path,
    required this.status,
    this.reason,
    this.durationMs,
    this.errorCode,
    this.metrics,
    this.stage,
    this.reportAccepted,
    this.reportRequested,
    this.understandingFailures = const <String>[],
  });

  /// Имя материала (`учебный текст 12 разделов`, `статья 3 раздела`, `скан`).
  final String material;

  /// Сколько разделов в материале (0 — скан без текстового слоя).
  final int materialSections;

  /// Заказ карточек.
  final int requested;

  /// Путь: `legacy` или `v3`.
  final String path;

  /// Статус ячейки.
  final BenchCellStatus status;

  /// Причина `not_run`/`failed` (числа и машинные коды, без текстов материалов).
  final String? reason;

  /// Длительность прогона стенными часами.
  final int? durationMs;

  /// Код ошибки прогона, если он упал.
  final String? errorCode;

  /// Метрики из отчёта (`null` — отчёта нет).
  final CollectedMetrics? metrics;

  /// Терминальный этап отчёта.
  final String? stage;

  /// «Принято N из M» из отчёта (для честной сверки с заказом).
  final int? reportAccepted;

  /// Заказ из отчёта (он же — заказ прогона).
  final int? reportRequested;

  /// Причины отсутствия карты знаний (например, `no_text_layer`).
  final List<String> understandingFailures;

  /// JSON-строка для `matrix.jsonl`.
  Map<String, Object?> toJson() => <String, Object?>{
    'material': material,
    'material_sections': materialSections,
    'requested': requested,
    'path': path,
    'status': status.name,
    'reason': reason,
    'duration_ms': durationMs,
    'error_code': errorCode,
    'stage': stage,
    'report_accepted': reportAccepted,
    'report_requested': reportRequested,
    'understanding_failures': understandingFailures,
    'metrics': metrics?.toJson(),
  };
}

/// Накапливает ячейки, пишет `matrix.jsonl` и `matrix.md`.
class S12Bench {
  /// Создаёт стенд; [outputDir] — каталог отчёта (обычно
  /// `journal/generation-v3/live-s12`).
  S12Bench({
    required this.outputDir,
    required this.provider,
    required this.model,
  });

  /// Каталог отчёта.
  final String outputDir;

  /// Провайдер прогона (id пресета).
  final String provider;

  /// Модель прогона.
  final String model;

  final List<BenchCell> _cells = <BenchCell>[];

  /// Сколько ячеек уже записано.
  int get cellCount => _cells.length;

  /// Все ячейки в порядке прогона.
  List<BenchCell> get cells => List<BenchCell>.unmodifiable(_cells);

  /// Добавляет ячейку и немедленно дописывает JSONL (сбой прогона не теряет
  /// уже измеренные значения).
  Future<void> add(BenchCell cell) async {
    _cells.add(cell);
    final Directory directory = Directory(outputDir);
    await directory.create(recursive: true);
    await File('$outputDir/matrix.jsonl').writeAsString(
      '${jsonEncode(cell.toJson())}\n',
      mode: FileMode.append,
      flush: true,
    );
    await writeMarkdown();
  }

  /// Пишет markdown-таблицу из накопленных ячеек (без ручных чисел).
  Future<void> writeMarkdown() async {
    final Directory directory = Directory(outputDir);
    await directory.create(recursive: true);
    await File('$outputDir/matrix.md').writeAsString(_markdown(), flush: true);
  }

  /// Пишет сводку прогона (провайдер, модель, бюджеты, исход).
  Future<void> writeRunSummary(Map<String, Object?> summary) async {
    final Directory directory = Directory(outputDir);
    await directory.create(recursive: true);
    await File('$outputDir/run.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(<String, Object?>{
        'provider': provider,
        'model': model,
        ...summary,
      }),
      flush: true,
    );
  }

  String _markdown() {
    final StringBuffer buffer = StringBuffer()
      ..writeln('# Срез 12 — матрица живых прогонов')
      ..writeln()
      ..writeln('**Провайдер:** $provider · **Модель:** $model')
      ..writeln()
      ..writeln(
        '`cleanRate` = принято без warning / принято; `coverage` — доля '
        'единиц (v3) или разделов (legacy) с принятой карточкой; '
        '`yield` — принято на 1000 входных токенов; `req/10` — запросов на '
        '10 принятых; `p50/p95` — длительность запроса модели. '
        '`—` — данных нет (например, у legacy нет карты знаний и salience), '
        '`not_run` — ячейка не запускалась (причина в последней колонке).',
      )
      ..writeln()
      ..writeln(
        '| Материал | Разд. | Заказ | Путь | Статус | Принято | cleanRate | '
        'coverage | yield | req/10 | Дубли | p50/p95, мс | Причина/код |',
      )
      ..writeln(
        '|---|---:|---:|---|---|---:|---:|---:|---:|---:|---:|---|---|',
      );
    for (final BenchCell cell in _cells) {
      final CollectedMetrics? metrics = cell.metrics;
      buffer.writeln(
        '| ${cell.material} | ${cell.materialSections} | ${cell.requested} | '
        '${cell.path} | ${_statusText(cell)} | '
        '${cell.reportAccepted ?? '—'}${cell.reportRequested == null ? '' : '/${cell.reportRequested}'} | '
        '${_percent(metrics?.cleanRate)} | '
        '${_percent(metrics?.coverage)} | '
        '${_number(metrics?.yieldPer1kInputTokens, digits: 2)} | '
        '${_number(metrics?.requestsPer10Cards, digits: 2)} | '
        '${metrics == null ? '—' : metrics.duplicates} | '
        '${_latency(metrics)} | '
        '${_reason(cell)} |',
      );
    }
    buffer
      ..writeln()
      ..writeln('## Сводка')
      ..writeln();
    final int ran = _cells
        .where((BenchCell cell) => cell.status == BenchCellStatus.ran)
        .length;
    buffer.writeln(
      'Ячеек: ${_cells.length}; выполнено: $ran; '
      'not_run: ${_cells.where((BenchCell c) => c.status == BenchCellStatus.notRun).length}; '
      'failed: ${_cells.where((BenchCell c) => c.status == BenchCellStatus.failed).length}.',
    );
    return buffer.toString();
  }

  static String _statusText(BenchCell cell) => switch (cell.status) {
    BenchCellStatus.ran => 'ran',
    BenchCellStatus.notRun => 'not_run',
    BenchCellStatus.failed => 'failed',
  };

  static String _reason(BenchCell cell) {
    if (cell.reason != null && cell.reason!.isNotEmpty) {
      return '${cell.reason}${cell.errorCode == null ? '' : ' (${cell.errorCode})'}';
    }
    if (cell.understandingFailures.isNotEmpty) {
      return cell.understandingFailures.join(', ');
    }
    if (cell.stage != null && cell.stage != 'ready') return cell.stage!;
    return '—';
  }

  static String _percent(double? value) =>
      value == null ? '—' : '${(value * 100).toStringAsFixed(1)} %';

  static String _number(double? value, {int digits = 2}) =>
      value == null ? '—' : value.toStringAsFixed(digits);

  static String _latency(CollectedMetrics? metrics) {
    if (metrics == null) return '—';
    final Duration? p50 = metrics.p50BatchDuration;
    final Duration? p95 = metrics.p95BatchDuration;
    if (p50 == null && p95 == null) return '—';
    return '${p50?.inMilliseconds ?? '—'}/${p95?.inMilliseconds ?? '—'}';
  }
}

/// Возвращает метрики из отчёта или `null` со сроком жизни в комментарии.
CollectedMetrics? collectOf(GenerationReport? report) =>
    report == null ? null : const MetricsCollector().collect(report);
